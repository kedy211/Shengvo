import Foundation
import whisper

class ASRService {
    private var whisperContext: WhisperActor?

    init() {}

    func recognize(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        switch AppConfig.shared.asrMode {
        case "cloud":
            recognizeCloud(audioData: audioData, completion: completion)
        case "qwen_cloud":
            recognizeQwenCloud(audioData: audioData, completion: completion)
        default:
            recognizeLocal(audioData: audioData, completion: completion)
        }
    }

    // MARK: - Local Whisper

    private func recognizeLocal(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                let context = try await self.getWhisperContext()
                let samples = ASRService.wavToFloatSamples(audioData)
                guard !samples.isEmpty else {
                    await MainActor.run { completion(.failure(ASRError.emptyAudio)) }
                    return
                }

                let text = try await context.transcribe(samples: samples, language: "zh", prompt: AppConfig.shared.customWords.joined(separator: "，"))
                await MainActor.run {
                    completion(.success(text))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func getWhisperContext() async throws -> WhisperActor {
        if let ctx = whisperContext { return ctx }

        let modelPath = try await ModelManager.shared.prepareModel()
        let ctx = try WhisperActor.create(modelPath: modelPath)
        whisperContext = ctx
        return ctx
    }

    static func wavToFloatSamples(_ wavData: Data) -> [Float] {
        guard wavData.count > 44 else { return [] }
        let pcmData = wavData.subdata(in: 44..<wavData.count)
        let sampleCount = pcmData.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        pcmData.withUnsafeBytes { raw in
            let int16Ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return samples
    }

    // MARK: - Cloud (Volcano Engine)

    private func recognizeCloud(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let taskID = UUID().uuidString

        let submitURL = "https://openspeech-direct.zijieapi.com/api/v3/auc/bigmodel/submit"
        guard let url = URL(string: submitURL) else {
            completion(.failure(ASRError.invalidURL))
            return
        }

        var submitRequest = URLRequest(url: url)
        submitRequest.httpMethod = "POST"
        submitRequest.timeoutInterval = 30
        submitRequest.addValue(AppConfig.shared.asrAppID, forHTTPHeaderField: "X-Api-App-Key")
        submitRequest.addValue(AppConfig.shared.asrAccessToken, forHTTPHeaderField: "X-Api-Access-Key")
        submitRequest.addValue("volc.bigasr.auc", forHTTPHeaderField: "X-Api-Resource-Id")
        submitRequest.addValue(taskID, forHTTPHeaderField: "X-Api-Request-Id")
        submitRequest.addValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        submitRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Audio = audioData.base64EncodedString()

        var requestDict: [String: Any] = [
            "model_name": "bigmodel",
            "enable_punc": true,
            "enable_itn": true,
            "enable_ddc": true
        ]

        if !AppConfig.shared.customWords.isEmpty {
            let contextStr = AppConfig.shared.customWords.joined(separator: "，")
            requestDict["boostingtext"] = contextStr
            print("[ASR] Custom words (boostingtext): \(contextStr)")
        }

        let requestBody: [String: Any] = [
            "user": ["uid": "shengvo"],
            "audio": ["data": base64Audio],
            "request": requestDict
        ]

        submitRequest.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        print("[ASR] Submitting task \(taskID), audio: \(audioData.count) bytes")

        URLSession.shared.dataTask(with: submitRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("[ASR] Submit error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ASRError.invalidResponse))
                return
            }

            let statusCode = httpResponse.statusCode
            print("[ASR] Submit response: \(statusCode)")

            if let apiStatus = httpResponse.allHeaderFields["X-Api-Status-Code"] as? String {
                print("[ASR] API status code: \(apiStatus)")
                if apiStatus != "20000000" && apiStatus != "20000001" && apiStatus != "20000002" {
                    let msg = httpResponse.allHeaderFields["X-Api-Message"] as? String ?? "Unknown"
                    print("[ASR] Submit failed: \(msg)")
                    completion(.failure(ASRError.httpError(statusCode, msg)))
                    return
                }
            }

            self.pollResult(taskID: taskID, attempt: 0, completion: completion)
        }.resume()
    }

    /// 自适应轮询间隔（ms）：200 → 350 → 550 → 800 → 1000（封顶）
    private func pollInterval(for attempt: Int) -> Double {
        switch attempt {
        case 0:  return 0.20
        case 1:  return 0.35
        case 2:  return 0.55
        case 3:  return 0.80
        default: return 1.00
        }
    }

    private func pollResult(taskID: String, attempt: Int, completion: @escaping (Result<String, Error>) -> Void) {
        let queryURL = "https://openspeech-direct.zijieapi.com/api/v3/auc/bigmodel/query"
        guard let url = URL(string: queryURL) else {
            completion(.failure(ASRError.invalidURL))
            return
        }

        var queryRequest = URLRequest(url: url)
        queryRequest.httpMethod = "POST"
        queryRequest.timeoutInterval = 30
        queryRequest.addValue(AppConfig.shared.asrAppID, forHTTPHeaderField: "X-Api-App-Key")
        queryRequest.addValue(AppConfig.shared.asrAccessToken, forHTTPHeaderField: "X-Api-Access-Key")
        queryRequest.addValue("volc.bigasr.auc", forHTTPHeaderField: "X-Api-Resource-Id")
        queryRequest.addValue(taskID, forHTTPHeaderField: "X-Api-Request-Id")
        queryRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        queryRequest.httpBody = "{}".data(using: .utf8)

        URLSession.shared.dataTask(with: queryRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("[ASR] Query error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let data = data else {
                completion(.failure(ASRError.invalidResponse))
                return
            }

            let apiStatus = httpResponse.allHeaderFields["X-Api-Status-Code"] as? String ?? ""
            print("[ASR] Query status: \(apiStatus)")

            if apiStatus == "20000000" {
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let result = json?["result"] as? [String: Any],
                       let text = result["text"] as? String, !text.isEmpty {
                        print("[ASR] Recognized: \(text)")
                        completion(.success(text))
                    } else if let text = json?["text"] as? String, !text.isEmpty {
                        print("[ASR] Recognized: \(text)")
                        completion(.success(text))
                    } else {
                        completion(.failure(ASRError.emptyResult))
                    }
                } catch {
                    print("[ASR] Parse error: \(error)")
                    completion(.failure(error))
                }
            } else if apiStatus == "20000001" || apiStatus == "20000002" {
                let delay = pollInterval(for: attempt)
                print("[ASR] Poll attempt \(attempt), waiting \(String(format: "%.0f", delay * 1000))ms")
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    self.pollResult(taskID: taskID, attempt: attempt + 1, completion: completion)
                }
            } else {
                let msg = httpResponse.allHeaderFields["X-Api-Message"] as? String ?? "Unknown error"
                print("[ASR] Query failed: \(msg)")
                completion(.failure(ASRError.httpError(0, msg)))
            }
        }.resume()
    }

    // MARK: - Cloud (Alibaba Qwen-ASR)

    private func recognizeQwenCloud(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let config = AppConfig.shared
        guard !config.asrQwenAPIKey.isEmpty else {
            completion(.failure(ASRError.httpError(0, "未配置阿里云 Qwen-ASR API Key")))
            return
        }

        let urlString = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            completion(.failure(ASRError.invalidURL))
            return
        }

        let base64Audio = audioData.base64EncodedString()
        let dataURL = "data:audio/wav;base64,\(base64Audio)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(config.asrQwenAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        var asrOptions: [String: Any] = [
            "enable_itn": false
        ]
        if !config.customWords.isEmpty {
            asrOptions["language"] = "zh"
        }

