# 提示词架构升级方案

基于 OpenLess (openless-beta) 项目的提示词架构对比分析，对晟语 (Shengvo) 的 LLM 提示词系统进行模块化升级。

## 目标

- 将单一整体的系统提示词拆分为可组合的模块化块
- 支持未来扩展多种处理模式（后处理、翻译、问答等）
- 增加多轮上下文支持，改善连续口述体验
- 增加输出清理逻辑，防止 LLM 废话前缀污染输出
- 精简 `appStyleMap`，降低维护成本

---

## 一、新建文件：`Shengvo/Shengvo/Core/PromptManager.swift`

将分散在 `AppConfig.swift`、`LLMService.swift` 中的所有提示词相关逻辑集中到一个新文件中。

### 1.1 文件结构

```swift
import Foundation

// MARK: - 处理模式枚举

enum ProcessMode: String, Codable, CaseIterable {
    case polish = "polish"          // 默认后处理
    // 未来扩展
    // case translate = "translate"
    // case qa = "qa"
}

// MARK: - Prompt 管理器

struct PromptManager {

    // ---- 共享块 ----

    /// 角色定义块
    static let roleBlock = """
    你是语音输入的文本后处理引擎。将用户口语化的语音识别文本，处理为可直接使用的最终输出。
    """

    /// 通用规则块（所有模式共用）
    static let commonRules = """
    ## 通用规则

    1. **风格保真**：100%保留用户的用词习惯、语气词、口头禅。禁止为追求书面化而改写原生表达。
    2. **最小改动**：仅执行——删除语音噪音、修正ASR错误、删除重复、补充标点。禁止重构语句。
    3. **用户指令优先**：当用户给出改写/翻译/格式指令时，按指令执行，覆盖上述规则。
    4. **中英混编/专有名词保持**：代码标识符、技术术语（useState, async/await）、品牌名、人名不翻译不改写。
    5. **不编造事实**：用户没说的不要替他说。不补充"背景知识"、不扩写、不解释。
    6. **不回答嵌入问题**：用户转写中可能包含自言自语或反问，不要尝试回答它们，照原意整理即可。
    7. **ASR 常见错误纠正**：
       - 同音错字（在/再、的/得/地、以/已等），根据上下文判断
       - ASR 错误拆分的术语（如 "Open code" → "OpenCode"、"跟目录" → "根目录"）
    """

    /// 输出约束块（所有模式共用）
    static let outputBlock = """
    ## 输出规则

    - 始终只输出处理后的纯文本
    - 禁止添加解释、说明、对话
    - 禁止包裹代码块、引号等格式符号
    - 禁止添加"根据您给的内容""整理如下""以下是整理后的内容"等前缀
    """

    // ---- 模式专用块 ----

    /// 默认后处理模式的任务描述
    static let polishTaskBlock = """
    ## 处理规则

    - **删除**：语气填充词（嗯、啊、呃、那个、um、uh、like 等无实际语义的部分）
    - **删除**：语音停顿导致的重复短语（如 "A的B的C的A的B的C" → "A的B的C"）
    - **修正**：同音错字，根据上下文判断正确写法
    - **补充**：句号、逗号、问号等基础标点
    - **不做**：不改口语表达、不调整语序、不补充省略内容、不改变人称、不重构句式

    ## 列表识别

    当用户使用"第一点……第二点……""步骤一……步骤二……"等结构时，自动转换为编号列表。
    使用双层格式：一级用 `1. `，二级用 `- `。
    """

    // ---- 系统提示词组装 ----

    /// 组装完整的系统提示词
    /// - Parameters:
    ///   - mode: 处理模式
    ///   - hotwords: 用户自定义词汇（热词）
    /// - Returns: 完整的系统提示词字符串
    static func systemPrompt(mode: ProcessMode, hotwords: [String] = []) -> String {
        let taskBlock: String
        switch mode {
        case .polish:
            taskBlock = polishTaskBlock
        }

        var prompt = """
        \(roleBlock)

        \(taskBlock)

        \(commonRules)

        \(outputBlock)
        """

        // 热词注入
        if !hotwords.isEmpty {
            let hotwordLines = hotwords.map { "- \($0)" }.joined(separator: "\n")
            prompt += """


            热词（用户希望以下写法在输出中保持准确；当转写中出现这些词的同音/近形误识别时，优先按上述写法输出）：
            \(hotwordLines)
            """
        }

        return prompt
    }

    // ---- 上下文前置 ----

    /// 上下文前置块（工作语言 / 前台应用）
    /// 在 system prompt 之前插入
    static func contextPremise(targetApp: String?) -> String? {
        var parts: [String] = []

        if let app = targetApp, !app.isEmpty {
            // 优先精确匹配，否则使用通用描述
            if let style = appStyleMap[app] {
                parts.append("当前正在向 [\(app)] 输入文字。\(style)")
            } else {
                parts.append("当前正在向 [\(app)] 输入文字。请根据该应用的类型和使用场景，自动调整语言风格、表达方式和格式，使其更贴合该应用的上下文。")
            }
        }

        guard !parts.isEmpty else { return nil }

        return """
        # 上下文
        \(parts.joined(separator: "\n"))
        """
    }

    // ---- 用户提示词模板 ----

    /// 包装原始 ASR 转写文本
    static func userPrompt(rawTranscript: String) -> String {
        """
        下面是本次语音输入的原始转写。请按 system prompt 中当前模式的任务描述进行整理后输出，整理结果会被原样插入到当前 app 的光标位置。

        <raw_transcript>
        \(rawTranscript)
        </raw_transcript>

        只输出整理后的文本正文。
        """
    }

    // ---- 多轮上下文指令 ----

    /// 多轮上下文使用规则（追加到 system prompt 末尾）
    static let polishContextInstruction = """
    # 多轮上下文使用规则

    上面的对话历史是给你提供前文语境（代词指代、未完整句子等），以正确理解最新一条用户消息要表达的意思。
    **不要复读、改写或合并历史中已经整理过的内容**——历史里的 assistant 输出已经被插入到用户的文档里了，再次出现就是重复。每次只输出**当前最新一条** user message 的整理结果，不要把上文带进来。
    """

    // ---- 输出清理 ----

    /// 需要从 LLM 输出开头剥离的废话前缀
    /// 参考 OpenLess 的 LEADING_BOILERPLATE_PREFIXES
    static let boilerplatePrefixes: [String] = [
        "根据您给的内容，整理如下：",
        "根据您给的内容，翻译如下：",
        "根据您提供的内容，",
        "以下是整理后的内容：",
        "以下是整理后的文本：",
        "整理后的内容如下：",
        "整理如下：",
        "我整理如下：",
        "处理后的文本如下：",
        "输出如下：",
        "整理结果：",
        "翻译结果：",
        "后处理结果：",
        "语音转文本结果：",
    ]

    /// 清理 LLM 输出：去除前言废话、思考块、首尾空白
    static func cleanOutput(_ raw: String) -> String {
        var text = raw

        // 1. 移除 <think>...</think> 块
        while let start = text.range(of: "<think>"),
              let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }

        // 2. 按行剥离已知废话前缀
        for prefix in boilerplatePrefixes {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }

        // 3. 去除首尾空白和空行
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    // ---- 应用风格映射 ----

    /// 精简后的应用 → 风格映射（从 35+ 条缩减到 10 条，其余走通用 fallback）
    private static let appStyleMap: [String: String] = [
        // 代码编辑器
        "Xcode": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",
        "Code": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",
        "Cursor": "输出简洁的技术内容，适合编程场景。可包含代码片段，使用准确的技术术语。",

        // 聊天
        "微信": "轻松友好的聊天语气。",
        "WeChat": "轻松友好的聊天语气。",
        "钉钉": "简洁专业的工作沟通语气。",
        "飞书": "简洁专业的工作沟通语气。",

        // 邮件
        "Mail": "正式专业的商务邮件语气。注意礼貌用语，结构完整的书信格式。",

        // 终端
        "终端": "适合命令行的输出格式。纯文本，直接输出命令或简洁的技术内容。",
        "Terminal": "适合命令行的输出格式。纯文本，直接输出命令或简洁的技术内容。",
        "iTerm2": "适合命令行的输出格式。纯文本，直接输出命令或简洁的技术内容。",

        // 备忘录/笔记：统一用简洁笔记格式
        "备忘录": "简洁有条理的笔记格式。",
        "Notes": "简洁有条理的笔记格式。",
    ]
}
```

