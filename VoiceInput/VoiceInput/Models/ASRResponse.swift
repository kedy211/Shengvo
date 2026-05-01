import Foundation

struct ASRResponse: Codable {
    let code: Int?
    let message: String?
    let result: ASRResult?

    enum CodingKeys: String, CodingKey {
        case code, message, result
    }
}

struct ASRResult: Codable {
    let text: String?
    let utterances: [ASRUtterance]?
}

struct ASRUtterance: Codable {
    let text: String?
    let definite: Bool?
    let start_time: Int?
    let end_time: Int?
}

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
