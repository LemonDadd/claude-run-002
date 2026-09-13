import SwiftUI

/// 门控修饰器：未解锁时在内容上覆盖锁标识 / 点击弹出付费墙
struct ProLockedModifier: ViewModifier {
    let feature: ProFeature
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        if subs.isUnlocked(feature) {
            content
        } else {
            content
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
                .onTapGesture { showPaywall = true }
                .sheet(isPresented: $showPaywall) {
                    PaywallView(subscriptions: subs, feature: feature)
                }
        }
    }
}

extension View {
    /// 未解锁 Pro 功能时，视图显示锁标并点击弹出付费墙
    func proLocked(_ feature: ProFeature) -> some View {
        modifier(ProLockedModifier(feature: feature))
    }
}

/// 门控 Toggle：未解锁时显示锁且不可开启，点击弹付费墙
struct ProToggleRow: View {
    let feature: ProFeature
    let title: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)?
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showPaywall = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if subs.isUnlocked(feature) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .onChange(of: isOn) { onChange?($0) }
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                Toggle("", isOn: .constant(false))
                    .labelsHidden()
                    .disabled(true)
                    .onTapGesture { showPaywall = true }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !subs.isUnlocked(feature) { showPaywall = true }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptions: subs, feature: feature)
        }
    }
}

/// 门控按钮：未解锁时点击弹付费墙，解锁后执行真实动作
struct ProButton<Label: View>: View {
    let feature: ProFeature
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showPaywall = false

    init(feature: ProFeature, action: @escaping () -> Void,
         @ViewBuilder label: @escaping () -> Label) {
        self.feature = feature
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            if subs.isUnlocked(feature) { action() } else { showPaywall = true }
        } label: {
            label()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptions: subs, feature: feature)
        }
    }
}