---

## 二、修改 `LLMService.swift`

### 2.1 改造前的 `processText` 方法

当前逻辑（`LLMService.swift` 第 74-122 行）：

```swift
func processText(_ text: String, targetApp: String?, completion: @escaping (Result<String, Error>) -> Void) {
    var systemPrompt = AppConfig.shared.llmSystemPrompt

    // 手动拼接 app 风格
    if let app = targetApp {
        if let style = Self.appStyleMap[app] {
            systemPrompt += "\n\n---\n当前正在向 [\(app)] 输入文字。请针对此类应用场景调整输出：\(style)"
        } else {
            systemPrompt += "\n\n---\n当前正在向 [\(app)] 输入文字。请根据该应用的类型和使用场景..."
        }
    }

    // 手动拼接自定义词汇
    let words = AppConfig.shared.customWords.joined(separator: "、")
    if !words.isEmpty {
        systemPrompt += "\n\n---\n以下是本用户的专业术语/自定义词汇：\(words)..."
    }

    let messages: [[String: String]] = [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": text]
    ]
    // ...
}
```

### 2.2 改造后

```swift
func processText(
    _ text: String,
    targetApp: String?,
    mode: ProcessMode = .polish,
    priorTurns: [(raw: String, polished: String)] = [],  // 新增：多轮历史
    completion: @escaping (Result<String, Error>) -> Void
) {
    // 1. 组装系统提示词（基础块组合）
    var systemPrompt = PromptManager.systemPrompt(
        mode: mode,
        hotwords: AppConfig.shared.customWords
    )

    // 2. 前置上下文（如果有前台 app 信息）
    if let premise = PromptManager.contextPremise(targetApp: targetApp) {
        systemPrompt = "\(premise)\n\n\(systemPrompt)"
    }

    // 3. 如果有多轮历史，追加多轮上下文规则
    if !priorTurns.isEmpty {
        systemPrompt += "\n\n\(PromptManager.polishContextInstruction)"
    }

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

    // 5. 发送请求
    let body: [String: Any] = [
        "model": AppConfig.shared.llmModel,
        "messages": messages,
        "temperature": 0.3,
        "max_tokens": 4096,
        "reasoning_effort": AppConfig.shared.llmReasoningEffort
    ]

    // ... 发送 HTTP 请求（保持不变）

    // 6. 在 response handler 中对 output 做清理
    // let cleanedOutput = PromptManager.cleanOutput(rawOutput)
}
```

