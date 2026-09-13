import Foundation
import SwiftUI
import Combine

/// 全局持久化门面：
/// - iOS 17+：SwiftData（@Model 实体）
/// - iOS 16：Documents 目录 JSON 兜底（需求要求最低 iOS 16，SwiftData 仅 iOS 17+）
final class PersistenceStore: ObservableObject {
    static let shared = PersistenceStore()

    @Published var profile: UserProfile
    @Published var settings: AppSettings

    private let backend: any HistoryStore

    init() {
        let profileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile.json")
        self.profile = (try? Self.load(UserProfile.self, from: profileURL)) ?? UserProfile()
        self.settings = AppSettings.load()
        if #available(iOS 17.0, *) {
            backend = SwiftDataHistoryStore()
        } else {
            backend = JSONHistoryStore()
        }
        self.profileURL = profileURL
    }

    private let profileURL: URL

    // MARK: Profile / Settings

    func saveProfile(_ p: UserProfile) {
        profile = p
        try? Self.encode(p).write(to: profileURL, options: .atomic)
    }

    func saveSettings(_ s: AppSettings) {
        settings = s
        s.save()
    }

    // MARK: Runs

    func runs(limit: Int? = nil) -> [RunSummary] {
        backend.fetchRuns(limit: limit)
    }

    func saveRun(_ run: RunSummary) {
        backend.insertRun(run)
    }

    func deleteRun(id: UUID) {
        backend.deleteRun(id: id)
    }

    func deleteAll() {
        backend.deleteAllRuns()
        try? FileManager.default.removeItem(at: profileURL)
        profile = UserProfile()
    }

    // MARK: Plans

    func plans() -> [TrainingPlan] { backend.fetchPlans() }
    func savePlan(_ plan: TrainingPlan) { backend.upsertPlan(plan) }
    func deletePlan(id: UUID) { backend.deletePlan(id: id) }

    // MARK: Helpers

    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}

// MARK: - 存储协议

protocol HistoryStore {
    func fetchRuns(limit: Int?) -> [RunSummary]
    func insertRun(_ run: RunSummary)
    func deleteRun(id: UUID)
    func deleteAllRuns()
    func fetchPlans() -> [TrainingPlan]
    func upsertPlan(_ plan: TrainingPlan)
    func deletePlan(id: UUID)
}

// MARK: - iOS 16 JSON 实现

final class JSONHistoryStore: HistoryStore {
    private let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var runsURL: URL { dir.appendingPathComponent("runs.json") }
    private var plansURL: URL { dir.appendingPathComponent("plans.json") }
    private let queue = DispatchQueue(label: "com.temporun.jsonstore")

    func fetchRuns(limit: Int?) -> [RunSummary] {
        let all = (try? PersistenceStore.load([RunSummary].self, from: runsURL)) ?? []
        let sorted = all.sorted { $0.startDate > $1.startDate }
        return limit.map { Array(sorted.prefix($0)) } ?? sorted
    }

    func insertRun(_ run: RunSummary) {
        queue.sync {
            var all = (try? PersistenceStore.load([RunSummary].self, from: runsURL)) ?? []
            all.append(run)
            if let data = try? PersistenceStore.encode(all) {
                try? data.write(to: runsURL, options: .atomic)
            }
        }
    }

    func deleteRun(id: UUID) {
        queue.sync {
            var all = (try? PersistenceStore.load([RunSummary].self, from: runsURL)) ?? []
            all.removeAll { $0.id == id }
            if let data = try? PersistenceStore.encode(all) {
                try? data.write(to: runsURL, options: .atomic)
            }
        }
    }

    func deleteAllRuns() {
        try? FileManager.default.removeItem(at: runsURL)
        try? FileManager.default.removeItem(at: plansURL)
    }

    func fetchPlans() -> [TrainingPlan] {
        (try? PersistenceStore.load([TrainingPlan].self, from: plansURL)) ?? []
    }

    func upsertPlan(_ plan: TrainingPlan) {
        queue.sync {
            var all = (try? PersistenceStore.load([TrainingPlan].self, from: plansURL)) ?? []
            if let i = all.firstIndex(where: { $0.id == plan.id }) { all[i] = plan } else { all.append(plan) }
            if let data = try? PersistenceStore.encode(all) {
                try? data.write(to: plansURL, options: .atomic)
            }
        }
    }

    func deletePlan(id: UUID) {
        queue.sync {
            var all = (try? PersistenceStore.load([TrainingPlan].self, from: plansURL)) ?? []
            all.removeAll { $0.id == id }
            if let data = try? PersistenceStore.encode(all) {
                try? data.write(to: plansURL, options: .atomic)
            }
        }
    }
}

// MARK: - AppSettings

struct AppSettings: Codable {
    var beatVolume: Float = 0.9
    var soundRaw: String = BeatSound.click.rawValue
    var hapticsEnabled = true
    var stereoFeet = true
    var voiceAlerts = true
    var deviationAlerts = true
    var healthSync = false
    var stravaSync = false
    var keepAliveSilent = true
    var dashboardFields: [DashboardField] = DashboardField.allCases
    var colorSchemeRaw: String = "system"

    static func load() -> AppSettings {
        guard let url = url, let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }
    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
    private static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("settings.json")
    }
}

enum DashboardField: String, Codable, CaseIterable, Identifiable {
    case cadence = "实时步频"
    case target = "目标步频"
    case distance = "距离"
    case duration = "时长"
    case pace = "配速"
    case steps = "步数"
    case calories = "卡路里"
    case stage = "当前阶段"
    case signal = "信号质量"
    var id: String { rawValue }
}
