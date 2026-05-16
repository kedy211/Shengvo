import Foundation

// MARK: - Binary Protocol Constants

/// 消息类型 (4 bits)
enum SauceMessageType: UInt8 {
    case fullClientRequest = 0x1
    case audioOnlyRequest  = 0x2
    case fullServerResponse = 0x9
    case errorMessage      = 0xF
}

/// 标志位 (4 bits)
enum SauceFlags: UInt8 {
    case noSequence       = 0x0  // 无序列号
    case positiveSequence = 0x1  // 正序列号
    case lastNoSequence   = 0x2  // 最后一包，无序列号
    case lastNegativeSeq  = 0x3  // 最后一包，负序列号
}

/// 序列化方式 (4 bits)
private let sauceSerializationJSON: UInt8 = 0x1
private let sauceSerializationNone: UInt8 = 0x0

/// 压缩方式 (4 bits)
private let sauceCompressionNone: UInt8 = 0x0
private let sauceCompressionGzip: UInt8 = 0x1

// MARK: - Binary Frame Encoding

/// 构造 4 字节二进制协议 Header
/// Byte 0: [version:4][header_size:4]  (version=1, header_size=1 → 0x11)
/// Byte 1: [msg_type:4][flags:4]
/// Byte 2: [serialization:4][compression:4]
/// Byte 3: [reserved:8] (0x00)
private func makeHeader(msgType: SauceMessageType, flags: SauceFlags,
                         serialization: UInt8, compression: UInt8) -> Data {
    var bytes = [UInt8](repeating: 0, count: 4)
    bytes[0] = 0x11  // version=1, header_size=1
    bytes[1] = (msgType.rawValue << 4) | flags.rawValue
    bytes[2] = (serialization << 4) | compression
    bytes[3] = 0x00
    return Data(bytes)
}

/// 4 字节大端无符号整数
private func bigEndianUInt32(_ value: UInt32) -> Data {
    var v = value.bigEndian
    return Data(bytes: &v, count: 4)
}

/// 4 字节大端有符号整数
private func bigEndianInt32(_ value: Int32) -> Data {
    var v = value.bigEndian
    return Data(bytes: &v, count: 4)
}

/// 构造客户端帧: [Header(4)] [PayloadSize(4B BE)] [Payload]
private func makeClientFrame(msgType: SauceMessageType, flags: SauceFlags,
                              serialization: UInt8, compression: UInt8,
                              payload: Data) -> Data {
    let header = makeHeader(msgType: msgType, flags: flags,
                            serialization: serialization, compression: compression)
    var frame = Data()
    frame.append(header)
    frame.append(bigEndianUInt32(UInt32(payload.count)))
    frame.append(payload)
    return frame
}

/// 构造带序列号的客户端帧: [Header(4)] [Sequence(4B BE)] [PayloadSize(4B BE)] [Payload]
private func makeClientFrameWithSeq(msgType: SauceMessageType, flags: SauceFlags,
                                     serialization: UInt8, compression: UInt8,
                                     sequence: Int32, payload: Data) -> Data {
    let header = makeHeader(msgType: msgType, flags: flags,
                            serialization: serialization, compression: compression)
    var frame = Data()
    frame.append(header)
    frame.append(bigEndianInt32(sequence))
    frame.append(bigEndianUInt32(UInt32(payload.count)))
    frame.append(payload)
    return frame
}

// MARK: - Gzip Compression (via zlib from bridging header)

private func gzipCompress(_ data: Data) -> Data? {
    guard !data.isEmpty else { return nil }

    var strm = z_stream()
    strm.zalloc = nil
    strm.zfree = nil
    strm.opaque = nil

    // windowBits = 15 + 16 = gzip format
    let windowBits: Int32 = 15 + 16
    let result = deflateInit2_(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                                windowBits, 8, Z_DEFAULT_STRATEGY,
                                ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard result == Z_OK else { return nil }
    defer { deflateEnd(&strm) }

    let chunkSize = 16384
    var output = Data()

    _ = data.withUnsafeBytes { (inputPtr: UnsafeRawBufferPointer) in
        strm.next_in = UnsafeMutablePointer<Bytef>(mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!)
        strm.avail_in = uInt(inputPtr.count)

        repeat {
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                strm.next_out = bufPtr.baseAddress
                strm.avail_out = uInt(bufPtr.count)
                let ret = deflate(&strm, Z_FINISH)
                output.append(bufPtr.baseAddress!, count: bufPtr.count - Int(strm.avail_out))
                if ret == Z_STREAM_END { return }
            }
        } while strm.avail_out == 0
    }

    return output
}

// MARK: - PCM Conversion

