import Foundation
import HealthKit

/// HealthKit 跑步数据写入（距离/步数/卡路里/训练）
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(result: ((Bool) -> Void)? = nil) {
        guard isAvailable else { result?(false); return }
        let write: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
        ]
        store.requestAuthorization(toShare: write, read: read) { ok, _ in result?(ok) }
    }

    func writeRun(_ run: RunSummary) {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        builder.beginCollection(withStart: run.startDate) { [weak self] success, _ in
            guard success, let self else { return }
            var samples: [HKQuantitySample] = []
            if run.distanceMeters > 0 {
                samples.append(self.quantitySample(.distanceWalkingRunning,
                    quantity: HKQuantity(unit: .meter(), doubleValue: run.distanceMeters),
                    start: run.startDate, end: run.endDate))
            }
            if run.steps > 0 {
                samples.append(self.quantitySample(.stepCount,
                    quantity: HKQuantity(unit: .count(), doubleValue: Double(run.steps)),
                    start: run.startDate, end: run.endDate))
            }
            if run.calories > 0 {
                samples.append(self.quantitySample(.activeEnergyBurned,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: run.calories),
                    start: run.startDate, end: run.endDate))
            }
            builder.add(samples) { ok, _ in
                guard ok else { return }
                builder.endCollection(withEnd: run.endDate) { finished, _ in
                    guard finished else { return }
                    builder.finishWorkout { _, _ in }
                }
            }
        }
    }

    private func quantitySample(_ id: HKQuantityTypeIdentifier, quantity: HKQuantity,
                                start: Date, end: Date) -> HKQuantitySample {
        HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: id)!,
                         quantity: quantity, start: start, end: end)
    }
}
