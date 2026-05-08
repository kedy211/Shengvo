import Foundation

class LLMService {
    /// 多轮对话上下文（由调用方管理生命周期）
    var conversationContext = ConversationContext()

    /// 重置多轮上下文（切换场景、手动清空时调用）
    func resetContext() {
        conversationContext.reset()
        print("[LLM] Conversation context reset")
    }

    func processText(
        _ text: String,
        targetApp: String? = nil,
        mode: ProcessMode = .polish,
        priorTurns: [(raw: String, polished: String)] = [],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let config = AppConfig.shared
        guard config.llmEnabled else {
            completion(.success(text))
            return
        }

        let urlString = "\(config.llmBaseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        // 1. 组装系统提示词（基础块组合）
        var systemPrompt: String
        if let override = config.customSystemPromptOverride, !override.isEmpty {
            // 用户自定义覆盖模式
            systemPrompt = override
            // 但仍注入热词
            if !config.customWords.isEmpty {
                let hotwordLines = config.customWords.map { "- \($0)" }.joined(separator: "\n")
                systemPrompt += """


                热词（用户希望以下写法在输出中保持准确；当转写中出现这些词的同音/近形误识别时，优先按上述写法输出）：
                \(hotwordLines)
                """
            }
        } else {
            systemPrompt = PromptManager.systemPrompt(
                mode: mode,
                hotwords: config.customWords
            )
        }

        // 2. 前置上下文（如果有前台 app 信息）
        if let premise = PromptManager.contextPremise(targetApp: targetApp) {
            systemPrompt = "\(premise)\n\n\(systemPrompt)"
        }

        // 3. 如果有多轮历史，追加多轮上下文规则
        if !priorTurns.isEmpty {
            systemPrompt += "\n\n\(PromptManager.polishContextInstruction)"
        }

        print("[LLM] === System Prompt (first 200 chars) ===")
        print("[LLM] \(systemPrompt.prefix(200))...")
        print("[LLM] === End Prompt ===")

        // 4. 构建消息数组
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // 历史轮次（oldest first）
        for turn in priorTurns {
            messages.append(["role": "user", "content": PromptManager.userPrompt(rawTranscript: turn.raw)])
            messages.append(["role": "assistant", "content": turn.polished])
        }

        // 当前用户消息
        messages.append(["role": "user", "content": PromptManager.userPrompt(rawTranscript: text)])

        print("[LLM] Messages count: \(messages.count) (system + \(priorTurns.count) history turns + current)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(config.llmAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": config.llmModel,
            "messages": messages,
            "temperature": 0.3,
            "max_tokens": 4096,
            "reasoning_effort": config.llmReasoningEffort
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("[LLM] Sending request to: \(urlString)")
        print("[LLM] Model: \(config.llmModel)")
        print("[LLM] Input: \(text.prefix(100))...")

        let capturedPrompt = systemPrompt
        let startTime = CFAbsoluteTimeGetCurrent()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            if let error = error {
                print("[LLM] Request error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("[LLM] Response status: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                print("[LLM] No data received")
                completion(.failure(LLMError.noData))
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("[LLM] Raw response: \(responseString.prefix(500))")
            }

            do {
                let llmResponse = try JSONDecoder().decode(LLMResponse.self, from: data)
                if let rawContent = llmResponse.choices?.first?.message?.content, !rawContent.isEmpty {
                    // 6. 输出清理：去除 <think> 块、废话前缀、首尾空白
                    let cleanedContent = PromptManager.cleanOutput(rawContent)
                    print("[LLM] Raw output: \(rawContent.prefix(100))...")
                    if cleanedContent != rawContent {
                        print("[LLM] Cleaned output: \(cleanedContent.prefix(100))...")
                    }
                    AppLogger.shared.logLLM(systemPrompt: capturedPrompt, userText: text, output: cleanedContent, durationMs: elapsed)
                    completion(.success(cleanedContent))
                } else {
                    print("[LLM] Empty response")
                    completion(.failure(LLMError.emptyResponse))
                }
            } catch {
                print("[LLM] JSON decode error: \(error)")
                completion(.failure(error))
            }
        }
        task.resume()
    }
}

enum LLMError: LocalizedError {
    case invalidURL
    case noData
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .emptyResponse: return "Empty response from LLM"
        }
    }
}
