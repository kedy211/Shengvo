import Foundation
import AppKit
import Carbon

struct AppConfig: Codable {
    // Hotkey
    var hotKeyKeyCode: UInt32 = UInt32(kVK_ANSI_V) // V key
    var hotKeyModifiers: UInt32 = UInt32(cmdKey | shiftKey) // Cmd+Shift
    var hotKeyUsesFn: Bool = false // Whether fn is part of the hotkey

    // ASR
    var asrMode: String = "local" // "local" = Whisper, "cloud" = Volcano Engine
    var asrAppID: String = ""
    var asrAccessToken: String = ""
    var asrSecretKey: String = ""
    var asrQwenAPIKey: String = "" // 阿里云百炼 Qwen-ASR API Key
    var customWords: [String] = []

    // LLM - Volcano Engine Ark
    var llmEnabled: Bool = true
    var llmBaseURL: String = "https://ark.cn-beijing.volces.com/api/v3"
    var llmAPIKey: String = ""
    var llmModel: String = "doubao-seed-2-0-lite-260215"
    var llmMinChars: Int = 10
    var llmReasoningEffort: String = "minimal"
    var minRecordingDuration: Double = 1.0 // seconds - recordings shorter than this are discarded
    var llmSystemPrompt: String = """
    你是语音输入的文本后处理引擎。将用户口语化的语音识别文本，处理为可直接使用的最终输出。

    ## 处理原则

    1. **风格保真**：100%保留用户的用词习惯、语气词、口头禅。禁止为追求书面化而改写原生表达。
    2. **最小改动**：仅执行——删除语音噪音、修正ASR错误、删除重复、补充标点。禁止重构语句。
    3. **用户指令优先**：当用户给出改写/翻译/格式指令时，按指令执行，覆盖上述规则。

    ## 处理规则

    - **删除**：语气填充词（嗯、啊、呃、那个、um、uh、like等无实际语义的部分）
    - **删除**：语音停顿导致的重复短语（如"A的B的C的A的B的C"→"A的B的C"）
    - **修正**：同音错字（在/再、的/得/地、以/已等），根据上下文判断
    - **修正**：ASR错误拆分的术语（如"Open code"→"opencode"）
    - **补充**：句号、逗号、问号等基础标点
    - **不做**：不改口语表达、不调整语序、不补充省略内容、不改变人称、不重构句式

    ## 列表识别

    当用户使用"第一点……第二点……""步骤一……步骤二……"等结构时，自动转换为编号列表（1. 2. 3.）。

    ## 输出规则

    - 始终只输出处理后的纯文本
    - 禁止添加解释、说明、对话
    - 禁止包裹代码块、引号等格式符号
    """

    // General
    var launchAtLogin: Bool = true
    var showNotifications: Bool = true
    var logEnabled: Bool = false

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
