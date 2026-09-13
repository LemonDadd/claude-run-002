import Foundation
import SwiftUI
import Combine

/// 训练状态机
///
/// 状态流转：
/// idle → running ⇄ paused → finished
///                 （running 内推进 stageIndex：热身→快跑→…→冷身）
///
/// 职责：
/// - 驱动 AudioEngine（节拍 + 渐入）、CadenceEngine（实时步频）、LocationTracker（轨迹）
/// - 多阶段间歇：每阶段独立步频/时长/距离，切换时 语音 + 触觉 + 视觉 三重提示
/// - 训练中动态调整当前阶段步频：只改音频目标，不中断节拍与计时
/// - ±5 SPM 偏离：冷却 8s 节流的语音 + 视觉标记
/// - 聚合：时长/距离/配速/平均&最大步频/步数/卡路里，5s 落一条步频曲线点
@MainActor
final class TrainingSession: ObservableObject {

    enum State: Equatable {
        case idle, running, paused, finished
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var stageElapsed: TimeInterval = 0
    @Published private(set) var stageIndex = 0
    @Published private(set) var cadence = 0
    @Published private(set) var maxCadence = 0
    @Published private(set) var steps = 0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var plan: TrainingPlan
    @Published private(set) var stageOverrideCadence: [UUID: Int] = [:]
    @Published var deviationBanner: String?   // 视觉提示
    @Published var stageFlash: Bool = false

    let cadenceEngine = CadenceEngine()
    let audio = AudioEngine()
    let location = LocationTracker()

    var trainingType: TrainingType { plan.type }

    private var ticker: Timer?
    private var lastTickDate: Date?
    private var cadenceSum = 0
    private var cadenceCount = 0
    private var lastSeriesDate: Date?
    private(set) var series: [CadenceSample] = []
    private var splits: [Split] = []
    private var nextSplitKm = 1
    private var lastSplitElapsed: TimeInterval = 0
    private var splitCadenceSum = 0
    private var splitCadenceCount = 0
    private var deviationCooldown = Date.distantPast
    private var audioRampPerBeat: Int { 2 } // 每拍 ±2SPM 的渐入斜率
    private let haptics = HapticEngine()
    private var live: Any? // LiveActivityService（16.1 可用性）

    var stages: [Stage] { plan.stages }

    var currentStage: Stage? {
        stages.indices.contains(stageIndex) ? stages[stageIndex] : nil
    }

    /// 当前阶段实际目标（可被动态调整覆盖）
    var effectiveTargetCadence: Int {
        guard let stage = currentStage else { return 170 }
        return stageOverrideCadence[stage.id] ?? stage.targetCadence
    }

    var stageRemaining: TimeInterval? {
        guard let s = currentStage, s.duration > 0 else { return nil }
        return max(0, s.duration - stageElapsed)
    }

    var avgCadence: Int { cadenceCount > 0 ? Int(Double(cadenceSum) / Double(cadenceCount)) : 0 }
    var pace: TimeInterval { // sec/km
        distanceMeters > 50 ? elapsed / (distanceMeters / 1000) : 0
    }
    var calories: Double {
        // MET 估算：跑步 ~ (0.9 * 速度km/h)，kcal = MET * 体重kg * 时间h
        let speedKmh = elapsed > 0 ? (distanceMeters / 1000) / (elapsed / 3600) : 0
        let met = max(6.0, 0.9 * speedKmh)
        let weight = PersistenceStore.shared.profile.weightKg
        return met * weight * (elapsed / 3600)
    }

    init(plan: TrainingPlan = .freePlan) {
        self.plan = plan
        observeWidgetCommands()
    }

    deinit {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer)
    }

    // MARK: - 计划

    func configure(plan newPlan: TrainingPlan, startCadence: Int? = nil) {
        var p = newPlan
        if let startCadence, let i = p.stages.indices.first {
            p.stages[i].targetCadence = startCadence
        }
        self.plan = p
    }

    // MARK: - 状态转换

