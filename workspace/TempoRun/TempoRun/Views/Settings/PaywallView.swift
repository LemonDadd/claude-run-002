import SwiftUI
import StoreKit

/// Pro 付费墙
struct PaywallView: View {
    @ObservedObject var subscriptions: SubscriptionManager
    var feature: ProFeature?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var showError = false

    private let features: [ProFeature] = [
        .sound(.woodblock), .unlimitedPlans, .fullHistory,
        .healthSync, .stravaSync, .cadenceDistribution, .removeAds
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if let feature {
                        lockedFeatureCard(feature)
                    }
                    plans
                    featureList
                    purchaseButton
                    restoreRow
                    legalText
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(colors: [Color.accentColor.opacity(0.10), Color(.systemGroupedBackground)],
                               startPoint: .top, endPoint: .center)
                .ignoresSafeArea())
            .navigationTitle("TempoRun Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("以后再说") { dismiss() }
                }
            }
            .alert("提示", isPresented: $showError) {
                Button("好", role: .cancel) {}
            } message: {
                Text(subscriptions.purchaseError?.alertMessage ?? "购买失败，请稍后再试")
            }
            .onChange(of: subscriptions.purchaseError) { newValue in
                showError = newValue != nil && newValue != .userCancelled
            }
            .task {
                await subscriptions.loadProducts()
                if subscriptions.products.isEmpty == false { selectedPlan = .yearly }
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 46))
                .foregroundStyle(.linearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom))
                .padding(.top, 8)
            Text("升级 TempoRun Pro")
                .font(.title.bold())
            Text("全部音色 · 无限计划 · 全平台同步 · 无广告")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func lockedFeatureCard(_ f: ProFeature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(.subheadline.bold())
                Text(f.valueDescription).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 方案选择

    private var plans: some View {
        VStack(spacing: 12) {
            ForEach(SubscriptionPlan.allCases) { plan in
                planRow(plan)
            }
        }
    }

    private func planRow(_ plan: SubscriptionPlan) -> some View {
        let selected = selectedPlan == plan
        let product = subscriptions.product(for: plan)
        return Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(.headline)
                        if plan == .yearly {
                            Text("推荐")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.orange, in: Capsule())
                                .foregroundColor(.white)
                        }
                    }
                    Text(plan.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product?.displayPrice ?? pricePlaceholder(plan))
                        .font(.headline.monospacedDigit())
                    if plan == .yearly {
                        Text(equivalentMonthlyPrice(product))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            )
        }
        .buttonStyle(.plain)
    }

    private func pricePlaceholder(_ plan: SubscriptionPlan) -> String {
        switch plan {
        case .monthly: return "¥28/月"
        case .yearly: return "¥168/年"
        case .lifetime: return "¥388"
        }
    }

    /// 年付折合月均价格展示（基于真实 Product 价格计算）
    private func equivalentMonthlyPrice(_ product: Product?) -> String {
        guard let price = product?.price else { return "约 ¥14/月" }
        let monthly = (price as NSDecimalNumber).doubleValue / 12
        return String(format: "约 ¥%.0f/月", monthly)
    }

    // MARK: 权益列表

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pro 包含").font(.headline)
            ForEach(features, id: \.title) { f in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.title).font(.subheadline.weight(.medium))
                        Text(f.valueDescription).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 购买

    private var purchaseButton: some View {
        Button {
            Task {
                let result = await subscriptions.purchase(selectedPlan)
                if result == .success {
                    await subscriptions.refresh()
                    dismiss()
                }
            }
        } label: {
            HStack {
                if subscriptions.isPurchasing {
                    ProgressView().tint(.white)
                }
                Text(buttonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
            .foregroundColor(.white)
        }
        .disabled(subscriptions.isPurchasing || subscriptions.products.isEmpty)
    }

    private var buttonTitle: String {
        switch selectedPlan {
        case .monthly:  return "订阅月付方案"
        case .yearly:   return "开始 7 天免费试用"
        case .lifetime: return "终身买断"
        }
    }

    private var restoreRow: some View {
        HStack {
            Button("恢复购买") {
                Task { await subscriptions.restore() }
            }
            .font(.subheadline)
            if subscriptions.didRestore {
                Text("已检查可恢复的购买").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var legalText: some View {
        Text("年付方案前 7 天免费，试用结束后自动按年续费，可随时在系统设置中取消；月付按月自动续期；终身买断一次付费永久使用。付款将通过 App Store 账户收取，续费在到期前 24 小时内扣款。")
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }
}
