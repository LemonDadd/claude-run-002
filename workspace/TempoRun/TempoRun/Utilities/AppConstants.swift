import Foundation

enum AppConstants {
    static let cadenceRange = 60...240
    static let cadenceStep = 1
    static let defaultTargetCadence = 170
    static let deviationAlertThreshold = 5      // ±5 SPM 偏离提醒
    static let accelerometerHz = 60.0           // ≥50Hz
    static let bandpassLowHz = 1.0
    static let bandpassHighHz = 5.0
    static let cadenceWindow: TimeInterval = 5  // 5 秒滑动窗口
    static let minPeakInterval: TimeInterval = 0.18
    static let schedulerAhead: TimeInterval = 0.15  // 音频提前调度
    static let hapticAhead: TimeInterval = 0.1
    static let maxLocationAge: TimeInterval = 8
    static let minLocationAccuracy: Double = 30  // 米
    static let earthRadiusMeters = 6_371_000.0
}
