import SwiftUI

struct HistoryView: View {
    @State private var allRuns: [RunSummary] = PersistenceStore.shared.runs()
    @State private var selected: RunSummary?
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showPaywall = false

    private let freeWindow: TimeInterval = 7 * 24 * 3600

    /// 免费版仅最近 7 天
    private var visibleRuns: [RunSummary] {
        guard !subs.isPro else { return allRuns }
        let cutoff = Date().addingTimeInterval(-freeWindow)
        return allRuns.filter { $0.startDate >= cutoff }
    }

    private var hiddenCount: Int { allRuns.count - visibleRuns.count }

    var body: some View {
        NavigationStack {
            Group {
                if allRuns.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray").font(.largeTitle).foregroundColor(.secondary)
                        Text("暂无跑步记录").foregroundColor(.secondary)
                    }
                } else {
                    List {
                        if hiddenCount > 0 {
                            Section {
                                Button {
                                    showPaywall = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "lock.fill").foregroundColor(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("还有 \(hiddenCount) 条更早的记录被锁定")
                                                .font(.subheadline.weight(.semibold))
                                            Text("升级 Pro 查看全部历史记录与步频曲线")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("Pro")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(.orange, in: Capsule())
                                            .foregroundColor(.white)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            } footer: {
                                Text("免费版保留最近 7 天记录")
                            }
                        }

                        ForEach(visibleRuns) { run in
                            Button { selected = run } label: { HistoryRow(run: run) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        PersistenceStore.shared.deleteRun(id: run.id)
                                        allRuns = PersistenceStore.shared.runs()
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史记录")
            .sheet(item: $selected) { RunSummaryView(run: $0) }
            .sheet(isPresented: $showPaywall) {
                PaywallView(subscriptions: subs, feature: .fullHistory)
            }
            .onChange(of: subs.status) { _ in
                allRuns = PersistenceStore.shared.runs()
            }
        }
    }
}

private struct HistoryRow: View {
    let run: RunSummary
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: run.trainingType.icon).foregroundColor(.accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(Formatters.day.string(from: run.startDate)).font(.subheadline.weight(.semibold))
                Text("\(run.trainingType.rawValue) · \(Formatters.clock.string(from: run.startDate))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.2f km", run.distanceKilometers)).font(.headline)
                Text("\(run.avgCadence) SPM").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