/// Float32 PCM → Int16 PCM (little-endian)
private func floatToInt16PCM(_ samples: [Float]) -> Data {
    var data = Data(capacity: samples.count * 2)
    for sample in samples {
        let clamped = max(-1.0, min(1.0, sample))
        var intSample = Int16(clamped * 32767)
        withUnsafeBytes(of: &intSample) { data.append(contentsOf: $0) }
    }
    return data
}

// MARK: - BigModelWS

class BigModelWS {

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    // 确保回调始终在主线程执行
    private func dispatchPartial(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.dispatchPartial(text) }
    }
    private func dispatchFinal(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.dispatchFinal(text) }
    }
    private func dispatchError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in self?.dispatchError(error) }
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var sequence: Int = 0
    private var isConnected = false
    private var isFinishing = false

    private let wsURL = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    private let resourceID: String

    init(resourceID: String = "volc.bigasr.sauc.duration") {
        self.resourceID = resourceID
    }

    // MARK: - Connection

    func connect(appID: String, accessToken: String) {
        guard !isConnected else { return }

        guard let url = URL(string: wsURL) else {
            dispatchError(BigModelWSError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.addValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.addValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.addValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")

        let connectID = UUID().uuidString
        request.addValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")

        urlSession = URLSession(configuration: .default)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        print("[BigModelWS] Connecting to \(wsURL)...")
        sendFullClientRequest()
        startReceiveLoop()
        isConnected = true
    }

    // MARK: - Send Audio Chunk

    /// 发送 PCM 音频分片
    /// - Parameters:
    ///   - pcmSamples: Float32 PCM 样本 (16kHz, mono)
    ///   - isLast: 是否为最后一包
    func sendAudioChunk(pcmSamples: [Float], isLast: Bool) {
        guard isConnected, !pcmSamples.isEmpty || isLast else { return }

        let pcmData: Data
        if !pcmSamples.isEmpty {
            pcmData = floatToInt16PCM(pcmSamples)
        } else {
            // 最后一包可能为空（仅发送结束标志）
            pcmData = Data()
        }

        guard let compressed = gzipCompress(pcmData) else {
            print("[BigModelWS] Gzip compression failed")
            return
        }

        let flags: SauceFlags = isLast ? .lastNegativeSeq : .positiveSequence
        let seqValue: Int32 = isLast ? -1 : Int32(sequence)

        let frame = makeClientFrameWithSeq(
            msgType: .audioOnlyRequest,
            flags: flags,
            serialization: sauceSerializationNone,
            compression: sauceCompressionGzip,
            sequence: seqValue,
            payload: compressed
        )

        webSocketTask?.send(.data(frame)) { [weak self] error in
            if let error = error {
                print("[BigModelWS] Send audio chunk error: \(error)")
                self?.dispatchError(error)
            }
        }

        if !isLast {
            sequence += 1
        }

        print("[BigModelWS] Sent audio chunk seq=\(isLast ? "LAST" : "\(sequence)"), "
              + "samples=\(pcmSamples.count), compressed=\(compressed.count)B")
    }

    /// 结束流式识别：发送剩余样本 + 最后一包，等待最终结果
    func finish(remainingSamples: [Float], timeout: TimeInterval,
                completion: @escaping (Result<String, Error>) -> Void) {
        isFinishing = true

        // 如果有剩余样本，先发送最后一个数据包
        if !remainingSamples.isEmpty {
            sendAudioChunk(pcmSamples: remainingSamples, isLast: true)
        } else {
            // 发送空内容的最后一包
            sendAudioChunk(pcmSamples: [], isLast: true)
        }

        // 超时计时器
        var done = false
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard !done else { return }
            done = true
            print("[BigModelWS] Finish timeout")
            self?.cancel()
            DispatchQueue.main.async {
                completion(.failure(BigModelWSError.timeout))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        onFinalResult = { [weak self] text in
            guard !done, let self else { return }
            done = true
            timeoutWork.cancel()
            print("[BigModelWS] Final result received: \(text.prefix(50))...")
            self.cancel()
            completion(.success(text))
        }

        onError = { [weak self] error in
            guard !done, let self else { return }
            done = true
            timeoutWork.cancel()
            print("[BigModelWS] Error during finish: \(error)")
            self.cancel()
            completion(.failure(error))
        }
    }

    // MARK: - Cancel

    func cancel() {
        print("[BigModelWS] Cancelling...")
        isConnected = false
        isFinishing = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sequence = 0
    }

    // MARK: - Private: Full Client Request

    private func sendFullClientRequest() {
        let config: [String: Any] = [
            "user": ["uid": "shengvo"],
            "audio": [
                "format": "pcm",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "language": "zh-CN"
            ],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "enable_nostream": true,
                "result_type": "single"
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let compressed = gzipCompress(jsonData) else {
            dispatchError(BigModelWSError.invalidConfig)
            return
        }

        let frame = makeClientFrame(
            msgType: .fullClientRequest,
            flags: .noSequence,
            serialization: sauceSerializationJSON,
            compression: sauceCompressionGzip,
            payload: compressed
        )

        webSocketTask?.send(.data(frame)) { error in
            if let error = error {
                print("[BigModelWS] Send full client request error: \(error)")
                self.dispatchError(error)
            } else {
                print("[BigModelWS] Full client request sent")
            }
        }
    }

    // MARK: - Private: Receive Loop

    private func startReceiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(.data(let data)):
                self.handleServerFrame(data)
            case .success(.string(let text)):
                print("[BigModelWS] Unexpected text frame: \(text)")
            case .failure(let error):
                print("[BigModelWS] Receive error: \(error)")
                if self.isConnected {
                    self.dispatchError(error)
                }
                self.isConnected = false
                return
            }

            // 继续接收
            if self.isConnected {
                self.startReceiveLoop()
            }
        }
    }

    // MARK: - Private: Parse Server Response

    private func handleServerFrame(_ data: Data) {
        guard data.count >= 4 else {
            print("[BigModelWS] Frame too short: \(data.count) bytes")
            return
        }

        let header = data.prefix(4)
        let msgTypeRaw = (header[1] >> 4) & 0x0F

        guard let msgType = SauceMessageType(rawValue: msgTypeRaw) else {
            print("[BigModelWS] Unknown message type: \(msgTypeRaw)")
            return
        }

        switch msgType {
        case .fullServerResponse:
            parseServerResponse(data)
        case .errorMessage:
            parseErrorMessage(data)
        default:
            print("[BigModelWS] Unexpected message type from server: \(msgTypeRaw)")
        }
    }

    private func parseServerResponse(_ data: Data) {
        // Server frame: Header(4) + Sequence(4) + PayloadSize(4) + Payload
        guard data.count >= 12 else {
            print("[BigModelWS] Server response too short: \(data.count)")
            return
        }

        let sequenceValue = data.subdata(in: 4..<8).withUnsafeBytes {
            Int32(bigEndian: $0.load(as: Int32.self))
        }

        let payloadSize = data.subdata(in: 8..<12).withUnsafeBytes {
            Int($0.load(as: UInt32.self).bigEndian)
        }

        guard data.count >= 12 + payloadSize else {
            print("[BigModelWS] Incomplete payload: expected \(payloadSize), got \(data.count - 12)")
            return
        }

        let payload = data.subdata(in: 12..<(12 + payloadSize))

        // Parse JSON
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            print("[BigModelWS] Failed to parse server JSON")
            return
        }

        // Extract text from result
        if let result = json["result"] as? [String: Any],
           let text = result["text"] as? String {
            let isDefinite = (json["utterances"] as? [[String: Any]])?.contains { utterance in
                (utterance["definite"] as? Bool) == true
            } ?? false

            print("[BigModelWS] Response seq=\(sequenceValue), definite=\(isDefinite), "
                  + "text=\(text.prefix(50))")

            if isDefinite || isFinishing {
                // Final result
                dispatchFinal(text)
            } else {
                // Partial result
                dispatchPartial(text)
            }
        }
    }

    private func parseErrorMessage(_ data: Data) {
        // Error frame: Header(4) + ErrorCode(4) + ErrorMsgSize(4) + ErrorMsg
        guard data.count >= 12 else { return }

        let errorCode = data.subdata(in: 4..<8).withUnsafeBytes {
            Int32(bigEndian: $0.load(as: Int32.self))
        }

        let msgSize = data.subdata(in: 8..<12).withUnsafeBytes {
            Int($0.load(as: UInt32.self).bigEndian)
        }

        var errorMsg = "Unknown error"
        if data.count >= 12 + msgSize {
            errorMsg = String(data: data.subdata(in: 12..<(12 + msgSize)), encoding: .utf8) ?? errorMsg
        }

        print("[BigModelWS] Server error code=\(errorCode), msg=\(errorMsg)")
        dispatchError(BigModelWSError.serverError(Int(errorCode), errorMsg))
    }
}

// MARK: - Errors

enum BigModelWSError: LocalizedError {
    case invalidURL
    case invalidConfig
    case timeout
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WebSocket URL"
        case .invalidConfig: return "Failed to encode Full Client Request"
        case .timeout: return "Streaming ASR timed out"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        }
    }
}
