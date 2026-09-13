import SwiftUI

/// 免费版广告横幅占位（实际接入时替换为 Google AdMob / 国内广告 SDK 的 GADBannerView）。
/// Pro 用户不渲染该视图，实现“去除广告”。
struct AdBannerView: View {
    @ObservedObject private var subs = SubscriptionManager.shared
    var placement: String = "home"

    var body: some View {
        if subs.isUnlocked(.removeAds) {
            EmptyView()
        } else {
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("升级 Pro 去除广告").font(.subheadline.bold())
                        Text("同时解锁全部音色、无限计划与数据同步")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Pro")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange, in: Capsule()).foregroundColor(.white)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPaywall) {
                PaywallView(subscriptions: subs, feature: .removeAds)
            }
        }
    }

    @State private var showPaywall = false
}
