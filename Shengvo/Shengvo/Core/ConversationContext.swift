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
