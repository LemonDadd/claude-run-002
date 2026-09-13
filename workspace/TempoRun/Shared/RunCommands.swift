import Foundation

/// 主 App 与 Widget / AppIntent 之间的跨进程命令通道
/// （App Group UserDefaults 存命令 + Darwin Notification 通知主进程）
enum RunCommands {
    static let appGroupID = "group.com.temporun.shared"
    static let notificationName = "com.temporun.RunCommand"

    enum Command: String, Codable {
        case pause, resume, stop, bumpUp, bumpDown
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// 由 Widget Extension（后台 AppIntent）调用
    static func send(_ command: Command) {
        defaults?.set(command.rawValue, forKey: "pendingCommand")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil, nil, true
        )
    }

    /// 主 App 取出并清除挂起命令
    static func consume() -> Command? {
        guard let raw = defaults?.string(forKey: "pendingCommand") else { return nil }
        defaults?.removeObject(forKey: "pendingCommand")
        return Command(rawValue: raw)
    }

    static func publish(state: LiveActivityState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: "liveActivityState")
    }

    static func currentState() -> LiveActivityState {
        guard let data = defaults?.data(forKey: "liveActivityState"),
              let state = try? JSONDecoder().decode(LiveActivityState.self, from: data) else {
            return .empty
        }
        return state
    }
}
