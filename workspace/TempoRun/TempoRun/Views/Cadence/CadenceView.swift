import SwiftUI

/// 步频器页：节拍试听 + 目标步频调节（滑块 / 加减 / 数字输入，步进 1）
struct CadenceView: View {
    @State private var target: Int = {
        let v = UserDefaults.standard.integer(forKey: "targetCadence")
        return v == 0 ? AppConstants.defaultTargetCadence : v
    }()
    @State private var showNumberPad = false
    @State private var sound: BeatSound = {
        if let raw = UserDefaults.standard.string(forKey: "beatSound"),
           let s = BeatSound(rawValue: raw) { return s }
        return .click
    }()
    @State private var rampEnabled = true
    @StateObject private var preview = CadencePreviewModel()
    @ObservedObject private var subs = SubscriptionManager.shared
    @State private var lockedSound: BeatSound?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 试听按钮
                    Button {
                        preview.toggle(target: target, sound: sound)
                        save()
                    } label: {
                        Label(preview.isPlaying ? "停止节拍" : "试听节拍",
                              systemImage: preview.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(preview.isPlaying ? Color.red : Color.accentColor,
                                        in: RoundedRectangle(cornerRadius: DesignSystem.radius))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    CadenceStepperControl(value: $target, range: AppConstants.cadenceRange) { v in
                        preview.updateTarget(v)
                        save()
                    }

                    // 数字输入（第三种调节方式）
                    Button {
                        showNumberPad = true
                    } label: {
                        Label("输入数字", systemImage: "keyboard")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    // 音色
                    VStack(alignment: .leading, spacing: 12) {
                        Text("节拍音色").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                            ForEach(BeatSound.allCases) { s in
                                let locked = !subs.isUnlocked(.sound(s))
                                Button {
                                    if locked {
                                        lockedSound = s
                                    } else {
                                        sound = s
                                        preview.setSound(s)
                                        save()
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        if locked {
                                            Image(systemName: "lock.fill").font(.caption2)
                                        }
                                        Text(s.rawValue)
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                                    .background(sound == s && !locked
                                                ? Color.accentColor : Color(.tertiarySystemFill),
                                                in: Capsule())
                                    .foregroundColor(sound == s && !locked ? .white : .primary)
                                    .opacity(locked ? 0.7 : 1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .card()

                    Toggle("左右脚交替提示（音色/声像/振动）", isOn: $preview.stereoFeet)
                        .card()
                    Toggle("节拍渐入（从当前步频平滑过渡）", isOn: $rampEnabled)
                        .card()

                    Text("节拍与第三方音乐可同时播放，音量相互独立")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("步频器")
            .sheet(isPresented: $showNumberPad) {
                CadenceNumberInput(initial: target) { value in
                    target = value
                    preview.updateTarget(value)
                    save()
                    showNumberPad = false
                }
                .presentationDetents([.height(320)])
            }
            .sheet(item: $lockedSound) { s in
                PaywallView(subscriptions: subs, feature: .sound(s))
            }
            .onDisappear { preview.stopIfOnlyPreview() }
            .task {
                // 免费用户若历史选择了 Pro 音色，回退到滴答，保证核心步频器完整可用
                if !subs.isUnlocked(.sound(sound)) {
                    sound = .click
                    save()
                }
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(target, forKey: "targetCadence")
        UserDefaults.standard.set(sound.rawValue, forKey: "beatSound")
    }
}

/// 数字输入弹窗（第三种调节方式）
private struct CadenceNumberInput: View {
    @State var text: String
    let initial: Int
    let confirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initial: Int, confirm: @escaping (Int) -> Void) {
        self.initial = initial
        self._text = State(initialValue: "\(initial)")
        self.confirm = confirm
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("输入目标步频").font(.headline)
            TextField("60–240", text: $text)
                .keyboardType(.numberPad)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

            HStack {
                Button("取消") { dismiss() }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                Button("确定") {
                    if let v = Int(text), AppConstants.cadenceRange.contains(v) { confirm(v) }
                }
                .disabled(Int(text).map { !AppConstants.cadenceRange.contains($0) } ?? true)
                .frame(maxWidth: .infinity).padding()
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.white)
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 32)
    }
}

/// 试听用的轻量 AudioEngine 包装
@MainActor
final class CadencePreviewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var stereoFeet = true {
        didSet { audio?.stereoFeetEnabled = stereoFeet }
    }
    var rampPerBeat = 2
    private var audio: AudioEngine?

    func toggle(target: Int, sound: BeatSound) {
        if isPlaying {
            audio?.stop()
            audio = nil
            isPlaying = false
        } else {
            let engine = AudioEngine()
            engine.sound = sound
            engine.stereoFeetEnabled = stereoFeet
            engine.rampPerBeat = rampPerBeat
            engine.start(atSPM: target,
                         rampFrom: rampPerBeat > 0 ? max(60, target - 20) : target,
                         rampPerBeat: rampPerBeat)
            audio = engine
            isPlaying = true
        }
    }
    func updateTarget(_ v: Int) { audio?.updateTarget(v) }
    func setSound(_ s: BeatSound) {
        guard let audio else { return }
        let spm = audio.targetSPM
        audio.sound = s
        if isPlaying { audio.stop(); audio.start(atSPM: spm) }
    }
    func stopIfOnlyPreview() {
        audio?.stop()
        audio = nil
        isPlaying = false
    }
}