    func start() {
        guard state == .idle else { return }
        state = .running
        elapsed = 0; stageElapsed = 0
        stageIndex = 0
        maxCadence = 0; cadenceSum = 0; cadenceCount = 0
        series.removeAll(); splits.removeAll()
        nextSplitKm = 1; lastSplitElapsed = 0
        splitCadenceSum = 0; splitCadenceCount = 0
        deviationBanner = nil
        let target = effectiveTargetCadence
        let s = PersistenceStore.shared.settings
        audio.beatVolume = s.beatVolume
        audio.sound = BeatSound(rawValue: s.soundRaw) ?? .click
        audio.hapticsEnabled = s.hapticsEnabled
        audio.stereoFeetEnabled = s.stereoFeet
        audio.keepAliveWhenSilent = s.keepAliveSilent
        // 节拍渐入：若当前实时步频未知，从目标 -20 起渐入，更跟脚
        audio.start(atSPM: target,
                    rampFrom: cadenceEngine.cadence > 0 ? cadenceEngine.cadence : max(60, target - 20),
                    rampPerBeat: audioRampPerBeat)
        cadenceEngine.start()
        location.start()
        if #available(iOS 16.2, *) {
            let svc = LiveActivityService.shared
            live = svc
            svc.start(targetCadence: target, stageName: currentStage?.type.rawValue)
        }
        lastTickDate = Date()
        startTicker()
        speak("开始\(plan.name)，目标步频 \(target)")
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        stopTicker()
        cadenceEngine.stop()
        audio.stop()
        location.stop()
        publishLive()
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        cadenceEngine.start()
        location.start()
        audio.start(atSPM: effectiveTargetCadence,
                    rampFrom: cadenceEngine.cadence > 0 ? cadenceEngine.cadence : nil,
                    rampPerBeat: audioRampPerBeat)
        lastTickDate = Date()
        startTicker()
    }

    func stopAndSave() {
        guard state != .idle else { return }
        finish(speak: false)
        saveRecord()
    }

    func discardRun() {
        finish(speak: false)
        series.removeAll()
    }

    private func finish(speak: Bool) {
        state = .finished
        stopTicker()
        cadenceEngine.stop()
        audio.stop()
        location.stop()
        SpeechService.shared.stop()
        if speak { self.speak("训练结束，干得漂亮") }
        if #available(iOS 16.2, *) {
            (live as? LiveActivityService)?.end()
        }
        live = nil
    }

    // MARK: - 阶段控制（训练中动态调整，不中断）

    /// 动态调整当前阶段目标步频（±按钮/输入），节拍无缝过渡
    func adjustCurrentStageCadence(by delta: Int) {
        guard let stage = currentStage else { return }
        let new = min(AppConstants.cadenceRange.upperBound,
                      max(AppConstants.cadenceRange.lowerBound, effectiveTargetCadence + delta))
        stageOverrideCadence[stage.id] = new
        audio.ramp(to: new, perBeat: audioRampPerBeat)
        publishLive()
    }

    func setCurrentStageCadence(_ value: Int) {
        guard let stage = currentStage,
              AppConstants.cadenceRange.contains(value) else { return }
        stageOverrideCadence[stage.id] = value
        audio.ramp(to: value, perBeat: audioRampPerBeat)
        publishLive()
    }

    func jumpToStage(_ index: Int) {
        guard stages.indices.contains(index) else { return }
        stageIndex = index
        stageElapsed = 0
        announceStage()
    }

    private func advanceStageIfNeeded() {
        guard let stage = currentStage else { return }
        let timeDone = stage.duration > 0 && stageElapsed >= stage.duration
        let distanceDone = stage.distanceMeters > 0 && distanceMeters >= stage.distanceMeters
        guard timeDone || distanceDone else { return }

        if stageIndex + 1 < stages.count {
            stageIndex += 1
            stageElapsed = 0
            announceStage()
        } else {
            finish(speak: true)
            saveRecord()
        }
    }

    /// 三重提示：语音 + 触觉 + 视觉
    private func announceStage() {
        guard let stage = currentStage else { return }
        let target = effectiveTargetCadence
        let text: String
        switch stage.type {
        case .warmup:   text = "热身，步频 \(target)"
        case .fast:     text = "快跑，步频 \(target)"
        case .slow:     text = "慢跑，步频 \(target)"
        case .cooldown: text = "冷身，步频 \(target)"
        case .steady:   text = "下一阶段，步频 \(target)"
        }
        speak(text)
        haptics.notify()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { stageFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.stageFlash = false
        }
        audio.ramp(to: target, perBeat: audioRampPerBeat)
    }

    // MARK: - 主循环 1Hz

    private func startTicker() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // common：滑动地图/列表时计时不中断
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard state == .running else { return }
        let now = Date()
        if let last = lastTickDate { elapsed += now.timeIntervalSince(last) }
        lastTickDate = now
        stageElapsed += 1

        cadence = cadenceEngine.cadence
        maxCadence = max(maxCadence, cadence)
        if cadence > 0 {
            cadenceSum += cadence; cadenceCount += 1
            splitCadenceSum += cadence; splitCadenceCount += 1
        }
        steps = cadenceEngine.validatedSteps
        distanceMeters = location.distanceMeters

        // 5s 一个曲线点（曲线上 1h 约 720 点）
        if lastSeriesDate == nil || now.timeIntervalSince(lastSeriesDate!) >= 5 {
            series.append(CadenceSample(timestamp: now, spm: cadence))
            lastSeriesDate = now
        }

        recordSplits()
        checkDeviation()
        advanceStageIfNeeded()
        publishLive()
    }

    private func recordSplits() {
        while distanceMeters >= Double(nextSplitKm) * 1000 {
            let avg = splitCadenceCount > 0 ? Int(Double(splitCadenceSum) / Double(splitCadenceCount)) : 0
            splits.append(Split(kilometer: nextSplitKm,
                                duration: elapsed - lastSplitElapsed,
                                avgCadence: avg))
            lastSplitElapsed = elapsed
            nextSplitKm += 1
            splitCadenceSum = 0; splitCadenceCount = 0
        }
    }

    // MARK: - 偏离提醒（±5 SPM）

    private func checkDeviation() {
        guard cadence > 0 else { deviationBanner = nil; return }
        guard PersistenceStore.shared.settings.deviationAlerts else {
            deviationBanner = nil
            return
        }
        let diff = cadence - effectiveTargetCadence
        if abs(diff) >= AppConstants.deviationAlertThreshold {
            let msg = diff > 0 ? "步频偏快 \(diff)，放慢一点" : "步频偏慢 \(-diff)，加快一点"
            deviationBanner = msg
            if Date().timeIntervalSince(deviationCooldown) > 8 {
                deviationCooldown = Date()
                speak(diff > 0 ? "步频偏快" : "步频偏慢")
            }
        } else {
            deviationBanner = nil
        }
    }

    private func speak(_ text: String) {
        guard PersistenceStore.shared.settings.voiceAlerts else { return }
        SpeechService.shared.speak(text)
    }

    // MARK: - 保存

    private func saveRecord() {
        let record = RunSummary(
            userId: PersistenceStore.shared.profile.id,
            startDate: Date().addingTimeInterval(-elapsed),
            endDate: Date(),
            duration: elapsed,
            distanceMeters: distanceMeters,
            avgCadence: avgCadence,
            maxCadence: maxCadence,
            calories: calories,
            steps: steps,
            trainingType: plan.type,
            planId: plan.stages.count > 1 ? plan.id : nil,
            track: location.track,
            cadenceSeries: series,
            splits: splits)
        PersistenceStore.shared.saveRun(record)
        let subs = SubscriptionManager.shared
        if PersistenceStore.shared.settings.healthSync, subs.isUnlocked(.healthSync) {
            HealthService.shared.writeRun(record)
        }
        NotificationCenter.default.post(name: .runDidFinish, object: record)
    }

    // MARK: - Live Activity / Widget 命令

    private func publishLive() {
        let laState = LiveActivityState(
            status: state == .paused ? .paused : (state == .running ? .running : .idle),
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            cadence: cadence,
            targetCadence: effectiveTargetCadence,
            stageName: currentStage?.type.rawValue,
            stageRemaining: stageRemaining)
        if #available(iOS 16.2, *) {
            (live as? LiveActivityService)?.update(laState)
        } else {
            RunCommands.publish(state: laState)
        }
    }

    private func observeWidgetCommands() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, _, _, _, _ in
            guard let cmd = RunCommands.consume() else { return }
            // TrainingSession 是 @MainActor；通过协调器转发命令
            Task { @MainActor in
                guard let session = RunCoordinator.shared.session else { return }
                switch cmd {
                case .pause: if session.state == .running { session.pause() }
                case .resume: if session.state == .paused { session.resume() }
                case .stop: session.stopAndSave()
                case .bumpUp: session.adjustCurrentStageCadence(by: 5)
                case .bumpDown: session.adjustCurrentStageCadence(by: -5)
                }
            }
        }, RunCommands.notificationName as CFString, nil, .deliverImmediately)
    }
}

// MARK: - 计划模板

extension TrainingPlan {
    static let freePlan = TrainingPlan(name: "自由跑", type: .free,
                                       stages: [Stage(type: .steady, targetCadence: 170, duration: 0)])

    static let fixedPlan = TrainingPlan(name: "定频跑 170", type: .fixed,
                                        stages: [Stage(type: .steady, targetCadence: 170, duration: 0)])

    /// 示例间歇：5'热身 → 6×(2'快跑180 / 2'慢跑150) → 5'冷身
    static let intervalTemplate: TrainingPlan = {
        var stages: [Stage] = [Stage(type: .warmup, targetCadence: 150, duration: 300)]
        for _ in 0..<6 {
            stages.append(Stage(type: .fast, targetCadence: 180, duration: 120))
            stages.append(Stage(type: .slow, targetCadence: 150, duration: 120))
        }
        stages.append(Stage(type: .cooldown, targetCadence: 140, duration: 300))
        return TrainingPlan(name: "间歇 6 组", type: .interval, stages: stages)
    }()
}
