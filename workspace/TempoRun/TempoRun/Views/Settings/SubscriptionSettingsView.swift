import SwiftUI
import StoreKit

/// 设置页 - 订阅管理
struct SubscriptionSettingsView: View {
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showPaywall = false
    @State private var isRestoring = false

    var body: some View {
        List {
            // MARK: 当前状态
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(subs.isPro ? Color.orange.opacity(0.15) : Color(.tertiarySystemFill))
                            .frame(width: 56, height: 56)
                        Image(systemName: subs.isPro ? "crown.fill" : "crown")
                            .font(.title2)
                            .foregroundColor(subs.isPro ? .orange : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subs.status.displayName).font(.headline)
                        Text(statusDetail)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // MARK: 升级
            if !subs.isPro {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Label("升级 Pro", systemImage: "sparkles")
                                .foregroundColor(.orange)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("解锁全部 5 种音色、无限间歇模板、全部历史、HealthKit 与 Strava 同步、步频分布图，并去除广告。")
                }
            }

            // MARK: 可升级方案（已订阅月付/试用时引导年付/终身）
            if subs.isPro && subs.status != .lifetime {
                Section("升级与续费方案") {
                    ForEach(SubscriptionPlan.allCases) { plan in
                        upgradeRow(plan)
                    }
                }
            }

            // MARK: 恢复 / 管理
            Section {
                Button {
                    isRestoring = true
                    Task {
                        _ = await subs.restore()
                        isRestoring = false
                    }
                } label: {
                    HStack {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("恢复购买")
                    }
                }

                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    Link(destination: url) {
                        Label("管理 App Store 订阅", systemImage: "creditcard")
                    }
                }
            } footer: {
                Text("换设备或重装后可通过「恢复购买」找回权益；订阅续费与取消请在 App Store 账户中管理。")
            }

            // MARK: 环境（调试信息）
            #if DEBUG
            Section("调试") {
                HStack {
                    Text("StoreKit 环境")
                    Spacer()
                    Text(subs.environment.displayName).foregroundColor(.secondary)
                }
                HStack {
                    Text("产品数量")
                    Spacer()
                    Text("\(subs.products.count)").foregroundColor(.secondary)
                }
                Button("强制刷新权益") {
                    Task { await subs.refresh() }
                }
            }
            #endif
        }
        .navigationTitle("订阅管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptions: subs)
        }
        .task { await subs.refresh() }
    }

    private var statusDetail: String {
        switch subs.status {
        case .free:
            return "免费版：基础步频器、2 种音色、1 个间歇模板、最近 7 天历史"
        case .trial:
            if let exp = subs.expiryDate {
                return "年付免费试用中，\(Formatters.day.string(from: exp)) 到期"
            }
            return "年付免费试用中"
        case .pro:
            if let exp = subs.expiryDate {
                return "Pro 会员，到期时间 \(Formatters.day.string(from: exp))"
            }
            return "Pro 会员"
        case .lifetime:
            return "终身会员，权益永久有效"
        }
    }

    @ViewBuilder
    private func upgradeRow(_ plan: SubscriptionPlan) -> some View {
        let product = subs.product(for: plan)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title).font(.subheadline.weight(.medium))
                Text(plan.subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(product?.displayPrice ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { showPaywall = true }
    }
}
