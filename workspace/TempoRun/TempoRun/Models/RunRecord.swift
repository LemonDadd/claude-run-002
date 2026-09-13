import Foundation

// MARK: - 枚举
enum TrainingType: String, Codable, CaseIterable, Identifiable {
    case free = "自由跑"
    case fixed = "定频跑"
    case interval = "间歇训练"
    case custom = "自定义计划"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .free: return "figure.run"
        case .fixed: return "metronome"
        case .interval: return "timer"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum StageType: String, Codable, CaseIterable, Identifiable {
    case warmup = "热身"
    case fast = "快跑"
    case slow = "慢跑"
    case cooldown = "冷身"
    case steady = "匀速"
    var id: String { rawValue }
    var colorName: String {
        switch self {
        case .warmup:   return "StageWarmup"
        case .fast:     return "StageFast"
        case .slow:     return "StageSlow"
        case .cooldown: return "StageCooldown"
        case .steady:   return "StageSteady"
        }
    }
}

enum Gender: String, Codable, CaseIterable {
    case male = "男", female = "女", other = "其他"
}

enum UnitSystem: String, Codable, CaseIterable {
    case metric = "公制", imperial = "英制"
}

// MARK: - 值类型（JSON 持久化 / Widget 共享安全）
struct TrackPoint: Codable, Hashable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
}

struct CadenceSample: Codable, Hashable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let spm: Int
}

struct Split: Codable, Hashable, Identifiable {
    var id: Int { kilometer }
    let kilometer: Int
    let duration: TimeInterval
    let avgCadence: Int
    var pace: TimeInterval { duration } // 每公里秒数
}

/// 一条完整的跑步记录（与持久化实体解耦的值类型）
struct RunSummary: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID?
    var startDate: Date = Date()
    var endDate: Date = Date()
    var duration: TimeInterval = 0
    var distanceMeters: Double = 0
    var avgCadence: Int = 0
    var maxCadence: Int = 0
    var calories: Double = 0
    var steps: Int = 0
    var trainingType: TrainingType = .free
    var planId: UUID?
    var note: String = ""
    var track: [TrackPoint] = []
    var cadenceSeries: [CadenceSample] = []
    var splits: [Split] = []

    var avgPace: TimeInterval { // sec/km
        distanceMeters > 50 ? duration / (distanceMeters / 1000) : 0
    }
    var distanceKilometers: Double { distanceMeters / 1000 }
}

struct UserProfile: Codable, Hashable {
    var id: UUID = UUID()
    var nickname: String = "跑者"
    var avatarData: Data?
    var gender: Gender = .other
    var age: Int?
    var weightKg: Double = 65
    var heightCm: Double = 170
    var unit: UnitSystem = .metric
    var language: String = Locale.preferredLanguages.first ?? "zh-Hans"
    /// 订阅状态（免费 / 试用 / 订阅 / 终身）
    var subscriptionStatus: SubscriptionStatus = .free
    /// 订阅到期时间（lifetime 为 nil；月付/年付为续费或过期时间）
    var subscriptionExpiryDate: Date?

    // 显式 CodingKeys + decodeIfPresent，保证旧版本 profile.json 可平滑升级
    enum CodingKeys: String, CodingKey {
        case id, nickname, avatarData, gender, age, weightKg, heightCm, unit, language
        case subscriptionStatus, subscriptionExpiryDate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? "跑者"
        avatarData = try c.decodeIfPresent(Data.self, forKey: .avatarData)
        gender = try c.decodeIfPresent(Gender.self, forKey: .gender) ?? .other
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 65
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? 170
        unit = try c.decodeIfPresent(UnitSystem.self, forKey: .unit) ?? .metric
        language = try c.decodeIfPresent(String.self, forKey: .language)
            ?? (Locale.preferredLanguages.first ?? "zh-Hans")
        subscriptionStatus = try c.decodeIfPresent(SubscriptionStatus.self, forKey: .subscriptionStatus) ?? .free
        subscriptionExpiryDate = try c.decodeIfPresent(Date.self, forKey: .subscriptionExpiryDate)
    }
}

struct Stage: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var type: StageType = .steady
    var targetCadence: Int = 170
    var duration: TimeInterval = 300   // 秒；0 表示按距离
    var distanceMeters: Double = 0
}

struct TrainingPlan: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var userId: UUID?
    var name: String = ""
    var type: TrainingType = .custom
    var stages: [Stage] = []
}
