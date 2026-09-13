import Foundation
import SwiftUI
import Combine

/// 全局跑步协调器：App / Widget AppIntents / Live Activity 共享同一个活动会话入口。
/// Widget 通过 Darwin 通知下发命令，TrainingSession 内监听并执行。
@MainActor
final class RunCoordinator: ObservableObject {
    static let shared = RunCoordinator()

    @Published var session: TrainingSession?
    /// 最近一次完成的跑步（摘要页展示）
    @Published var lastFinishedRun: RunSummary?

    private init() {
        // 训练结束后弹出摘要
        NotificationCenter.default.addObserver(forName: .runDidFinish, object: nil, queue: .main) { note in
            if let run = note.object as? RunSummary {
                Task { @MainActor in
                    self.lastFinishedRun = run
                    self.session = nil
                }
            }
        }
    }

    func prepare(_ plan: TrainingPlan, target: Int? = nil) -> TrainingSession {
        var p = plan
        if let target, let i = p.stages.indices.first {
            p.stages[i].targetCadence = target
        }
        let s = TrainingSession(plan: p)
        session = s
        return s
    }

    func startFreeRun(target: Int) -> TrainingSession {
        var plan = TrainingPlan.freePlan
        plan.stages[0].targetCadence = target
        let s = prepare(plan, target: target)
        s.start()
        return s
    }

    var isActive: Bool { session?.state == .running || session?.state == .paused }
}

extension Notification.Name {
    static let runDidFinish = Notification.Name("com.temporun.runDidFinish")
}
