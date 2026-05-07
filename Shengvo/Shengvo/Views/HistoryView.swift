import SwiftUI

struct HistoryView: View {
    @State private var historyEntries: [HistoryEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("历史记录")
                    .font(.title3)
                    .fontWeight(.medium)

                Spacer()

                if !historyEntries.isEmpty {
                    Button("清空全部") {
                        HistoryManager.shared.clearAll()
                        historyEntries = []
                    }
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
            }

            if historyEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无历史记录")
                        .foregroundColor(.secondary)
                    Text("语音输入的文字会自动保存到这里")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("共 \(historyEntries.count) 条记录，双击可粘贴")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(historyEntries) { entry in
                            HistoryRow(entry: entry) {
                                historyEntries.removeAll { $0.id == entry.id }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 550, height: 500)
        .onAppear {
            historyEntries = HistoryManager.shared.getAllEntries()
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    @State private var showCopied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let app = entry.targetApp {
                    Text(app)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(4)
                }

                if entry.wasProcessedByLLM {
                    Text("LLM")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .frame(width: 80, alignment: .leading)

            Text(entry.text)
                .font(.subheadline)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Button(action: {
                    ClipboardManager.shared.copyToClipboard(text: entry.text)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                }) {
                    if showCopied {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("复制")

                Button(action: {
                    HistoryManager.shared.deleteEntry(id: entry.id)
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("删除")
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(8)
        .onTapGesture(count: 2) {
            ClipboardManager.shared.copyAndPaste(text: entry.text)
        }
    }
}
