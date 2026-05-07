import Foundation

struct LLMResponse: Codable {
    let id: String?
    let choices: [LLMChoice]?
}

struct LLMChoice: Codable {
    let index: Int?
    let message: LLMMessage?
    let finish_reason: String?
}

struct LLMMessage: Codable {
    let role: String?
    let content: String?
}
