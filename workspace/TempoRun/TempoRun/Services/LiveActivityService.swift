import ActivityKit

/// Live Activity 生命周期封装。
/// 注意：ActivityContent 的便捷初始化器为 iOS 16.2+，故本服务整体要求 16.2；
/// iOS 16.0–16.1 由锁屏 Widget + 深链兜底（见 RunCommands / Widgets）。
@available(iOS 16.2, *)
final class LiveActivityService {
    static let shared = LiveActivityService()
    private(set) var activity: Activity<RunActivityAttributes>?

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(targetCadence: Int, stageName: String?) {
        guard isAvailable, activity == nil else { return }
        let attributes = RunActivityAttributes()
        let state = LiveActivityState(status: .running,
                                     targetCadence: targetCadence,
                                     stageName: stageName)
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: state, staleDate: nil),
                                            pushType: nil)
        } catch {
            #if DEBUG
            print("[LiveActivity] start failed: \(error)")
            #endif
        }
    }

    func update(_ state: LiveActivityState) {
        RunCommands.publish(state: state) // 同步给锁屏 Timeline Provider（App 未更新时兜底）
        guard let activity else { return }
        Task {
            // 1Hz 更新（主循环驱动）；staleDate 留空，避免系统把活动标记为过期
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        Task {
            await activity.end(ActivityContent(state: .empty, staleDate: nil),
                               dismissalPolicy: .immediate)
            self.activity = nil
        }
    }
}
