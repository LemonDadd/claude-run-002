import SwiftUI

/// 大号实时数据块（支持 Dynamic Type、VoiceOver）
struct MetricTile: View {
    let title: String
    let value: String
    let unit: String?
    var emphasis: Bool = false

    init(title: String, value: String, unit: String? = nil, emphasis: Bool = false) {
        self.title = title; self.value = value; self.unit = unit; self.emphasis = emphasis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(emphasis ? .system(size: 44, weight: .heavy, design: .rounded) : .title2.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)\(unit ?? "")")
    }
}

/// 圆形大按钮（跑步中防误触：≥74pt 热区、二次确认停止）
struct BigActionButton: View {
    enum Style { case primary, danger, secondary }
    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                .background(color, in: RoundedRectangle(cornerRadius: DesignSystem.radius))
                .foregroundColor(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(style == .danger ? "需要再次点击确认" : "")
    }

    private var color: Color {
        switch style {
        case .primary: return .accentColor
        case .danger: return .red
        case .secondary: return .gray
        }
    }
}

/// 步频调节器：滑块 + 加减按钮（步进 1SPM）
struct CadenceStepperControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var onChange: ((Int) -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 28) {
                Button { set(value - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(value <= range.lowerBound)

                VStack {
                    Text("\(value)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("SPM").font(.headline).foregroundColor(.secondary)
                }
                .frame(minWidth: 140)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("目标步频 \(value)")

                Button { set(value + 1) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                }
                .disabled(value >= range.upperBound)
            }

            Slider(value: Binding(get: { Double(value) },
                                  set: { set(Int($0.rounded())) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .tint(.accentColor)
            .accessibilityLabel("目标步频滑块")

            HStack {
                Text("\(range.lowerBound)").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(range.upperBound)").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func set(_ v: Int) {
        let clamped = min(range.upperBound, max(range.lowerBound, v))
        value = clamped
        onChange?(clamped)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 14))
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
