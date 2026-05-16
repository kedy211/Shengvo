import AVFoundation
import Foundation

class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    private var audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private var timer: Timer?
    private var currentLevel: Float = 0
    private var streamingReadPosition: Int = 0

    let sampleRate: Double = 16000
    let channels: AVAudioChannelCount = 1

    func startRecording() {
        audioBuffer.removeAll()
        streamingReadPosition = 0
        recordingDuration = 0

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += channelData[i] * channelData[i]
                }
                let rms = sqrt(sum / Float(frameLength))
                let level = min(1.0, rms * 15)
                DispatchQueue.main.async {
                    self.currentLevel = level
                }
            }

            if let convertedBuffer = self.convert(buffer: buffer, to: targetFormat) {
                let channelData = convertedBuffer.floatChannelData![0]
                let frameLength = Int(convertedBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                DispatchQueue.main.async {
                    self.audioBuffer.append(contentsOf: samples)
                }
            }
        }

        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    self?.recordingDuration += 0.1
                }
            }
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stopRecording(completion: @escaping (Data?) -> Void) {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        timer?.invalidate()

        DispatchQueue.main.async {
            self.isRecording = false
            self.currentLevel = 0
        }

        guard !audioBuffer.isEmpty else {
            completion(nil)
            return
        }

        let samples = audioBuffer
        audioBuffer.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            let wavData = AudioRecorder.encodeWAV(samples: samples, sampleRate: self.sampleRate)
            DispatchQueue.main.async {
                completion(wavData)
            }
        }
    }

    func cancelRecording() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        timer?.invalidate()
        audioBuffer.removeAll()
        streamingReadPosition = 0

        DispatchQueue.main.async {
            self.isRecording = false
            self.currentLevel = 0
        }
    }

    func getCurrentLevel() -> Float {
        return currentLevel
    }

    /// 非破坏性读取：提取指定数量的未消费 PCM 样本用于流式发送
    /// 不会从 audioBuffer 中移除，不影响最终 WAV 编码
    /// 仅从主线程调用（与 audioBuffer 追加同线程）
    func readStreamingChunk(sampleCount: Int = 3200) -> [Float]? {
        guard audioBuffer.count - streamingReadPosition >= sampleCount else {
            return nil
        }
        let chunk = Array(audioBuffer[streamingReadPosition..<(streamingReadPosition + sampleCount)])
        streamingReadPosition += sampleCount
        return chunk
    }

    /// 读取所有未消费的剩余样本
    func readAllRemainingSamples() -> [Float] {
        guard streamingReadPosition < audioBuffer.count else { return [] }
        let remaining = Array(audioBuffer[streamingReadPosition...])
        streamingReadPosition = audioBuffer.count
        return remaining
    }

    private func convert(buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error else { return nil }
        return outputBuffer
    }

    static func encodeWAV(samples: [Float], sampleRate: Double) -> Data {
        var data = Data()

        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = dataSize + 36

        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        var intSamples = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            intSamples[i] = Int16(clamped * 32767)
        }
        intSamples.withUnsafeBufferPointer { ptr in
            data.append(ptr)
        }

        return data
    }
}
