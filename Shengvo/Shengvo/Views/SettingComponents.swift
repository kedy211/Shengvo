import SwiftUI

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(.secondary)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Toggle Row

struct SettingToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    @State private var isHovered = false

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: subtitle != nil ? 52 : 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Number Field Row

struct SettingNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var isHovered = false

    init(title: String, unit: String = "", value: Binding<Int>, range: ClosedRange<Int> = 0...Int.max) {
        self.title = title
        self.unit = unit
        self._value = value
        self.range = range
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 6) {
                Stepper("", value: $value, in: range)
                    .labelsHidden()
                    .scaleEffect(0.8)

                TextField("", value: $value, format: .number)
                    .font(.system(size: 13, weight: .regular))
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
                    .textFieldStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Double Number Field Row

struct SettingDoubleField: View {
    let title: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    @State private var isHovered = false

    init(title: String, unit: String = "", value: Binding<Double>, range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude, step: Double = 0.1, format: String = "%.1f") {
        self.title = title
        self.unit = unit
        self._value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 6) {
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .scaleEffect(0.8)

                TextField("", value: $value, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 13, weight: .regular))
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .textFieldStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Single-line Text Field Row

struct SettingTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    init(title: String, placeholder: String = "", text: Binding<String>, isSecure: Bool = false) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            Spacer()

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 13, weight: .regular))
                } else {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 13, weight: .regular))
                }
            }
            .textFieldStyle(.plain)
            .frame(width: 240, height: 24)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isFocused ? 1.5 : 0.5)
            )
            .focused($isFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Text Editor (Multi-line)

struct SettingTextEditor: View {
    let title: String
    let subtitle: String?
    let placeholder: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    init(title: String, subtitle: String? = nil, placeholder: String = "", text: Binding<String>) {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty && !isFocused {
                    Text(placeholder)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.primary.opacity(0.2))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.visible)
                    .frame(minHeight: 180)
                    .padding(4)
                    .focused($isFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isFocused ? 1.5 : 0.5)
                    )
            }

            HStack {
                Spacer()
                Text("\(text.count) 字")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
