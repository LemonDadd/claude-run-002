import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @ObservedObject private var store = PersistenceStore.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var showDeleteConfirm = false
    @State private var showPaywall = false
    @State private var beatSound: BeatSound = {
        if let raw = UserDefaults.standard.string(forKey: "beatSound"),
           let s = BeatSound(rawValue: raw) { return s }
        return .click
    }()
    @State private var beatVolume: Float = Float(UserDefaults.standard.double(forKey: "beatVolume") == 0
        ? 0.9 : UserDefaults.standard.double(forKey: "beatVolume"))

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 订阅
                Section {
                    NavigationLink {
                        SubscriptionSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: subs.isPro ? "crown.fill" : "crown")
                                .font(.title3)
                                .foregroundColor(.orange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subs.isPro ? subs.status.displayName : "升级 TempoRun Pro")
                                    .font(.headline)
                                Text(subs.isPro ? subscriptionDetail : "全部音色 · 无限计划 · 数据同步")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if !subs.isPro {
                                Text("Pro")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.orange, in: Capsule())
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // MARK: 账户
                Section("账户") {
                    SignInWithAppleButtonRow()
                    Button {
                        // 手机号登录 sheet 在 PhoneLoginView 中
                        showPhoneLogin = true
                    } label: {
                        Label("手机号登录", systemImage: "phone.fill")
                    }
                    if auth.isSignedIn {
                        Button("退出登录", role: .destructive) { auth.signOut() }
                    }
                }

                // MARK: 音频/触觉
                Section("节拍与提示") {
                    Picker("节拍音色", selection: $beatSound) {
                        ForEach(BeatSound.allCases) { sound in
                            let locked = !subs.isUnlocked(.sound(sound))
                            Text(locked ? "\(sound.rawValue) 🔒" : sound.rawValue).tag(sound)
                        }
                    }
                    HStack {
                        Image(systemName: "speaker.wave.1.fill")
                        Slider(value: Binding(get: { Double(beatVolume) },
                                              set: { beatVolume = Float($0); saveAudio() }), in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Text("节拍音量与第三方音乐 App 相互独立；木鱼/电子/人声为 Pro 音色")
                        .font(.caption).foregroundColor(.secondary)
                    Toggle("语音播报", isOn: settingsBinding(\.voiceAlerts))
                    Toggle("触觉振动（左右脚强弱区分）", isOn: settingsBinding(\.hapticsEnabled))
                    Toggle("左右脚立体声交替", isOn: settingsBinding(\.stereoFeet))
                    Toggle("步频偏离 ±5 提醒", isOn: settingsBinding(\.deviationAlerts))
                    Toggle("静音时后台保活（极低功耗）", isOn: settingsBinding(\.keepAliveSilent))
                }

                // MARK: 数据同步（Pro）
                Section {
                    ProToggleRow(feature: .healthSync,
                                 title: "自动同步到 HealthKit",
                                 isOn: settingsBinding(\.healthSync)) { on in
                        if on { HealthService.shared.requestAuthorization() }
                    }
                    ProButton(feature: .stravaSync, action: {
                        if StravaService.shared.isConnected {
                            StravaService.shared.disconnect()
                        } else if let url = StravaService.shared.authorizeURL {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Label("Strava", systemImage: "figure.outdoor.cycle")
                            Spacer()
                            Text(StravaService.shared.isConnected ? "已连接（解绑）" : "去连接")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("数据与同步")
                } footer: {
                    Text("HealthKit 与 Strava 同步为 Pro 功能。")
                }

                // MARK: 个人资料
                Section("个人资料（用于卡路里估算）") {
                    HStack {
                        Text("昵称"); Spacer()
                        TextField("昵称", text: Binding(get: { store.profile.nickname },
                                                       set: { var p = store.profile; p.nickname = $0; store.saveProfile(p) }))
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("性别", selection: Binding(get: { store.profile.gender },
                                                      set: { gender in var p = store.profile; p.gender = gender; store.saveProfile(p) })) {
                        ForEach(Gender.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    numberField("年龄", value: Binding(get: { store.profile.age ?? 0 },
                                                       set: { var p = store.profile; p.age = $0; store.saveProfile(p) }))
                    numberField("体重 kg", value: Binding(get: { Int(store.profile.weightKg) },
                                                          set: { var p = store.profile; p.weightKg = Double($0); store.saveProfile(p) }))
                    numberField("身高 cm", value: Binding(get: { Int(store.profile.heightCm) },
                                                          set: { var p = store.profile; p.heightCm = Double($0); store.saveProfile(p) }))
                }

                // MARK: 外观与无障碍
                Section("外观与无障碍") {
                    Picker("外观", selection: Binding(get: { store.settings.colorSchemeRaw },
                                                      set: { raw in var s = store.settings; s.colorSchemeRaw = raw; store.saveSettings(s) })) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    Label("支持动态字体与 VoiceOver", systemImage: "accessibility")
                        .font(.subheadline).foregroundColor(.secondary)
                }

                // MARK: 隐私
                Section("隐私") {
                    NavigationLink("隐私政策（GDPR / 个人信息保护法）") {
                        PrivacyPolicyView()
                    }
                    Label("位置数据仅本地加密存储，可一键删除", systemImage: "lock.shield.fill")
                        .font(.subheadline).foregroundColor(.secondary)
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除我的所有数据", systemImage: "trash.fill")
                    }
                }

                Section {
                    Text("TempoRun v1.0.0 · iOS 16+\nApple Watch 独立 App 将于二期上线（watchOS + WorkoutKit）")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("我的")
            .alert("确认删除所有数据？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("全部删除", role: .destructive) {
                    store.deleteAll()
                }
            } message: {
                Text("将永久删除本机全部跑步记录、计划与个人资料，且无法恢复。")
            }
            .sheet(isPresented: $showPhoneLogin) {
                PhoneLoginView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(subscriptions: subs)
            }
        }
    }

    @State private var showPhoneLogin = false

    private var subscriptionDetail: String {
        switch subs.status {
        case .pro, .trial:
            if let exp = subs.expiryDate {
                return "\(subs.status == .trial ? "试用中" : "已订阅") · \(Formatters.day.string(from: exp)) 到期"
            }
            return "Pro 会员"
        case .lifetime:
            return "终身会员"
        case .free:
            return ""
        }
    }

    private func settingsBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { value in
                    var s = store.settings
                    s[keyPath: keyPath] = value
                    store.saveSettings(s)
                })
    }

    private func saveAudio() {
        var s = store.settings
        s.beatVolume = beatVolume
        s.soundRaw = beatSound.rawValue
        store.saveSettings(s)
        UserDefaults.standard.set(Double(beatVolume), forKey: "beatVolume")
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title); Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
        }
    }
}

/// Sign in with Apple 按钮桥接
private struct SignInWithAppleButtonRow: View {
    var body: some View {
        Button {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.windows.first?.rootViewController else { return }
            AuthService.shared.signInWithApple(presentation: ApplePresentationProvider(anchor: root.view.window))
        } label: {
            Label("通过 Apple 登录", systemImage: "applelogo")
        }
    }
}

private final class ApplePresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    let anchor: ASPresentationAnchor?
    init(anchor: ASPresentationAnchor?) { self.anchor = anchor }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}

