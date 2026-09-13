import CoreHaptics

/// 节拍触觉：左脚弱振 / 右脚强振，与音频节拍在同一调度时刻触发
final class HapticEngine {
    private var engine: CHHapticEngine?
    private var leftPattern: CHHapticPattern?
    private var rightPattern: CHHapticPattern?
    private(set) var isAvailable = false

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        isAvailable = engine != nil
        makePatterns()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        engine?.stoppedHandler = { _ in }
    }

    func start() {
        guard isAvailable else { return }
        try? engine?.start()
    }

    func stop() {
        engine?.stop()
    }

    private func makePatterns() {
        // 右脚：强 + 锐；左脚：弱而短 —— 不看屏幕也能分辨左右脚
        leftPattern = try? CHHapticPattern(events: [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.45),
                .init(parameterID: .hapticSharpness, value: 0.4)
            ], relativeTime: 0)
        ], parameters: [])

        rightPattern = try? CHHapticPattern(events: [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                .init(parameterID: .hapticIntensity, value: 1.0),
                .init(parameterID: .hapticSharpness, value: 0.85)
            ], relativeTime: 0)
        ], parameters: [])
    }

    /// - Parameter relativeTime: 相对“现在”的偏移（秒），由音频调度器提前量换算
    func playFoot(isRight: Bool, relativeTime: TimeInterval = 0) {
        guard isAvailable, let engine else { return }
        let pattern = isRight ? rightPattern : leftPattern
        guard let pattern else { return }
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate + relativeTime)
        } catch {
            // 触觉失败不影响音频
        }
    }

    /// 阶段切换 / 暂停等长反馈
    func notify() {
        guard isAvailable, let engine else { return }
        let pattern = try? CHHapticPattern(events: [
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: 0.9),
                .init(parameterID: .hapticSharpness, value: 0.5)
            ], relativeTime: 0, duration: 0.5)
        ], parameters: [])
        if let pattern, let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }
}
