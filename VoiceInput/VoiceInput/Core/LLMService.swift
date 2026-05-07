import Foundation

class LLMService {
    // App-specific style hints
    private let appStyleMap: [String: String] = [
        // Code editors
        "Xcode": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",
        "Code": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",
        "Cursor": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",
        "Sublime Text": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",
        "Typora": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",

        // Chat / IM
        "微信": "轻松友好的聊天语气，适合即时消息。简短自然，可适当使用口语化表达。",
        "WeChat": "轻松友好的聊天语气，适合即时消息。简短自然，可适当使用口语化表达。",
        "钉钉": "简洁专业的工作沟通语气，适合企业协作。直接明了，避免冗余。",
        "DingTalk": "简洁专业的工作沟通语气，适合企业协作。直接明了，避免冗余。",
        "飞书": "简洁专业的工作沟通语气，适合团队协作。条理清晰，重点突出。",
        "Lark": "简洁专业的工作沟通语气，适合团队协作。条理清晰，重点突出。",
        "Telegram": "轻松自然的聊天语气，适合即时消息。",
        "Slack": "简洁友好的团队沟通语气，适合工作讨论。",
        "Discord": "轻松自然的聊天语气，适合社区交流。",
        "QQ": "轻松自然的聊天语气，适合即时消息。",
        "企业微信": "简洁专业的工作沟通语气，适合企业协作。直接明了，避免冗余。",

        // Email
        "Mail": "正式专业的商务邮件语气。注意礼貌用语，结构完整的书信格式。",
        "邮件": "正式专业的商务邮件语气。注意礼貌用语，结构完整的书信格式。",
        "Outlook": "正式专业的商务邮件语气。注意礼貌用语，结构完整的书信格式。",
        "Spark": "正式专业的商务邮件语气。注意礼貌用语，结构完整的书信格式。",
        "Thunderbird": "正式专业的商务邮件语气。注意礼貌用语，结构完整的书信格式。",

        // Notes
        "备忘录": "简洁有条理的笔记格式，便于快速记录和回顾。",
        "Notes": "简洁有条理的笔记格式，便于快速记录和回顾。",
        "Notion": "结构清晰的笔记格式。善用标题、列表和段落组织内容。",
        "Obsidian": "适合 Markdown 笔记的格式。善用标题、列表和链接组织内容。",
        "Bear": "简洁有条理的笔记格式，适合快速记录想法。",

        // Document editors
        "Pages": "正式规范的书面表达，段落分明，适合文档撰写。",
        "Word": "正式规范的书面表达，段落分明，适合文档撰写。",
        "Google Docs": "正式规范的书面表达，段落分明，适合文档撰写。",
        "WPS": "正式规范的书面表达，段落分明，适合文档撰写。",

        // Browser
        "Safari": "根据输入内容的场景自行判断，保持自然流畅。",
        "Chrome": "根据输入内容的场景自行判断，保持自然流畅。",
        "Firefox": "根据输入内容的场景自行判断，保持自然流畅。",

        // Terminal
        "终端": "适合命令行的输出格式。纯文本，直接输出命令或简洁的技术内容。",
        "Terminal": "适合命令行的输出格式。纯文本，直接输出命令或简洁的技术内容。",
        "iTerm2": "适合命令行的输出格式。纯文本，直接输出命令或简洁的技术内容。",

        // Design
        "Figma": "使用设计领域术语，描述准确清晰，适合设计协作场景。",
        "Sketch": "使用设计领域术语，描述准确清晰，适合设计协作场景。",
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
                systemPrompt += "\n\n---\n当前正在向 [\(appName)] 输入文字。请针对此类应用场景调整输出：\(style)"
                print("[LLM] Matched app: \(appName) → style hint applied")
            } else {
                systemPrompt += "\n\n---\n当前正在向 [\(appName)] 输入文字。请根据该应用的类型和使用场景，自动调整语言风格、表达方式和格式，使其更贴合该应用的上下文。"
                print("[LLM] Target app: \(appName) (no specific style, using generic hint)")
            }
        }

        // Inject custom words as hot word correction hint
        if !config.customWords.isEmpty {
            let words = config.customWords.joined(separator: "、")
            systemPrompt += "\n\n---\n以下是本用户的专业术语/自定义词汇：\(words)\n如果语音识别结果中存在与以上词汇发音近似但写法错误的内容，请纠正为对应词汇的正确写法。仅纠正明显发音错误，不要随意改写正确内容。"
            print("[LLM] Custom words injected for correction: \(words)")
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
                if let content = llmResponse.choices?.first?.message?.content, !content.isEmpty {
                    print("[LLM] Processed: \(content.prefix(100))...")
                    AppLogger.shared.logLLM(systemPrompt: capturedPrompt, userText: text, output: content, durationMs: elapsed)
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