private struct PhoneLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("手机号") {
                    TextField("+86 手机号", text: $phone).keyboardType(.phonePad)
                    Button(codeSent ? "重新发送验证码" : "发送验证码") {
                        loading = true
                        Task {
                            try? await AuthService.shared.sendSMSCode(phone: phone)
                            loading = false
                            codeSent = true
                        }
                    }.disabled(phone.count < 6 || loading)
                }
                if codeSent {
                    Section("验证码（演示环境为 123456）") {
                        TextField("6 位验证码", text: $code).keyboardType(.numberPad)
                        Button("登录") {
                            loading = true
                            Task {
                                let ok = await AuthService.shared.verifySMSCode(phone: phone, code: code)
                                loading = false
                                if ok { dismiss() }
                            }
                        }.disabled(code.count != 6)
                    }
                }
            }
            .navigationTitle("手机号登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text(privacyText)
                .font(.body)
                .padding()
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
    private let privacyText = """
    TempoRun 尊重并保护你的隐私：

    1. 位置、轨迹与运动数据仅存储在你的设备本地（SwiftData / 加密文件），不会上传到我们的服务器；
    2. 仅在你主动开启时向 HealthKit / Strava 写入跑步数据，可随时关闭授权；
    3. 不收集广告标识符，不做行为画像，不做数据交易；
    4. 你可在「我的 - 删除我的所有数据」中一键擦除全部数据；
    5. 依据 GDPR 与《中华人民共和国个人信息保护法》，你随时拥有访问、更正、删除与携带的权利。

    联系邮箱：privacy@temporun.app
    """
}
