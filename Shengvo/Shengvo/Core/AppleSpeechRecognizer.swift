import Foundation
import Speech

class AppleSpeechRecognizer {
    private let recognizer: SFSpeechRecognizer?

    init?(locale: Locale = Locale(identifier: "zh-CN")) {
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            print("[AppleSpeech] SFSpeechRecognizer not available for \(locale.identifier)")
            return nil
        }
        self.recognizer = r
    }

    /// 使用文件 URL 进行语音识别（WAV 文件）
    func recognize(audioFileURL: URL, timeout: TimeInterval = 15, completion: @escaping (Result<String, Error>) -> Void) {
        guard let recognizer = recognizer else {
            completion(.failure(AppleSpeechError.notAvailable))
            return
        }

        // 检查授权状态
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        self.performRecognition(recognizer: recognizer, url: audioFileURL, timeout: timeout, completion: completion)
                    } else {
                        completion(.failure(AppleSpeechError.unauthorized))
                    }
                }
            }
        case .authorized:
            performRecognition(recognizer: recognizer, url: audioFileURL, timeout: timeout, completion: completion)
        default:
            completion(.failure(AppleSpeechError.unauthorized))
        }
    }

    private func performRecognition(recognizer: SFSpeechRecognizer, url: URL, timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        var completed = false
        let timer = DispatchWorkItem {
            if !completed {
                completed = true
                recognizer.recognitionTask(with: request) { _, _ in }
                completion(.failure(AppleSpeechError.timeout))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)

        recognizer.recognitionTask(with: request) { result, error in
            if completed { return }

            if let error = error {
                completed = true
                timer.cancel()
                print("[AppleSpeech] Recognition error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if let result = result, result.isFinal {
                completed = true
                timer.cancel()
                let text = result.bestTranscription.formattedString
                print("[AppleSpeech] Recognized: \(text)")
                completion(.success(text))
            }
        }
    }
}

enum AppleSpeechError: LocalizedError {
    case notAvailable
    case unauthorized
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Apple Speech 不可用"
        case .unauthorized: return "语音识别权限未授权"
        case .timeout: return "Apple Speech 识别超时"
        }
    }
}
