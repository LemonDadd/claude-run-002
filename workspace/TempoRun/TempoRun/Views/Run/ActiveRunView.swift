import SwiftUI
import MapKit

/// 训练中页：大号防误触按钮、可自定义实时面板、±5 快捷调频
struct ActiveRunView: View {
    @ObservedObject var session: TrainingSession
    @Environment(\.dismiss) private var dismiss
    @State private var showStopConfirm = false
    @State private var showDashboardConfig = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                stageBar
                cadenceHero
                if session.location.permission == .denied {
                    locationDeniedBanner
                }
                if let banner = session.deviationBanner {
                    Label(banner, systemImage: "speedometer")
                        .font(.headline)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundColor(.orange)
                        .accessibilityAnnouncement(banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                dashboard
                miniMap
                quickCadenceControls
                actionButtons
            }
            .padding()
            .padding(.bottom, 24)
        }
        .background(session.stageFlash ? DesignSystem.stage(session.currentStage?.type ?? .steady).opacity(0.18)
                    : Color(.systemGroupedBackground))
        .animation(.easeInOut(duration: 0.3), value: session.stageFlash)
        .navigationBarBackButtonHidden(true)
        // 二级跑步页隐藏底部 TabBar，避免误触切走
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDashboardConfig = true
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .alert("结束并保存本次跑步？", isPresented: $showStopConfirm) {
            Button("继续跑步", role: .cancel) {}
            Button("结束并保存", role: .destructive) {
                session.stopAndSave()
                dismiss()
            }
            Button("放弃记录", role: .destructive) {
                session.discardRun()
                dismiss()
            }
        }
        .sheet(isPresented: $showDashboardConfig) {
            DashboardConfigView()
        }
        .onAppear {
            session.location.requestPermission()
            followLocation()
        }
        .onReceive(session.location.$lastLocation) { location in
            // 持续跟随用户真实位置（保持当前缩放跨度）
            guard let location else { return }
            mapRegion.center = location.coordinate
        }
    }

    private var locationDeniedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill").foregroundColor(.red)
            Text("定位未授权，轨迹无法记录").font(.subheadline.weight(.semibold))
            Spacer()
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.bold())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .foregroundColor(.red)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Label(session.trainingType.rawValue, systemImage: session.trainingType.icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
            Spacer()
            Text(Formatters.duration(session.elapsed))
                .font(.title2.bold().monospacedDigit())
                .accessibilityLabel("已用时 \(Formatters.duration(session.elapsed))")
        }
    }

    // MARK: 阶段条

    @ViewBuilder private var stageBar: some View {
        if !session.stages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let stage = session.currentStage {
                        Circle().fill(DesignSystem.stage(stage.type)).frame(width: 12, height: 12)
                        Text("\(stage.type.rawValue) · 目标 \(session.effectiveTargetCadence) SPM")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if let remain = session.stageRemaining {
                        Text(Formatters.duration(remain))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                if session.stages.count > 1 {
                    if let stage = session.currentStage, stage.duration > 0 {
                        ProgressView(value: min(stageElapsedDisplay, stage.duration), total: stage.duration)
                            .tint(DesignSystem.stage(stage.type))
                    } else {
                        ProgressView(value: Double(session.stageIndex),
                                     total: Double(max(1, session.stages.count - 1)))
                            .tint(DesignSystem.stage(session.currentStage?.type ?? .steady))
                    }
                }
            }
            .card()
        }
    }

    // MARK: 步频主屏

    private var cadenceHero: some View {
        VStack(spacing: 4) {
            Text("\(session.cadence)")
                .font(.system(size: 92, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(deviationColor)
                .accessibilityLabel("实时步频 \(session.cadence)")
            Text("SPM · 目标 \(session.effectiveTargetCadence)")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .card()
    }

    private var deviationColor: Color {
        abs(session.cadence - session.effectiveTargetCadence) >= AppConstants.deviationAlertThreshold
            ? .orange : .primary
    }

    private var stageElapsedDisplay: TimeInterval {
        // stageElapsed 是 @Published，读取即可驱动进度
        session.stageElapsed
    }

    // MARK: 自定义数据面板

    private var dashboard: some View {
        let fields = PersistenceStore.shared.settings.dashboardFields
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(fields) { field in
                tile(for: field)
            }
        }
    }

    @ViewBuilder
    private func tile(for field: DashboardField) -> some View {
        switch field {
        case .cadence:
            MetricTile(title: "实时步频", value: "\(session.cadence)", unit: "SPM", emphasis: false)
                .card()
        case .target:
            MetricTile(title: "目标步频", value: "\(session.effectiveTargetCadence)", unit: "SPM")
                .card()
        case .distance:
            MetricTile(title: "距离",
                       value: session.distanceMeters >= 1000
                        ? String(format: "%.2f", session.distanceMeters / 1000)
                        : String(format: "%.0f", session.distanceMeters),
                       unit: session.distanceMeters >= 1000 ? "km" : "m")
                .card()
        case .duration:
            MetricTile(title: "时长", value: Formatters.duration(session.elapsed))
                .card()
        case .pace:
            MetricTile(title: "配速", value: Formatters.pace(secondsPerKm: session.pace), unit: "/km")
                .card()
        case .steps:
            MetricTile(title: "步数", value: "\(session.steps)")
                .card()
        case .calories:
            MetricTile(title: "卡路里", value: String(format: "%.0f", session.calories), unit: "kcal")
                .card()
        case .stage:
            MetricTile(title: "当前阶段",
                       value: session.currentStage.map { "\(session.stageIndex + 1)/\(session.stages.count) \($0.type.rawValue)" } ?? "—")
                .card()
        case .signal:
            MetricTile(title: "信号质量",
                       value: String(format: "%.0f%%", session.cadenceEngine.signalQuality * 100))
                .card()
        }
    }

    // MARK: 迷你地图

    private var miniMap: some View {
        // 用 onReceive 手动跟随 + 显示用户蓝点，避免 userTrackingMode 与手动居中互相抢
        Map(coordinateRegion: $mapRegion, showsUserLocation: true)
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardRadius))
            .allowsHitTesting(false)
    }

    private func followLocation() {
        if let loc = session.location.lastLocation {
            mapRegion.center = loc.coordinate
        }
    }

    // MARK: ±5 快捷调频（训练中动态调整，不中断）

    private var quickCadenceControls: some View {
        HStack(spacing: 12) {
            Button { session.adjustCurrentStageCadence(by: -5) } label: {
                Label("-5", systemImage: "backward.fill").frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityLabel("目标步频减 5")

            Button { session.adjustCurrentStageCadence(by: 5) } label: {
                Label("+5", systemImage: "forward.fill").frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityLabel("目标步频加 5")
        }
    }

    // MARK: 主操作（暂停/继续/停止）

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if session.state == .running {
                BigActionButton(title: "暂停", systemImage: "pause.fill", style: .secondary) {
                    session.pause()
                }
            } else {
                BigActionButton(title: "继续", systemImage: "play.fill", style: .primary) {
                    session.resume()
                }
            }
            BigActionButton(title: "停止并保存", systemImage: "stop.fill", style: .danger) {
                showStopConfirm = true // 防误触：二次确认
            }
        }
    }
}

private extension View {
    /// 偏离横幅出现时进行 VoiceOver 朗读
    func accessibilityAnnouncement(_ text: String) -> some View {
        onChange(of: text) { _ in
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}
