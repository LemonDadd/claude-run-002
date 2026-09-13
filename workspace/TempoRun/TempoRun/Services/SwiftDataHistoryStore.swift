import Foundation
import SwiftData

/// iOS 17+ 的 SwiftData 实现（与需求中的数据模型一致：
/// User / RunRecord / TrainingPlan / Stage[JSON 嵌入]）
///
/// Swift 6 严格并发下 `container.mainContext` 是 @MainActor 隔离的，
/// 这里自建一个非隔离的 ModelContext（ModelContext 自身非 Sendable，
/// 因此所有访问串行化到专用队列），供任意线程调用。
@available(iOS 17.0, *)
final class SwiftDataHistoryStore: HistoryStore {

    let container: ModelContainer
    private let queue = DispatchQueue(label: "com.temporun.swiftdata")

    init() {
        let schema = Schema([UserEntity.self, RunRecordEntity.self, TrainingPlanEntity.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false) // 隐私：默认不走 CloudKit
        container = try! ModelContainer(for: schema, configurations: [config])
    }

    /// 在串行队列上同步执行，闭包内拿到独立的非 MainActor ModelContext
    private func perform<T>(_ work: (ModelContext) -> T) -> T {
        queue.sync {
            let context = ModelContext(container)
            return work(context)
        }
    }

    func fetchRuns(limit: Int?) -> [RunSummary] {
        perform { context in
            var desc = FetchDescriptor<RunRecordEntity>(
                sortBy: [SortDescriptor(\.startDate, order: .reverse)])
            desc.fetchLimit = limit
            let entities = (try? context.fetch(desc)) ?? []
            return entities.map { $0.summary() }
        }
    }

    func insertRun(_ run: RunSummary) {
        perform { context in
            context.insert(RunRecordEntity(run))
            try? context.save()
        }
    }

    func deleteRun(id: UUID) {
        perform { context in
            try? context.delete(model: RunRecordEntity.self, where: #Predicate { $0.id == id })
            try? context.save()
        }
    }

    func deleteAllRuns() {
        perform { context in
            try? context.delete(model: RunRecordEntity.self)
            try? context.delete(model: TrainingPlanEntity.self)
            try? context.delete(model: UserEntity.self)
            try? context.save()
        }
    }

    func fetchPlans() -> [TrainingPlan] {
        perform { context in
            let entities = (try? context.fetch(FetchDescriptor<TrainingPlanEntity>())) ?? []
            return entities.compactMap { e -> TrainingPlan? in
                guard let data = e.stagesData,
                      let stages = try? JSONDecoder().decode([Stage].self, from: data) else { return nil }
                return TrainingPlan(id: e.id, userId: e.userId, name: e.name,
                                    type: TrainingType(rawValue: e.typeRaw) ?? .custom,
                                    stages: stages)
            }
        }
    }

    func upsertPlan(_ plan: TrainingPlan) {
        perform { context in
            let desc = FetchDescriptor<TrainingPlanEntity>(
                predicate: #Predicate { $0.id == plan.id })
            if let existing = (try? context.fetch(desc))?.first {
                existing.name = plan.name
                existing.typeRaw = plan.type.rawValue
                existing.stagesData = try? JSONEncoder().encode(plan.stages)
            } else {
                context.insert(TrainingPlanEntity(
                    id: plan.id, userId: plan.userId, name: plan.name,
                    typeRaw: plan.type.rawValue,
                    stagesData: try? JSONEncoder().encode(plan.stages)))
            }
            try? context.save()
        }
    }

    func deletePlan(id: UUID) {
        perform { context in
            try? context.delete(model: TrainingPlanEntity.self, where: #Predicate { $0.id == id })
            try? context.save()
        }
    }
}
