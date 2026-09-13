import Foundation
import CoreMotion

/// CoreMotion 封装：加速度计（≥50Hz）+ CMPedometer 系统步频
final class SensorService {
    static let shared = SensorService()

    let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private(set) var pedometerCadence: Double?   // SPM
    private(set) var pedometerSteps: Int = 0

    /// 60Hz 加速度回调（合加速度模长 + 时间戳）
    private let accelerometerQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.temporun.accelerometer"
        q.qualityOfService = .userInteractive
        q.maxConcurrentOperationCount = 1
        return q
    }()

    func startAccelerometer(_ handler: @escaping (Double, TimeInterval) -> Void) {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / AppConstants.accelerometerHz
        motion.startAccelerometerUpdates(to: accelerometerQueue) { data, _ in
            guard let a = data?.acceleration, let timestamp = data?.timestamp else { return }
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            handler(magnitude, timestamp)
        }
    }

    func stopAccelerometer() { motion.stopAccelerometerUpdates() }

    /// 系统计步器：steps + currentCadence（设备支持时作为融合参考）
    func startPedometer(from date: Date = Date()) {
        guard CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            guard let self, let data else { return }
            self.pedometerSteps = data.numberOfSteps.intValue
            if let cadence = data.currentCadence?.doubleValue {
                self.pedometerCadence = cadence * 60.0 // steps/s -> SPM
            }
        }
    }

    func stopPedometer() {
        pedometer.stopUpdates()
        pedometerCadence = nil
    }

    func reset() {
        pedometerSteps = 0
        pedometerCadence = nil
    }

    static var permissionDescription: String { "需要运动与健身权限来检测步频" }
}
