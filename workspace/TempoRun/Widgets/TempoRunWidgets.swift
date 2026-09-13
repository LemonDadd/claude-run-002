import WidgetKit
import SwiftUI
import AppIntents

@main
struct TempoRunWidgetBundle: WidgetBundle {
    var body: some Widget {
        RunLockScreenWidget()
        if #available(iOS 16.1, *) {
            RunLiveActivityWidget()
        }
    }
}

// MARK: - 锁屏小组件

struct RunLockScreenWidget: Widget {
    let kind = "RunLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RunStatusProvider()) { entry in
            LockScreenView(state: entry.state)
        }
        .configurationDisplayName("TempoRun 跑步")
        .description("实时步频、配速与距离，一键暂停/继续")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct LockScreenView: View {
    let state: LiveActivityState
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(state.cadence)").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("SPM").font(.system(size: 8))
                }
            }
        case .accessoryInline:
            Label("\(state.cadence) SPM · \(Formatters.distance(meters: state.distanceMeters))",
                  systemImage: "figure.run")
        default:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(state.status.title, systemImage: "figure.run")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if let stage = state.stageName {
                        Text(stage).font(.system(size: 10)).opacity(0.8)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(state.cadence)").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("/ \(state.targetCadence) SPM").font(.system(size: 10))
                    Spacer()
                    Text(Formatters.duration(state.elapsed)).font(.system(size: 12, weight: .medium))
                }
            }
        }
    }
}

// MARK: - Live Activity

@available(iOS 16.1, *)
struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LiveActivityView(state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("步频").font(.caption2).foregroundColor(.secondary)
                        Text("\(state.cadence)")
                            .font(.title2.bold().monospacedDigit())
                        Text("目标 \(state.targetCadence)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("时间").font(.caption2).foregroundColor(.secondary)
                        Text(Formatters.duration(state.elapsed))
                            .font(.title3.bold().monospacedDigit())
                        Text(Formatters.distance(meters: state.distanceMeters))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if #available(iOS 17.0, *) {
                        ExpandedControls(state: state)
                    } else {
                        // iOS 16.x：深链到 App 控制
                        HStack(spacing: 12) {
                            Link(destination: URL(string: "temporun://cmd/down")!) {
                                Image(systemName: "minus").padding(6)
                            }
                            Link(destination: URL(string: "temporun://cmd/pause")!) {
                                Label("暂停", systemImage: "pause.fill")
                            }
                            Link(destination: URL(string: "temporun://cmd/up")!) {
                                Image(systemName: "plus").padding(6)
                            }
                            Link(destination: URL(string: "temporun://cmd/stop")!) {
                                Label("停止", systemImage: "stop.fill")
                            }
                        }
                        .font(.caption.bold())
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let stage = state.stageName {
                        Text(stage).font(.caption).foregroundColor(.accentColor)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.run")
            } compactTrailing: {
                Text("\(state.cadence)").font(.caption.bold())
            } minimal: {
                Text("\(state.cadence)")
            }
        }
    }
}

// MARK: - 展开锁屏 UI

struct LiveActivityView: View {
    let state: LiveActivityState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(state.status.title, systemImage: "figure.run")
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                Spacer()
                if let stage = state.stageName {
                    Text(stage).font(.caption).foregroundColor(.secondary)
                }
                if let remain = state.stageRemaining {
                    Text(Formatters.duration(remain)).font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading) {
                    Text("实时步频").font(.caption2).foregroundColor(.secondary)
                    Text("\(state.cadence)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(deviationColor)
                    Text("目标 \(state.targetCadence) SPM")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    metric(Formatters.duration(state.elapsed), label: "时间")
                    metric(Formatters.distance(meters: state.distanceMeters), label: "距离")
                }
            }
            if #available(iOS 17.0, *) {
                ExpandedControls(state: state)
            }
        }
        .padding()
    }

    private var deviationColor: Color {
        abs(state.deviation) >= 5 ? .orange : .primary
    }

    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .trailing) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}

@available(iOS 17.0, *)
struct ExpandedControls: View {
    let state: LiveActivityState

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: CadenceDownIntent()) {
                Image(systemName: "minus").labelStyle(.iconOnly)
            }
            .tint(.secondary)
            .controlSize(.small)
            .accessibilityLabel("步频减 5")

            Text("-5 / +5 SPM").font(.caption2).foregroundColor(.secondary)

            Button(intent: CadenceUpIntent()) {
                Image(systemName: "plus")
            }
            .tint(.secondary)
            .controlSize(.small)
            .accessibilityLabel("步频加 5")

            Spacer(minLength: 4)

            if state.status == .paused {
                Button(intent: ResumeRunIntent()) {
                    Label("继续", systemImage: "play.fill")
                }
                .tint(.green)
                .controlSize(.small)
            } else {
                Button(intent: PauseRunIntent()) {
                    Label("暂停", systemImage: "pause.fill")
                }
                .tint(.orange)
                .controlSize(.small)
            }

            Button(intent: StopRunIntent()) {
                Label("停止", systemImage: "stop.fill")
            }
            .tint(.red)
            .controlSize(.small)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }
}
