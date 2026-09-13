import ActivityKit

/// 跑步 Live Activity 属性。ContentState 直接复用 App Group 共享的 LiveActivityState。
@available(iOS 16.1, *)
struct RunActivityAttributes: ActivityAttributes {
    public typealias ContentState = LiveActivityState
    public let appName: String = "TempoRun"
}
