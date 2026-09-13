import Foundation

/// Live Activity / 灵动岛 / 锁屏 Widget 的共享状态（App 与 Widget Extension 共用）
struct LiveActivityState: Codable, Hashable {
    enum Status: String, Codable {
        case idle, running, paused
        var title: String {
            switch self {
            case .running: return "跑步中"
            case .paused:  return "已暂停"
            case .idle:    return "准备"
            }
        }
    }

    var status: Status = .idle
    var elapsed: TimeInterval = 0
    var distanceMeters: Double = 0
    var cadence: Int = 0
    var targetCadence: Int = 170
    var stageName: String?
    var stageRemaining: TimeInterval?
    var deviation: Int { cadence - targetCadence }

    static let empty = LiveActivityState()
}
