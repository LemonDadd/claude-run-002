import SwiftData
import Foundation

// SwiftData 需要 iOS 17+；工程最低支持 iOS 16，
// 因此所有 @Model 实体标注可用性，iOS 16 由 JSONHistoryStore 兜底（见 Services/Persistence）。

@available(iOS 17.0, *)
@Model
final class UserEntity {
    @Attribute(.unique) var id: UUID
    var nickname: String
    @Attribute(.externalStorage) var avatar: Data?
    var genderRaw: String
    var age: Int?
    var weightKg: Double
    var heightCm: Double
    var unitRaw: String
    var language: String
    var subscriptionStatusRaw: String
    var subscriptionExpiryDate: Date?

    init(id: UUID = UUID(), nickname: String, avatar: Data? = nil, genderRaw: String = "其他",
         age: Int? = nil, weightKg: Double = 65, heightCm: Double = 170,
         unitRaw: String = "公制", language: String = "zh-Hans",
         subscriptionStatusRaw: String = "free", subscriptionExpiryDate: Date? = nil) {
        self.id = id; self.nickname = nickname; self.avatar = avatar
        self.genderRaw = genderRaw; self.age = age
        self.weightKg = weightKg; self.heightCm = heightCm
        self.unitRaw = unitRaw; self.language = language
        self.subscriptionStatusRaw = subscriptionStatusRaw
        self.subscriptionExpiryDate = subscriptionExpiryDate
    }
}

@available(iOS 17.0, *)
@Model
final class RunRecordEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID?
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var distanceMeters: Double
    var avgCadence: Int
    var maxCadence: Int
    var calories: Double
    var steps: Int
    var trainingTypeRaw: String
    var planId: UUID?
    var note: String
    /// JSON: [TrackPoint]
    var trackData: Data?
    /// JSON: [CadenceSample]
    var cadenceSeriesData: Data?
    /// JSON: [Split]
    var splitsData: Data?

    init(id: UUID = UUID(), userId: UUID?, startDate: Date, endDate: Date,
         duration: TimeInterval, distanceMeters: Double, avgCadence: Int, maxCadence: Int,
         calories: Double, steps: Int, trainingTypeRaw: String, planId: UUID?, note: String,
         trackData: Data?, cadenceSeriesData: Data?, splitsData: Data?) {
        self.id = id; self.userId = userId
        self.startDate = startDate; self.endDate = endDate
        self.duration = duration; self.distanceMeters = distanceMeters
        self.avgCadence = avgCadence; self.maxCadence = maxCadence
        self.calories = calories; self.steps = steps
        self.trainingTypeRaw = trainingTypeRaw; self.planId = planId; self.note = note
        self.trackData = trackData; self.cadenceSeriesData = cadenceSeriesData
        self.splitsData = splitsData
    }
}

@available(iOS 17.0, *)
@Model
final class TrainingPlanEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID?
    var name: String
    var typeRaw: String
    /// JSON: [Stage]
    var stagesData: Data?

    init(id: UUID = UUID(), userId: UUID?, name: String, typeRaw: String, stagesData: Data?) {
        self.id = id; self.userId = userId; self.name = name
        self.typeRaw = typeRaw; self.stagesData = stagesData
    }
}

// MARK: - Entity <-> 值类型映射
@available(iOS 17.0, *)
extension RunRecordEntity {
    convenience init(_ r: RunSummary) {
        self.init(id: r.id, userId: r.userId,
                  startDate: r.startDate, endDate: r.endDate,
                  duration: r.duration, distanceMeters: r.distanceMeters,
                  avgCadence: r.avgCadence, maxCadence: r.maxCadence,
                  calories: r.calories, steps: r.steps,
                  trainingTypeRaw: r.trainingType.rawValue, planId: r.planId, note: r.note,
                  trackData: try? JSONEncoder().encode(r.track),
                  cadenceSeriesData: try? JSONEncoder().encode(r.cadenceSeries),
                  splitsData: try? JSONEncoder().encode(r.splits))
    }

    func summary() -> RunSummary {
        var r = RunSummary(
            id: id, userId: userId, startDate: startDate, endDate: endDate,
            duration: duration, distanceMeters: distanceMeters,
            avgCadence: avgCadence, maxCadence: maxCadence, calories: calories,
            steps: steps,
            trainingType: TrainingType(rawValue: trainingTypeRaw) ?? .free,
            planId: planId, note: note)
        if let d = trackData { r.track = (try? JSONDecoder().decode([TrackPoint].self, from: d)) ?? [] }
        if let d = cadenceSeriesData { r.cadenceSeries = (try? JSONDecoder().decode([CadenceSample].self, from: d)) ?? [] }
        if let d = splitsData { r.splits = (try? JSONDecoder().decode([Split].self, from: d)) ?? [] }
        return r
    }
}
