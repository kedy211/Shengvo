import Foundation

class ASRService {
    private let config: AppConfig

    init(config: AppConfig = .shared) {
        self.config = config
    }

    func recognize(audioData: Data, completion: @escaping (Result<String, Error>) -> Void) {
        let taskID = UUID().uuidString

        // Step 1: Submit task
        let submitURL = "https://openspeech-direct.zijieapi.com/api/v3/auc/bigmodel/submit"
        guard let url = URL(string: submitURL) else {
            completion(.failure(ASRError.invalidURL))
            return
        }

        var submitRequest = URLRequest(url: url)
        submitRequest.httpMethod = "POST"
        submitRequest.timeoutInterval = 30
        submitRequest.addValue(config.asrAppID, forHTTPHeaderField: "X-Api-App-Key")
        submitRequest.addValue(config.asrAccessToken, forHTTPHeaderField: "X-Api-Access-Key")
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

        // Add custom words if set (boosting context for better recognition)
        if !config.customWords.isEmpty {
            let contextStr = config.customWords.joined(separator: "，")
            requestDict["boostingtext"] = contextStr
            print("[ASR] Custom words (boostingtext): \(contextStr)")
        }

        let requestBody: [String: Any] = [
            "user": ["uid": "voice_input"],
            "audio": ["data": base64Audio],
            "request": requestDict
        ]

        submitRequest.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

        print("[ASR] Submitting task \(taskID), audio: \(audioData.count) bytes")

        let submitTask = URLSession.shared.dataTask(with: submitRequest) { [weak self] data, response, error in
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

            // Check response headers for status
            if let apiStatus = httpResponse.allHeaderFields["X-Api-Status-Code"] as? String {
                print("[ASR] API status code: \(apiStatus)")
                if apiStatus != "20000000" && apiStatus != "20000001" && apiStatus != "20000002" {
                    let msg = httpResponse.allHeaderFields["X-Api-Message"] as? String ?? "Unknown"
                    print("[ASR] Submit failed: \(msg)")
                    completion(.failure(ASRError.httpError(statusCode, msg)))
                    return
                }
            }

            // Step 2: Poll for result
            self.pollResult(taskID: taskID, completion: completion)
        }
        submitTask.resume()
    }

    private func pollResult(taskID: String, completion: @escaping (Result<String, Error>) -> Void) {
        let queryURL = "https://openspeech-direct.zijieapi.com/api/v3/auc/bigmodel/query"
        guard let url = URL(string: queryURL) else {
            completion(.failure(ASRError.invalidURL))
            return
        }

        var queryRequest = URLRequest(url: url)
        queryRequest.httpMethod = "POST"
        queryRequest.timeoutInterval = 30
        queryRequest.addValue(config.asrAppID, forHTTPHeaderField: "X-Api-App-Key")
        queryRequest.addValue(config.asrAccessToken, forHTTPHeaderField: "X-Api-Access-Key")
        queryRequest.addValue("volc.bigasr.auc", forHTTPHeaderField: "X-Api-Resource-Id")
        queryRequest.addValue(taskID, forHTTPHeaderField: "X-Api-Request-Id")
        queryRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        queryRequest.httpBody = "{}".data(using: .utf8)

        let queryTask = URLSession.shared.dataTask(with: queryRequest) { [weak self] data, response, error in
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
                // Task finished
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    print("[ASR] Result JSON: \(json ?? [:])")

                    // Try to extract text from various possible response formats
                    if let result = json?["result"] as? [String: Any],
                       let text = result["text"] as? String, !text.isEmpty {
                        print("[ASR] Recognized: \(text)")
                        completion(.success(text))
                    } else if let text = json?["text"] as? String, !text.isEmpty {
                        print("[ASR] Recognized: \(text)")
                        completion(.success(text))
                    } else {
                        print("[ASR] No text in result")
                        completion(.failure(ASRError.emptyResult))
                    }
                } catch {
                    print("[ASR] Parse error: \(error)")
                    completion(.failure(error))
                }
            } else if apiStatus == "20000001" || apiStatus == "20000002" {
                // Still processing, poll again
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    self.pollResult(taskID: taskID, completion: completion)
                }
            } else {
                let msg = httpResponse.allHeaderFields["X-Api-Message"] as? String ?? "Unknown error"
                print("[ASR] Query failed: \(msg)")
                completion(.failure(ASRError.httpError(0, msg)))
            }
        }
        queryTask.resume()
    }
}

enum ASRError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case httpError(Int, String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .noData: return "No data received"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .emptyResult: return "No speech recognized"
        }
    }
}
