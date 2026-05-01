import Foundation

class LLMService {
    // App-specific style hints
    private let appStyleMap: [String: String] = [
        // Code editors
        "Xcode": "输出简洁的技术内容，可以包含代码片段。使用技术术语。",
        "Code": "输出简洁的技术内容，可以包含代码片段。使用技术术语。",
        "Cursor": "输出简洁的技术内容，可以包含代码片段。使用技术术语。",
        "Sublime Text": "输出简洁的技术内容，可以包含代码片段。使用技术术语。",
        "Typora": "输出简洁的技术内容，可以包含代码片段。使用技术术语。",

        // Chat / IM
        "微信": "使用轻松友好的语气，适合即时消息沟通。简洁自然。",
        "WeChat": "使用轻松友好的语气，适合即时消息沟通。简洁自然。",
        "钉钉": "使用简洁专业的语气，适合工作沟通。",
        "DingTalk": "使用简洁专业的语气，适合工作沟通。",
        "飞书": "使用简洁专业的语气，适合工作沟通。",
        "Lark": "使用简洁专业的语气，适合工作沟通。",
        "Telegram": "使用轻松友好的语气，适合即时消息沟通。",
        "Slack": "使用轻松友好的语气，适合团队沟通。",
        "Discord": "使用轻松友好的语气，适合即时消息沟通。",
        "QQ": "使用轻松友好的语气，适合即时消息沟通。",
        "企业微信": "使用简洁专业的语气，适合工作沟通。",

        // Email
        "Mail": "使用正式专业的语气，适合商务邮件。注意礼貌用语。",
        "邮件": "使用正式专业的语气，适合商务邮件。注意礼貌用语。",
        "Outlook": "使用正式专业的语气，适合商务邮件。注意礼貌用语。",
        "Spark": "使用正式专业的语气，适合商务邮件。注意礼貌用语。",
        "Thunderbird": "使用正式专业的语气，适合商务邮件。注意礼貌用语。",

        // Notes
        "备忘录": "使用清晰有条理的格式，适合笔记记录。",
        "Notes": "使用清晰有条理的格式，适合笔记记录。",
        "Notion": "使用清晰有条理的格式，适合笔记记录。可以使用标题和列表。",
        "Obsidian": "使用清晰有条理的格式，适合笔记记录。可以使用 Markdown 语法。",
        "Bear": "使用清晰有条理的格式，适合笔记记录。",

        // Document editors
        "Pages": "使用正式的书面语气，适合文档编辑。",
        "Word": "使用正式的书面语气，适合文档编辑。",
        "Google Docs": "使用正式的书面语气，适合文档编辑。",
        "WPS": "使用正式的书面语气，适合文档编辑。",

        // Browser
        "Safari": "根据上下文判断用途，保持简洁。",
        "Chrome": "根据上下文判断用途，保持简洁。",
        "Firefox": "根据上下文判断用途，保持简洁。",

        // Terminal
        "终端": "输出命令或技术内容，保持简洁。",
        "Terminal": "输出命令或技术内容，保持简洁。",
        "iTerm2": "输出命令或技术内容，保持简洁。",

        // Design
        "Figma": "使用设计相关的术语，描述清晰。",
        "Sketch": "使用设计相关的术语，描述清晰。",
    ]

    func processText(_ text: String, targetApp: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
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

        // Build system prompt: base prompt + app-specific style
        var systemPrompt = config.llmSystemPrompt

        if let appName = targetApp {
            // Find matching app style
            var matchedStyle: String?
            for (key, style) in appStyleMap {
                if appName.localizedCaseInsensitiveContains(key) || key.localizedCaseInsensitiveContains(appName) {
                    matchedStyle = style
                    break
                }
            }

            if let style = matchedStyle {
                systemPrompt += "\n\n---\n当前输入目标应用: \(appName)\n针对此应用的风格要求: \(style)"
                print("[LLM] Matched app: \(appName) → style hint applied")
            } else {
                systemPrompt += "\n\n---\n当前输入目标应用: \(appName)\n请根据该应用的特点调整输出风格。"
                print("[LLM] Target app: \(appName) (no specific style, using generic hint)")
            }
        }

        print("[LLM] === System Prompt (first 200 chars) ===")
        print("[LLM] \(systemPrompt.prefix(200))...")
        print("[LLM] === End Prompt ===")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(config.llmAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": config.llmModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 4096,
            "reasoning_effort": config.llmReasoningEffort
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("[LLM] Sending request to: \(urlString)")
        print("[LLM] Model: \(config.llmModel)")
        print("[LLM] Input: \(text.prefix(100))...")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                if let content = llmResponse.choices?.first?.message?.content, !content.isEmpty {
                    print("[LLM] Processed: \(content.prefix(100))...")
                    completion(.success(content))
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