        let body: [String: Any] = [
            "model": "qwen3-asr-flash",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": dataURL
                            ]
                        ]
                    ]
                ]
            ],
            "asr_options": asrOptions
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("[Qwen-ASR] Sending request, audio: \(audioData.count) bytes")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[Qwen-ASR] Request error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ASRError.invalidResponse))
                return
            }

            print("[Qwen-ASR] Response status: \(httpResponse.statusCode)")

            guard let data = data else {
                completion(.failure(ASRError.noData))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // OpenAI-compatible format: choices[0].message.content
                    if let choices = json["choices"] as? [[String: Any]],
                       let first = choices.first,
                       let message = first["message"] as? [String: Any],
                       let content = message["content"] as? String,
                       !content.isEmpty {
                        print("[Qwen-ASR] Recognized: \(content)")
                        completion(.success(content))
                    }
                    // API error
                    else if let errorObj = json["error"] as? [String: Any],
                            let errorMsg = errorObj["message"] as? String {
                        print("[Qwen-ASR] API error: \(errorMsg)")
                        completion(.failure(ASRError.httpError(httpResponse.statusCode, errorMsg)))
                    }
                    else {
                        print("[Qwen-ASR] Empty result")
                        completion(.failure(ASRError.emptyResult))
                    }
                } else {
                    completion(.failure(ASRError.emptyResult))
                }
            } catch {
                print("[Qwen-ASR] JSON parse error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Whisper Actor (thread-safe wrapper)

actor WhisperActor {
    private var context: OpaquePointer

    private init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    static func create(modelPath: String) throws -> WhisperActor {
        var params = whisper_context_default_params()
        params.flash_attn = true
        let context = whisper_init_from_file_with_params(modelPath, params)
        guard let ctx = context else {
            throw ASRError.modelLoadFailed
        }
        return WhisperActor(context: ctx)
    }

    func transcribe(samples: [Float], language: String, prompt: String) throws -> String {
        let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(maxThreads)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.offset_ms = 0

        let result = language.withCString { lang -> Int32 in
            params.language = lang
            return prompt.withCString { p -> Int32 in
                params.initial_prompt = p
                whisper_reset_timings(context)
                return samples.withUnsafeBufferPointer { ptr in
                    whisper_full(context, params, ptr.baseAddress, Int32(samples.count))
                }
            }
        }

        guard result == 0 else {
            throw ASRError.inferenceFailed
        }

        var transcription = ""
        let segmentCount = whisper_full_n_segments(context)
        for i in 0..<segmentCount {
            if let cString = whisper_full_get_segment_text(context, i) {
                transcription += String(cString: cString)
            }
        }
        return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum ASRError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case httpError(Int, String)
    case emptyResult
    case emptyAudio
    case modelNotFound
    case modelLoadFailed
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 URL"
        case .invalidResponse: return "无效的响应"
        case .noData: return "未收到数据"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .emptyResult: return "未识别到语音内容"
        case .emptyAudio: return "音频数据为空"
        case .modelNotFound: return "Whisper 模型文件未找到"
        case .modelLoadFailed: return "Whisper 模型加载失败"
        case .inferenceFailed: return "Whisper 推理失败"
        }
    }
}
