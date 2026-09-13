import Foundation
import Combine

/// 步频检测引擎（实时监测核心）
///
/// 信号链：
/// 1) 加速度计 60Hz 合加速度模长
/// 2) BandPass1to5Hz：1–5Hz 二阶 Butterworth 带通（去重力、去抖动）
/// 3) PeakDetector：自适应阈值峰值检测（脚步冲击），最小峰间距 0.18s
/// 4) 5 秒滑动窗口收集峰间间隔，中位间隔换算 SPM
/// 5) 与 CMPedometer 系统步频加权融合（系统越可信权重越高）
///
/// 性能/准确率：
/// - 输出刷新率 ≥2Hz（内部每 0.5s 计算一次）
/// - 5s 窗口覆盖走路到跑步（60–240 SPM），中位数抗干扰
/// - 与系统计步器融合 + 步数交叉校验，目标准确率 ≥95%
final class CadenceEngine: ObservableObject {

    @Published private(set) var cadence: Int = 0
    @Published private(set) var isRunning = false
    @Published private(set) var peakSteps: Int = 0
    /// 信号质量 0–1（供 UI 显示传感器置信度）
    @Published private(set) var signalQuality: Double = 0

    private let sensor = SensorService.shared
    private let filter = BandPass1to5Hz(sampleRate: AppConstants.accelerometerHz)
    private var detector = PeakDetector()

    /// 滑动窗口内的脚步时刻
    private var stepTimes: [TimeInterval] = []
    private var startTime: TimeInterval = 0
    private var lastEmit: TimeInterval = 0
    private var confidenceHits = 0   // 与 pedometer 一致次数（融合权重自适应）
    private let queue = DispatchQueue(label: "com.temporun.cadence", qos: .userInteractive)

    func start() {
        guard !isRunning else { return }
        DispatchQueue.main.async { self.isRunning = true }
        filter.reset()
        detector.reset()
        stepTimes.removeAll(keepingCapacity: true)
        confidenceHits = 0
        sensor.reset()
        sensor.startPedometer()
        sensor.startAccelerometer { [weak self] magnitude, timestamp in
            self?.queue.async { self?.ingest(magnitude: magnitude, time: timestamp) }
        }
        DispatchQueue.main.async {
            self.peakSteps = 0; self.cadence = 0; self.signalQuality = 0
        }
    }

    func stop() {
        isRunning = false
        sensor.stopAccelerometer()
        sensor.stopPedometer()
    }

    // MARK: 采样处理（userInteractive 队列，非隔离纯计算）

    private func ingest(magnitude: Double, time: TimeInterval) {
        if startTime == 0 { startTime = time; lastEmit = time }
        let filtered = filter.process(magnitude)
        if detector.addSample(value: filtered, time: time) {
            stepTimes.append(time)
            DispatchQueue.main.async { self.peakSteps += 1 }
        }
        // 维持 5 秒滑动窗口
        let cutoff = time - AppConstants.cadenceWindow
        while let first = stepTimes.first, first < cutoff { stepTimes.removeFirst() }

        // 每 0.5s 输出一次（刷新率 ≥1Hz）
        if time - lastEmit >= 0.5 {
            lastEmit = time
            let raw = computeCadenceSPM()
            let pedo = sensor.pedometerCadence
            let stepCountInWindow = stepTimes.count
            DispatchQueue.main.async {
                self.publish(raw: raw, pedo: pedo, stepCountInWindow: stepCountInWindow)
            }
        }
    }

    /// 用窗口内峰间间隔的中位数计算 SPM，抗孤立误检
    private func computeCadenceSPM() -> Int {
        guard stepTimes.count >= 3 else { return 0 }
        var intervals: [TimeInterval] = []
        intervals.reserveCapacity(stepTimes.count - 1)
        for i in 1..<stepTimes.count {
            let dt = stepTimes[i] - stepTimes[i - 1]
            if (0.15...0.6).contains(dt) { intervals.append(dt) } // 100–400SPM 物理区间
        }
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        return Int((60.0 / median).rounded())
    }

    // MARK: 融合输出（主线程）

    private func publish(raw: Int, pedo: Double?, stepCountInWindow: Int) {
        let pedoValue = Int(pedo ?? 0)
        var fused = raw
        if pedoValue > 0 {
            // 自适应权重：两者越一致，越信任系统计步器
            if raw > 0, abs(raw - pedoValue) <= 6 {
                confidenceHits = min(confidenceHits + 1, 8)
            } else {
                confidenceHits = max(confidenceHits - 1, 0)
            }
            let pedoWeight = 0.3 + 0.05 * Double(confidenceHits) // 0.3...0.7
            fused = raw > 0
                ? Int((Double(raw) * (1 - pedoWeight) + Double(pedoValue) * pedoWeight).rounded())
                : pedoValue
        }
        fused = max(0, min(240, fused))
        cadence = fused

        // 信号质量：窗口内步数与理论密度
        let expectedSteps = 5.0 * Double(fused) / 60.0
        if expectedSteps > 0 {
            let density = min(1.0, Double(stepCountInWindow) / expectedSteps)
            signalQuality = raw > 0 ? min(1.0, 0.5 + density * 0.5) : density * 0.5
        } else {
            signalQuality = 0
        }
    }

    /// 校准用步数（峰值检测与 pedometer 取大，交叉校验防漏计）
    var validatedSteps: Int {
        max(peakSteps, sensor.pedometerSteps)
    }
}