---

## 三、修改 `AppConfig.swift`

### 3.1 需要移除的内容

移除默认的 `llmSystemPrompt` 静态字面量（第 27-54 行）。改为从 PromptManager 获取默认值。

### 3.2 保留用户自定义功能

如果用户希望继续拥有"自定义系统提示词"的能力，新增一个字段：

```swift
struct AppConfig: Codable {
    // ... 现有字段 ...

    /// 用户自定义的系统提示词覆盖（nil 时使用 PromptManager 生成的默认提示词）
    var customSystemPromptOverride: String?

    // 移除 var llmSystemPrompt: String
    // 改为计算属性：
    var effectiveSystemPrompt: String {
        if let override = customSystemPromptOverride, !override.isEmpty {
            return override
        }
        return PromptManager.systemPrompt(mode: .polish, hotwords: customWords)
    }
}
```

---

## 四、多轮上下文存储器（新增）

### 4.1 新建文件：`Shengvo/Shengvo/Core/ConversationContext.swift`

```swift
import Foundation

/// 保存最近 N 轮口述上下文，用于多轮协处理
struct ConversationContext {
    /// 最大保留轮数
    static let maxTurns = 5

    /// 存储格式：(原始转写, 整理后输出)，newest first
    private var turns: [(raw: String, polished: String)] = []

    /// 当前轮数
    var count: Int { turns.count }

    /// 获取按时间顺序排列的历史轮次（oldest first，供 LLM 使用）
    var orderedTurns: [(raw: String, polished: String)] {
        Array(turns.reversed())
    }

    /// 添加一轮对话记录
    mutating func addTurn(raw: String, polished: String) {
        turns.append((raw, polished))
        if turns.count > Self.maxTurns {
            turns.removeFirst()
        }
    }

    /// 清空上下文（用户手动重置或切换场景时调用）
    mutating func reset() {
        turns.removeAll()
    }
}
```

