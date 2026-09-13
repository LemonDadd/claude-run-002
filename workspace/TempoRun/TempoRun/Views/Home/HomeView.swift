import SwiftUI

/// 首页：快速开始（1 次点击）、训练模式入口、最近活动
struct HomeView: View {
    @EnvironmentObject var coordinator: RunCoordinator
    @State private var savedTarget: Int = {
        let v = UserDefaults.standard.integer(forKey: "targetCadence")
        return v == 0 ? AppConstants.defaultTargetCadence : v
    }()
    @State private var showPlans = false
    @State private var activeSession: TrainingSession?

    private var recentRuns: [RunSummary] { PersistenceStore.shared.runs(limit: 3) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 一键开始
                    Button {
                        activeSession = coordinator.startFreeRun(target: savedTarget)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.system(size: 56))
                            Text("开始自由跑")
                                .font(.title2.bold())
                            Text("目标 \(savedTarget) SPM · 一键开始")
                                .font(.subheadline)
                                .opacity(0.85)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 168)
                        .background(
                            LinearGradient(colors: [.accentColor, .accentColor.opacity(0.75)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: DesignSystem.radius))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("立即以当前目标步频开始跑步")

                    // 免费版广告位（Pro 自动隐藏）
                    AdBannerView(placement: "home")

                    // 训练模式
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(TrainingType.allCases) { type in
                            ModeCard(type: type) {
                                startMode(type)
                            }
                        }
                    }

                    // 最近活动
                    VStack(alignment: .leading, spacing: 12) {
                        Text("最近活动").font(.headline)
                        if recentRuns.isEmpty {
                            Text("还没有跑步记录，去跑第一步吧 👟")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            ForEach(recentRuns) { run in
                                RecentRunRow(run: run)
                            }
                        }
                    }
                    .card()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("TempoRun")
            .onAppear {
                // 提前请求定位与运动权限，首次开始跑步时不用等待弹窗
                LocationPermissionPrimer.shared.requestWhenInUse()
            }
            .navigationDestination(isPresented: Binding(get: { activeSession != nil },
                                                        set: { if !$0 { activeSession = nil } })) {
                if let s = activeSession {
                    ActiveRunView(session: s)
                }
            }
            .sheet(isPresented: $showPlans) {
                PlanListView { plan in
                    let s = coordinator.prepare(plan)
                    activeSession = s
                    s.start()
                    showPlans = false
                }
            }
        }
    }

    private func startMode(_ type: TrainingType) {
        switch type {
        case .free:
            activeSession = coordinator.startFreeRun(target: savedTarget)
        case .fixed:
            var plan = TrainingPlan.fixedPlan
            plan.stages[0].targetCadence = savedTarget
            let s = coordinator.prepare(plan, target: savedTarget)
            activeSession = s
            s.start()
        case .interval, .custom:
            showPlans = true
        }
    }
}

private struct ModeCard: View {
    let type: TrainingType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: type.icon).font(.title)
                Text(type.rawValue).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: DesignSystem.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择\(type.rawValue)")
    }
}

private struct RecentRunRow: View {
    let run: RunSummary
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.trainingType.rawValue).font(.subheadline.weight(.medium))
                Text(Formatters.day.string(from: run.startDate))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Formatters.distance(meters: run.distanceMeters)).font(.headline)
                Text("\(run.avgCadence) SPM").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
