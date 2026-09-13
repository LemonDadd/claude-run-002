import SwiftUI
import MapKit

/// 跑步摘要页：数据总览 + 步频曲线 + 轨迹地图 + 分段数据
struct RunSummaryView: View {
    let run: RunSummary
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion?
    @ObservedObject private var subs = SubscriptionManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    overview
                    cadenceSection
                    mapSection
                    splitsSection
                    syncButtons
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("跑步摘要")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: configureMap)
        }
    }

    // MARK: 总览

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            MetricTile(title: "距离",
                       value: String(format: "%.2f", run.distanceKilometers), unit: "km", emphasis: true)
            MetricTile(title: "时长", value: Formatters.duration(run.duration), emphasis: true)
            MetricTile(title: "平均配速", value: Formatters.pace(secondsPerKm: run.avgPace), unit: "/km")
            MetricTile(title: "平均步频", value: "\(run.avgCadence)", unit: "SPM")
            MetricTile(title: "最大步频", value: "\(run.maxCadence)", unit: "SPM")
            MetricTile(title: "步数", value: "\(run.steps)")
            MetricTile(title: "卡路里", value: String(format: "%.0f", run.calories), unit: "kcal")
            MetricTile(title: "类型", value: run.trainingType.rawValue)
        }
        .card()
    }

    private var cadenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("步频曲线").font(.headline)
            if run.cadenceSeries.count < 2 {
                Text("本次跑步时长较短，暂无曲线数据")
                    .font(.subheadline).foregroundColor(.secondary)
            } else {
                CadenceChart(series: run.cadenceSeries, target: targetCadence)
            }
        }
        .card()
    }

    private var targetCadence: Int {
        // 取曲线中值附近的典型目标；摘要中按最接近众数估计，实际可持久化目标
        let values = run.cadenceSeries.map(\.spm).filter { $0 > 0 }
        guard !values.isEmpty else { return 170 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: 轨迹地图

    @ViewBuilder private var mapSection: some View {
        if let region {
            VStack(alignment: .leading, spacing: 12) {
                Text("轨迹").font(.headline)
                Map(coordinateRegion: .constant(region),
                    annotationItems: annotations) { point in
                    MapMarker(coordinate: point.coordinate)
                }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardRadius))
                    .allowsHitTesting(false)
            }
            .card()
        }
    }

    private struct RunMapPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    private var annotations: [RunMapPin] {
        // 抽稀，最多 40 个点
        guard run.track.count > 40 else {
            return run.track.map { RunMapPin(coordinate: .init(latitude: $0.latitude, longitude: $0.longitude)) }
        }
        return stride(from: 0, to: run.track.count, by: run.track.count / 40).map {
            RunMapPin(coordinate: .init(latitude: run.track[$0].latitude, longitude: run.track[$0].longitude))
        }
    }

    private func configureMap() {
        guard let first = run.track.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for p in run.track {
            minLat = min(minLat, p.latitude); maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude); maxLon = max(maxLon, p.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.3),
                                    longitudeDelta: max(0.005, (maxLon - minLon) * 1.3))
        region = MKCoordinateRegion(center: center, span: span)
    }

    // MARK: 分段

    private var splitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分段数据").font(.headline)
            if run.splits.isEmpty {
                Text("距离不足 1 公里，暂无分段").font(.subheadline).foregroundColor(.secondary)
            } else {
                HStack {
                    Text("公里").font(.caption.bold()).foregroundColor(.secondary)
                    Spacer()
                    Text("配速").font(.caption.bold()).foregroundColor(.secondary)
                    Spacer()
                    Text("步频").font(.caption.bold()).foregroundColor(.secondary)
                }
                ForEach(run.splits) { split in
                    Divider()
                    HStack {
                        Text("\(split.kilometer) km").font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Formatters.pace(secondsPerKm: split.pace)).monospacedDigit()
                        Spacer()
                        Text("\(split.avgCadence)").monospacedDigit().foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    private var syncButtons: some View {
        VStack(spacing: 12) {
            ProButton(feature: .healthSync, action: {
                HealthService.shared.requestAuthorization { ok in
                    if ok { HealthService.shared.writeRun(run) }
                }
            }, label: {
                Label("同步到「健康」", systemImage: "heart.text.square.fill")
                    .frame(maxWidth: .infinity).padding()
            })
            .buttonStyle(.borderedProminent)

            ProButton(feature: .stravaSync, action: {
                Task { _ = await StravaService.shared.upload(run) }
            }, label: {
                Label("同步到 Strava", systemImage: "figure.outdoor.cycle")
                    .frame(maxWidth: .infinity).padding()
            })
            .buttonStyle(.bordered)

            if !subs.isPro {
                Text("数据同步为 Pro 功能，点击查看权益")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