### 4.2 在 `LLMService` 或调用方持有实例

```swift
class LLMService {
    // ... 现有代码 ...
    private var conversationContext = ConversationContext()
}
```

---

## 五、设置 UI 调整

### 5.1 修改 `SettingsView.swift`

将原来的"系统提示词"编辑区改为：

1. **新增开关**："使用自定义系统提示词"（切换 `customSystemPromptOverride` 是否生效）
2. **保留** TextEditor（仅在开关打开时显示）
3. **新增**："重置为默认提示词"按钮（清空 override，恢复 PromptManager 默认值）
4. **新增**："多轮上下文"开关 + 最大轮数滑块（默认 3，范围 1-5）

---

## 六、实施步骤（优先级排序）

### 第 1 步：提示词模块化（核心）

- [ ] 新建 `PromptManager.swift`
- [ ] 迁移 `AppConfig.swift` 中的默认 system prompt 到 `PromptManager`
- [ ] 迁移 `LLMService.swift` 中的 `appStyleMap` 到 `PromptManager`（精简至 10 条）
- [ ] 重构 `LLMService.processText()` 使用 `PromptManager` 组装提示词
- [ ] 测试：确保现有功能不受影响

### 第 2 步：输出清理

- [ ] 在 `LLMService` 的 response handler 中调用 `PromptManager.cleanOutput()`
- [ ] 测试：验证 `<think>` 块和废话前缀已被正确剥离

### 第 3 步：多轮上下文

- [ ] 新建 `ConversationContext.swift`
- [ ] 在 `LLMService.processText()` 中集成多轮历史
- [ ] 修改 `SettingsView.swift` 增加多轮开关和轮数控制
- [ ] 测试：连续口述体验

### 第 4 步：设置 UI 适配

- [ ] 将"系统提示词"编辑改为"自定义覆盖"模式（默认隐藏，高级用户可开启）
- [ ] 展示当前生效的默认提示词预览（只读）
- [ ] 测试：设置持久化与恢复

---

## 七、注意事项

1. **保持向后兼容**：升级过程中 `AppConfig` 的反序列化不能 break 现有用户数据。如果移除 `llmSystemPrompt` 字段，需要处理旧数据的迁移。
2. **ASR 层不受影响**：whisper.cpp 的 `initial_prompt` 和火山引擎的 `boostingtext` 不在此次升级范围内，它们走的是 ASR 上下文，与 LLM 提示词是不同的通道。
3. **日志记录保持不变**：`AppLogger.shared.logLLM()` 继续记录完整 system prompt + 输入 + 输出，方便调优。
4. **API 调用格式不变**：仍然是 OpenAI 兼容的 `chat/completions` 端点，只是 messages 数组从 2 条变为可能的 2+2N 条（多轮）。
