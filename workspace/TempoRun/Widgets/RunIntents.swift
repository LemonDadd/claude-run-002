import AppIntents
import WidgetKit

/// Widget / 灵动岛按钮：iOS 17+ 直接在扩展内执行 AppIntent；
/// 命令通过 App Group + Darwin 通知转发给主 App 的 TrainingSession。
/// （stop 需要打开 App 保存记录，openAppWhenRun = true）
@available(iOS 16.1, *)
struct PauseRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暂停"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult { RunCommands.send(.pause); return .result() }
}

@available(iOS 16.1, *)
struct ResumeRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "继续"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult { RunCommands.send(.resume); return .result() }
}

@available(iOS 16.1, *)
struct StopRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult { RunCommands.send(.stop); return .result() }
}

@available(iOS 16.1, *)
struct CadenceUpIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "步频 +5"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult { RunCommands.send(.bumpUp); return .result() }
}

@available(iOS 16.1, *)
struct CadenceDownIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "步频 -5"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult { RunCommands.send(.bumpDown); return .result() }
}

/// 锁屏小组件时间线：主 App 同时把状态发布到 App Group，这里 1s 刷新兜底
struct RunStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunStatusEntry { RunStatusEntry(date: Date(), state: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (RunStatusEntry) -> Void) {
        completion(RunStatusEntry(date: Date(), state: RunCommands.currentState()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RunStatusEntry>) -> Void) {
        let now = Date()
        let state = RunCommands.currentState()
        let entries = (0..<60).map { i in
            RunStatusEntry(date: now.addingTimeInterval(TimeInterval(i)), state: state)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct RunStatusEntry: TimelineEntry {
    let date: Date
    let state: LiveActivityState
}
