import SwiftUI

/// 极简高对比设计系统（户外强光可读：主文字对比 ≥4.5:1；动态字体）
enum DesignSystem {
    static let radius: CGFloat = 20
    static let cardRadius: CGFloat = 16

    static let stageWarmup = Color(red: 0.98, green: 0.74, blue: 0.18)   // 琥珀
    static let stageFast = Color(red: 0.95, green: 0.30, blue: 0.24)     // 红
    static let stageSlow = Color(red: 0.20, green: 0.66, blue: 0.96)     // 蓝
    static let stageCooldown = Color(red: 0.20, green: 0.78, blue: 0.55) // 绿
    static let stageSteady = Color.accentColor

    static func stage(_ type: StageType) -> Color {
        switch type {
        case .warmup: return stageWarmup
        case .fast: return stageFast
        case .slow: return stageSlow
        case .cooldown: return stageCooldown
        case .steady: return stageSteady
        }
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.cardRadius))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
