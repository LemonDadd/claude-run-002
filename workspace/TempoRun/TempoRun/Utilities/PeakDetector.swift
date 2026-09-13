import Foundation

/// 自适应阈值峰值检测：用于从滤波后加速度信号中检测每一次脚步冲击。
/// - 阈值随信号能量（EMA 均方根）自适应，走/跑通吃
/// - 最小峰间距 0.18s（支持最高 240+ SPM）
/// - 需要峰后回落验证，避免双峰误计
struct PeakDetector {
    private let minInterval: TimeInterval
    private let sensitivity: Double
    private var lastPeakTime: TimeInterval = -.infinity
    private var emaRMS = 0.0
    private var peakArmed = true
    private var candidateTime: TimeInterval = 0
    private var candidateValue: Double = 0

    init(minInterval: TimeInterval = AppConstants.minPeakInterval, sensitivity: Double = 1.35) {
        self.minInterval = minInterval
        self.sensitivity = sensitivity
    }

    mutating func reset() {
        lastPeakTime = -.infinity; emaRMS = 0; peakArmed = true
        candidateTime = 0; candidateValue = 0
    }

    /// - Parameters:
    ///   - value: 滤波后的加速度
    ///   - time: 采样时间（秒，单调递增）
    /// - Returns: 是否在该采样点确认一个脚步峰值
    @inline(__always)
    mutating func addSample(value: Double, time: TimeInterval) -> Bool {
        emaRMS = 0.95 * emaRMS + 0.05 * (value * value)
        let threshold = max(sensitivity * sqrt(emaRMS), 0.04) // g，静态底噪保护

        if peakArmed {
            if value > threshold, value > candidateValue,
               time - lastPeakTime >= minInterval {
                candidateValue = value
                candidateTime = time
            }
            // 峰值确认：信号从候选高点回落到阈值的 60%
            if candidateValue > 0 && value < candidateValue * 0.55 {
                peakArmed = false
            }
        } else if value < threshold * 0.4 {
            // 回落到谷底，重新武装；候选点计为一次脚步
            peakArmed = true
            if candidateValue > 0 {
                lastPeakTime = candidateTime
                candidateValue = 0
                return true
            }
        }
        return false
    }
}
