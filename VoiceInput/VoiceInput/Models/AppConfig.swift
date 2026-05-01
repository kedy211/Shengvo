import Foundation
import AppKit
import Carbon

struct AppConfig: Codable {
    // Hotkey
    var hotKeyKeyCode: UInt32 = UInt32(kVK_ANSI_V) // V key
    var hotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey) // Cmd+Shift

    // ASR - Volcano Engine
    var asrAppID: String = "9958934610"
    var asrAccessToken: String = "M5BfDAUJ4JrzIhbhMqaJct8s39H3MNDL"
    var asrSecretKey: String = "GBkiU3TeyedJj1cGV66gxpD9pFbZ6VR6"
    var customWords: [String] = []

    // LLM - Volcano Engine Ark
    var llmEnabled: Bool = true
    var llmBaseURL: String = "https://ark.cn-beijing.volces.com/api/v3"
    var llmAPIKey: String = "9ac3483f-0d94-4f5e-8455-99eda5c94ae3"
    var llmModel: String = "doubao-pro-32k"
    var llmMinChars: Int = 10
    var minRecordingDuration: Double = 1.0 // seconds - recordings shorter than this are discarded
    var llmSystemPrompt: String = """
    你是一个语音文字后处理助手。你的任务是将用户口语化的语音识别文本，转换为结构清晰、语法正确、符合书面习惯的最终输出。请严格按照以下步骤处理：

    语言净化：删除所有填充词（如"嗯、啊、呃、那个、就是、um、uh、like"等）。删除重复表达和自我修正，只保留用户最终想说的内容。例如，"我们明天，呃，不对，后天下午开会" → "我们后天下午开会"。

    意图理解与重构：自动修正语法错误，添加正确的标点符号（句号、逗号、问号等）。将口语化的松散表达提炼为核心意图，用简洁、逻辑通顺的书面语句重新组织。如果用户使用了"第一点……第二点……"或"步骤一……步骤二……"等结构，自动转换为项目符号列表（- ）或编号列表（1. ）。

    风格适配：根据对话上下文或用户使用的应用场景（如邮件、即时消息、笔记）调整语气。如果用户曾给出风格偏好（如更正式、更轻松、更友好），请模仿该风格。当用户选中已有文本并发出指令（如"make this sound more professional"或"translate this to Japanese"）时，按指令执行改写或翻译。

    始终输出纯文本结果，不要添加额外解释或对话。只输出处理后的最终文本。
    现在，开始帮我处理下面的文字：
    """

    // General
    var launchAtLogin: Bool = true
    var showNotifications: Bool = true

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

    var hotKeyDescription: String {
        var desc = ""
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
        default: return "Key(\(keyCode))"
        }
    }
}
