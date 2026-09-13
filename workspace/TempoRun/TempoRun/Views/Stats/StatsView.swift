import SwiftUI
import Charts

/// 统计视图：日/周/月/年趋势 + PB + 步频分布
struct StatsView: View {
    @State private var runs: [RunSummary] = PersistenceStore.shared.runs()
    @State private var period: StatsPeriod = .week
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showDistributionPaywall = false

    enum StatsPeriod: String, CaseIterable, Identifiable {
        case day = "日", week = "周", month = "月", year = "年"
        var id: String { rawValue }
        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .week: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Picker("周期", selection: $period) {
                        ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    pbSection
                    trendSection
                    distributionSection
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("统计")
        }
    }

    // MARK: PB

    private var pbSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            PBTile(title: "最远距离", value: runs.map(\.distanceKilometers).max().map { String(format: "%.2f km", $0) } ?? "—",
                   icon: "location.north.line")
            PBTile(title: "最长时长", value: runs.map(\.duration).max().map { Formatters.duration($0) } ?? "—",
                   icon: "clock")
            PBTile(title: "最快配速", value: bestPace.map { Formatters.pace(secondsPerKm: $0) } ?? "—",
                   icon: "speedometer")
            PBTile(title: "最高步频", value: runs.map(\.maxCadence).max().map { "\($0) SPM" } ?? "—",
                   icon: "waveform")
        }
        .padding(.horizontal)
    }

    private var bestPace: TimeInterval? {
        let paces = runs.filter { $0.distanceMeters > 1000 }.map(\.avgPace).filter { $0 > 0 }
        return paces.min()
    }

    // MARK: 趋势

    private var trendData: [TrendPoint] {
        let calendar = Calendar.current
        var buckets: [Date: (distance: Double, runs: Int)] = [:]
        for run in runs {
            guard let key = calendar.dateInterval(of: period.component, for: run.startDate)?.start else { continue }
            var v = buckets[key] ?? (0, 0)
            v.distance += run.distanceKilometers
            v.runs += 1
            buckets[key] = v
        }
        return buckets.sorted { $0.key < $1.key }.map {
            TrendPoint(date: $0.key, distance: $0.value.distance, runs: $0.value.runs)
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("距离趋势").font(.headline)
            Chart(trendData) { point in
                BarMark(x: .value("时间", point.date),
                        y: .value("公里", point.distance))
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
            }
            .frame(height: 200)
        }
        .card()
        .padding(.horizontal)
    }

    // MARK: 步频分布

    private var distribution: [CadenceBin] {
        // 120–220 SPM，每 10 一档
        var bins: [Int: Int] = [:]
        for run in runs {
            for s in run.cadenceSeries where s.spm > 0 {
                let bin = (s.spm / 10) * 10
                bins[bin, default: 0] += 1
            }
        }
        return stride(from: 120, through: 220, by: 10).map { CadenceBin(range: $0, count: bins[$0] ?? 0) }
    }

    private var distributionSection: some View {
        Group {
            if subs.isPro {
                VStack(alignment: .leading, spacing: 8) {
                    Text("步频分布").font(.headline)
                    Chart(distribution) { bin in
                        BarMark(x: .value("步频", "\(bin.range)"),
                                y: .value("采样数", bin.count))
                        .foregroundStyle(DesignSystem.stageFast.gradient)
                        .cornerRadius(4)
                    }
                    .frame(height: 200)
                }
                .card()
                .padding(.horizontal)
            } else {
                Button {
                    showDistributionPaywall = true
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill").font(.title2).foregroundColor(.orange)
                        Text("步频分布是 Pro 功能")
                            .font(.headline)
                        Text("查看你在各步频区间的时间分布，发现进步空间")
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Text("升级 Pro")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(.orange, in: Capsule())
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
                .buttonStyle(.plain)
                .card()
                .padding(.horizontal)
                .sheet(isPresented: $showDistributionPaywall) {
                    PaywallView(subscriptions: subs, feature: .cadenceDistribution)
                }
            }
        }
    }
}

private struct TrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let distance: Double
    let runs: Int
}

private struct CadenceBin: Identifiable {
    var id: Int { range }
    let range: Int
    let count: Int
}

private struct PBTile: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
