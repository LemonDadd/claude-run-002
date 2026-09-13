import Foundation

/// 与 App 模型解耦的共享格式化（Widget Extension 与 App 都可编译）
enum Formatters {
    static func duration(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// 配速 mm'ss"/km
    static func pace(secondsPerKm: TimeInterval) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "--'--\"" }
        let t = Int(secondsPerKm)
        return String(format: "%d'%02d\"", t / 60, t % 60)
    }

    /// 距离；imperial 供英制单位用户使用
    static func distance(meters: Double, imperial: Bool = false) -> String {
        if imperial {
            return String(format: "%.2f mi", meters / 1609.344)
        }
        return meters >= 1000
            ? String(format: "%.2f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }

    static func cadence(_ spm: Int) -> String { "\(max(0, spm)) SPM" }
    static func calories(_ kcal: Double) -> String { String(format: "%.0f 千卡", kcal) }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM月dd日 EEEE"; f.locale = Locale(identifier: "zh_CN")
        return f
    }()
}
