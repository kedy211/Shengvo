import Foundation
import AppKit
import Carbon

struct AppConfig: Codable {
    // Hotkey
    var hotKeyKeyCode: UInt32 = UInt32(kVK_ANSI_V) // V key
    var hotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey) // Cmd+Shift
    var hotKeyUsesFn: Bool = false // Whether fn is part of the hotkey
    var hotKeyMode: String = "toggle" // "toggle" or "hold"
    var hotKeySingleKey: String? = nil // nil = 组合键模式; "fn"/"rightCmd"/"leftOption"/"rightOption"

    // ASR
    var asrMode: String = "local" // "local" = Whisper, "cloud" = Volcano Engine
    var asrAppID: String = ""
    var asrAccessToken: String = ""
    var asrSecretKey: String = ""
    var asrQwenAPIKey: String = "" // 阿里云百炼 Qwen-ASR API Key
    var asrStreamingEnabled: Bool = false // 是否启用 WebSocket 流式识别（仅 cloud 模式生效）
    var asrStreamingResourceID: String = "volc.bigasr.sauc.duration" // 流式识别 Resource ID
    var asrFallbackChain: [String] = ["apple"] // Fallback 引擎列表（不含 primary）
    var asrAllowAppleFallback: Bool = true // 是否允许 Apple Speech 作为最终兜底
    var customWords: [String] = []

    // LLM - Volcano Engine Ark
    var llmEnabled: Bool = true
    var llmBaseURL: String = "https://ark.cn-beijing.volces.com/api/v3"
    var llmAPIKey: String = ""
    var llmModel: String = "doubao-seed-2-0-lite-260215"
    var llmMinChars: Int = 10
    var llmReasoningEffort: String = "minimal"
    var minRecordingDuration: Double = 1.0 // seconds - recordings shorter than this are discarded

    /// 用户自定义的系统提示词覆盖（nil 时使用 PromptManager 生成的默认提示词）
    var customSystemPromptOverride: String?

    // 多轮上下文
    var conversationContextEnabled: Bool = false
    var conversationContextMaxTurns: Int = 3

    // General
    var launchAtLogin: Bool = true
    var showNotifications: Bool = true
    var logEnabled: Bool = false

    // MARK: - 计算属性

    /// 生效的系统提示词：用户覆盖优先，否则使用 PromptManager 默认值
    var effectiveSystemPrompt: String {
        if let override = customSystemPromptOverride, !override.isEmpty {
            return override
        }
        return PromptManager.systemPrompt(mode: .polish, hotwords: customWords)
    }

    // MARK: - Codable 迁移支持

    /// 旧版字段：llmSystemPrompt（已迁移至 customSystemPromptOverride）
    private static let oldDefaultSystemPrompt: String = {
        // 旧版默认提示词的前 150 字符作为匹配锚点（足够区分默认和自定义）
        "你是语音输入的文本后处理引擎。将用户口语化的语音识别文本，处理为可直接使用的最终输出。"
    }()

    enum CodingKeys: String, CodingKey {
        case hotKeyKeyCode, hotKeyModifiers, hotKeyUsesFn, hotKeyMode, hotKeySingleKey
        case asrMode, asrAppID, asrAccessToken, asrSecretKey, asrQwenAPIKey
        case asrStreamingEnabled, asrStreamingResourceID
        case asrFallbackChain, asrAllowAppleFallback
        case customWords
        case llmEnabled, llmBaseURL, llmAPIKey, llmModel
        case llmMinChars, llmReasoningEffort, minRecordingDuration
        case customSystemPromptOverride
        case conversationContextEnabled, conversationContextMaxTurns
        case launchAtLogin, showNotifications, logEnabled
        // 旧字段仅用于解码迁移，不编码
        case llmSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        hotKeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyKeyCode) ?? UInt32(kVK_ANSI_V)
        hotKeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers) ?? UInt32(cmdKey | shiftKey)
        hotKeyUsesFn = try container.decodeIfPresent(Bool.self, forKey: .hotKeyUsesFn) ?? false
        hotKeyMode = try container.decodeIfPresent(String.self, forKey: .hotKeyMode) ?? "toggle"
        hotKeySingleKey = try container.decodeIfPresent(String.self, forKey: .hotKeySingleKey)

        asrMode = try container.decodeIfPresent(String.self, forKey: .asrMode) ?? "local"
        asrAppID = try container.decodeIfPresent(String.self, forKey: .asrAppID) ?? ""
        asrAccessToken = try container.decodeIfPresent(String.self, forKey: .asrAccessToken) ?? ""
        asrSecretKey = try container.decodeIfPresent(String.self, forKey: .asrSecretKey) ?? ""
        asrQwenAPIKey = try container.decodeIfPresent(String.self, forKey: .asrQwenAPIKey) ?? ""
        asrStreamingEnabled = try container.decodeIfPresent(Bool.self, forKey: .asrStreamingEnabled) ?? false
        asrStreamingResourceID = try container.decodeIfPresent(String.self, forKey: .asrStreamingResourceID) ?? "volc.bigasr.sauc.duration"
        asrFallbackChain = try container.decodeIfPresent([String].self, forKey: .asrFallbackChain) ?? ["apple"]
        asrAllowAppleFallback = try container.decodeIfPresent(Bool.self, forKey: .asrAllowAppleFallback) ?? true
        customWords = try container.decodeIfPresent([String].self, forKey: .customWords) ?? []

        llmEnabled = try container.decodeIfPresent(Bool.self, forKey: .llmEnabled) ?? true
        llmBaseURL = try container.decodeIfPresent(String.self, forKey: .llmBaseURL) ?? "https://ark.cn-beijing.volces.com/api/v3"
        llmAPIKey = try container.decodeIfPresent(String.self, forKey: .llmAPIKey) ?? ""
        llmModel = try container.decodeIfPresent(String.self, forKey: .llmModel) ?? "doubao-seed-2-0-lite-260215"
        llmMinChars = try container.decodeIfPresent(Int.self, forKey: .llmMinChars) ?? 10
        llmReasoningEffort = try container.decodeIfPresent(String.self, forKey: .llmReasoningEffort) ?? "minimal"
        minRecordingDuration = try container.decodeIfPresent(Double.self, forKey: .minRecordingDuration) ?? 1.0

        customSystemPromptOverride = try container.decodeIfPresent(String.self, forKey: .customSystemPromptOverride)

        conversationContextEnabled = try container.decodeIfPresent(Bool.self, forKey: .conversationContextEnabled) ?? false
        conversationContextMaxTurns = try container.decodeIfPresent(Int.self, forKey: .conversationContextMaxTurns) ?? 3

        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        showNotifications = try container.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? true
        logEnabled = try container.decodeIfPresent(Bool.self, forKey: .logEnabled) ?? false

        // 迁移旧字段 llmSystemPrompt → customSystemPromptOverride
        if customSystemPromptOverride == nil,
           let oldPrompt = try container.decodeIfPresent(String.self, forKey: .llmSystemPrompt),
           !oldPrompt.isEmpty,
           !oldPrompt.hasPrefix(Self.oldDefaultSystemPrompt) {
            // 旧提示词与默认不同 → 视为用户自定义，迁移为覆盖
            customSystemPromptOverride = oldPrompt
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(hotKeyKeyCode, forKey: .hotKeyKeyCode)
        try container.encode(hotKeyModifiers, forKey: .hotKeyModifiers)
        try container.encode(hotKeyUsesFn, forKey: .hotKeyUsesFn)
        try container.encode(hotKeyMode, forKey: .hotKeyMode)
        try container.encode(hotKeySingleKey, forKey: .hotKeySingleKey)

        try container.encode(asrMode, forKey: .asrMode)
        try container.encode(asrAppID, forKey: .asrAppID)
        try container.encode(asrAccessToken, forKey: .asrAccessToken)
        try container.encode(asrSecretKey, forKey: .asrSecretKey)
        try container.encode(asrQwenAPIKey, forKey: .asrQwenAPIKey)
        try container.encode(asrStreamingEnabled, forKey: .asrStreamingEnabled)
        try container.encode(asrStreamingResourceID, forKey: .asrStreamingResourceID)
        try container.encode(asrFallbackChain, forKey: .asrFallbackChain)
        try container.encode(asrAllowAppleFallback, forKey: .asrAllowAppleFallback)
        try container.encode(customWords, forKey: .customWords)

        try container.encode(llmEnabled, forKey: .llmEnabled)
        try container.encode(llmBaseURL, forKey: .llmBaseURL)
        try container.encode(llmAPIKey, forKey: .llmAPIKey)
        try container.encode(llmModel, forKey: .llmModel)
        try container.encode(llmMinChars, forKey: .llmMinChars)
        try container.encode(llmReasoningEffort, forKey: .llmReasoningEffort)
        try container.encode(minRecordingDuration, forKey: .minRecordingDuration)

        try container.encode(customSystemPromptOverride, forKey: .customSystemPromptOverride)

        try container.encode(conversationContextEnabled, forKey: .conversationContextEnabled)
        try container.encode(conversationContextMaxTurns, forKey: .conversationContextMaxTurns)

        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showNotifications, forKey: .showNotifications)
        try container.encode(logEnabled, forKey: .logEnabled)

        // 不编码 llmSystemPrompt（旧字段，已迁移）
    }

    // MARK: - Init

    /// 使用所有属性的默认值构造（Codable 自定义 init(from:) 后需显式声明）
    init() {}

    // MARK: - Singleton & Persistence

    static var shared: AppConfig = {
        if let data = UserDefaults.standard.data(forKey: "appConfig"),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }
        return AppConfig()
    }()

    mutating func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "appConfig")
        }
        AppConfig.shared = self
    }

    // MARK: - Helpers

    var asrModeLabel: String {
        switch asrMode {
        case "local": return "Whisper 本地"
        case "cloud": return "火山引擎"
        case "qwen_cloud": return "阿里云 Qwen"
        case "apple": return "Apple Speech"
        default: return asrMode
        }
    }

    var hotKeyDescription: String {
        var desc = ""
        if hotKeyUsesFn { desc += "fn " }
        if hotKeyModifiers & UInt32(cmdKey) != 0 { desc += "⌘" }
        if hotKeyModifiers & UInt32(shiftKey) != 0 { desc += "⇧" }
        if hotKeyModifiers & UInt32(controlKey) != 0 { desc += "⌃" }
        if hotKeyModifiers & UInt32(optionKey) != 0 { desc += "⌥" }
        desc += keyCodeToString(hotKeyModifiers, hotKeyKeyCode)
        return desc
    }

    private func keyCodeToString(_ modifiers: UInt32, _ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return "Key(\(keyCode))"
        }
    }
}
