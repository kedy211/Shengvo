import SwiftUI

struct CustomWordsView: View {
    @Binding var customWords: [String]
    @State private var newWord: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自定义识别词")
                .font(.headline)

            Text("添加专有名词、术语等，提升识别准确率")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                TextField("输入词汇，按回车添加", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addWord()
                    }

                Button("添加") {
                    addWord()
                }
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if customWords.isEmpty {
                Text("暂无自定义词汇")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(customWords.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text(word)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)

                                Spacer()

                                Button(action: {
                                    customWords.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                HStack {
                    Spacer()
                    Button("清空全部") {
                        customWords.removeAll()
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !customWords.contains(word) else { return }
        customWords.append(word)
        newWord = ""
    }
}
