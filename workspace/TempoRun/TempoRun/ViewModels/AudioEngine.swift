import AVFoundation
import Foundation
import Combine
import MediaPlayer

/// 音频引擎：节拍混音与后台播放
///
/// 关键设计：
/// - AVAudioSession: .playback + [.mixWithOthers]，与 Apple Music / Spotify / QQ音乐共存
/// - 节拍走独立 mixer，节拍音量与第三方音乐互不影响
/// - DispatchSourceTimer（leeway 2ms）+ 0.15s 提前量调度，调度抖动远低于 50ms
/// - 预分配 player 节点池轮转，避免运行时动态挂拆节点
/// - 后台保活：audio background mode 由 .playback 会话持有；静音时挂静音循环播放器
/// - 左右脚：声像 + 音高 + 触觉强度三维区分
/// - 节拍渐入：每拍按 rampPerBeat 平滑趋近目标
/// - 中断（来电/闹钟/Siri）：interruptionNotification 结束后恢复并重置节拍基线
final class AudioEngine: ObservableObject {

    @Published var isPlaying = false
    @Published var beatVolume: Float = 0.9 {
        didSet { poolMixer?.outputVolume = beatVolume }
    }
    @Published var sound: BeatSound = .click { didSet { rebuildBuffers() } }
    @Published var hapticsEnabled = true
    @Published var stereoFeetEnabled = true
    @Published var keepAliveWhenSilent = true
    @Published var isInterrupted = false
    /// 当前实际播放步频（渐入过程中 != targetSPM）
    @Published private(set) var currentSPMPublished = 0

    var targetSPM = 170
    /// 每拍向目标靠近的 SPM 数（0 = 立即到位，不渐入）
    var rampPerBeat = 0

    private var currentSPM = 0

    private let engine = AVAudioEngine()
    private var poolMixer: AVAudioMixerNode?
    private var playerPool: [AVAudioPlayerNode] = []
    private var poolIndex = 0
    private let poolCount = 6
    private var buffers: SoundFactory.Buffer?
    private let haptics = HapticEngine()

    private var scheduler: DispatchSourceTimer?
    private var schedulerSuspended = false
    private var nextBeatTime: TimeInterval = 0
    private var isRightFoot = false

    private var silencePlayer: AVAudioPlayerNode?
    private var observers: [NSObjectProtocol] = []

    // MARK: - 生命周期

    init() {
        setupSession()
        setupEngine()
        rebuildBuffers()
        observeInterruptions()
        observeRouteChange()
        setupRemoteCommands()
    }

    deinit {
        scheduler?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .default,
                                    options: [.mixWithOthers, .allowBluetoothA2DP])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setPreferredSampleRate(SoundFactory.sampleRate)
            try session.setActive(true, options: [])
        } catch {
            #if DEBUG
            print("[AudioEngine] session failed: \(error)")
            #endif
        }
    }

    private func setupEngine() {
        let mixerNode = AVAudioMixerNode()
        engine.attach(mixerNode)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: nil)
        mixerNode.outputVolume = beatVolume
        poolMixer = mixerNode

        // 预分配播放节点池（立体声标准格式，与合成 buffer 一致）
        let format = AVAudioFormat(standardFormatWithSampleRate: SoundFactory.sampleRate, channels: 2)!
        for _ in 0..<poolCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixerNode, format: format)
            playerPool.append(node)
        }

        // 1s 静音循环 buffer，后台保活（音量 0，功耗极低）
        if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(SoundFactory.sampleRate)) {
            buf.frameLength = AVAudioFrameCount(SoundFactory.sampleRate)
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            node.volume = 0
            node.scheduleBuffer(buf, at: nil, options: [.loops])
            silencePlayer = node
        }

        engine.prepare()
        try? engine.start()
    }

    private func rebuildBuffers() {
        buffers = SoundFactory.makeBuffers(sound)
    }

    // MARK: - 播放控制

    func start(atSPM spm: Int, rampFrom: Int? = nil, rampPerBeat rate: Int = 0) {
        targetSPM = spm
        rampPerBeat = max(0, rate)
        currentSPM = rampFrom ?? spm
        currentSPMPublished = currentSPM
        isRightFoot = false

        setupSession()
        if !engine.isRunning { try? engine.start() }
        haptics.start()
        silencePlayer?.play()
        playerPool.forEach { if !$0.isPlaying { $0.play() } }

        nextBeatTime = engineTime() + 0.06
        isPlaying = true
        isInterrupted = false
        startScheduler()
    }

    func stop() {
        isPlaying = false
        if let t = scheduler { t.cancel(); scheduler = nil }
        schedulerSuspended = false
        playerPool.forEach { $0.stop() }
        silencePlayer?.stop()
        haptics.stop()
        currentSPM = 0
        currentSPMPublished = 0
    }

    /// 训练中动态改目标步频：不中断播放
    func updateTarget(_ spm: Int) {
        targetSPM = spm
        if rampPerBeat == 0 {
            currentSPM = spm
            currentSPMPublished = spm
        }
    }

    /// 触发一段新渐入（阶段切换 / 自由跑中调整目标）
    func ramp(to spm: Int, perBeat rate: Int) {
        targetSPM = spm
        rampPerBeat = max(0, rate)
        if rate == 0 {
            currentSPM = spm
            currentSPMPublished = spm
        }
    }

    // MARK: - 调度器（节拍 < 50ms 延迟的核心）

    private func startScheduler() {
        scheduler?.cancel() // resume 重启时先回收旧 timer
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.temporun.scheduler",
                                                                    qos: .userInteractive))
        // 50Hz 检查 + 2ms leeway；节拍仅提前 0.15s 入队，杜绝漂移与突发
        t.schedule(deadline: .now() + .milliseconds(15),
                   repeating: .milliseconds(20), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        scheduler = t
        schedulerSuspended = false
    }

    private func tick() {
        guard isPlaying, !schedulerSuspended else { return }
        let now = engineTime()
        let horizon = now + AppConstants.schedulerAhead

        while nextBeatTime <= horizon {
            scheduleBeat(at: nextBeatTime)
            let interval = 60.0 / Double(max(1, currentSPM))
            nextBeatTime += interval
        }
    }

    private func scheduleBeat(at hostSeconds: TimeInterval) {
        guard let buffers else { return }
        poolIndex = (poolIndex + 1) % poolCount
        let node = playerPool[poolIndex]
        // isRightFoot 初始 false：第 1 拍为左脚（弱），右脚为强拍，符合 1&2& 数拍习惯
        let isRight = isRightFoot
        let buffer = (isRight || !stereoFeetEnabled) ? buffers.right : buffers.left
        node.scheduleBuffer(buffer,
                            at: AVAudioTime(hostTime: Self.hostTime(forSeconds: hostSeconds)),
                            options: [])

        if hapticsEnabled {
            // 触觉相对音频发声提前 0.1s 下发（系统触觉管线有约 30–80ms 延迟），实现听/感同步
            let rel = max(0, hostSeconds - engineTime() - AppConstants.hapticAhead)
            haptics.playFoot(isRight: isRight, relativeTime: rel)
        }

        isRightFoot.toggle()

        if rampPerBeat > 0, currentSPM != targetSPM {
            let dir = targetSPM > currentSPM ? 1 : -1
            currentSPM += dir * rampPerBeat
            if (dir > 0 && currentSPM >= targetSPM) || (dir < 0 && currentSPM <= targetSPM) {
                currentSPM = targetSPM
            }
            Task { @MainActor in self.currentSPMPublished = self.currentSPM }
        }
    }

    // MARK: - 时钟换算
    //
    // 统一使用 hostTime 时钟域（mach_absolute_time）：
    // CACurrentMediaTime() 返回的就是 hostTime 换算后的秒；
    // 调度时再把秒转回 hostTime 构造 AVAudioTime。
    // 注意：playerTime(forNodeTime:) 是 AVAudioPlayerNode 的 API，
    // 不能在 outputNode 上调用（那是旧代码的编译错误）。

    private func engineTime() -> TimeInterval {
        // 引擎在跑时以 lastRenderTime 的 hostTime 为准（更贴近音频硬件时钟），
        // 否则退化为 CACurrentMediaTime()
        if engine.isRunning, let nodeTime = engine.outputNode.lastRenderTime {
            let hostTime = nodeTime.hostTime
            var tb = mach_timebase_info_data_t()
            mach_timebase_info(&tb)
            return Double(hostTime) * Double(tb.numer)
                / Double(tb.denom) / 1_000_000_000.0
        }
        return CACurrentMediaTime()
    }

    private static func hostTime(forSeconds s: TimeInterval) -> UInt64 {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let nanos = UInt64(s * 1_000_000_000)
        return nanos * UInt64(tb.denom) / UInt64(tb.numer)
    }

    // MARK: - 中断（来电 / 通知 / 闹钟 / Siri）

    private func observeInterruptions() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                switch type {
                case .began:
                    self.isInterrupted = true
                    self.suspendScheduler()
                    self.silencePlayer?.pause()
                case .ended:
                    let opts = AVAudioSession.InterruptionOptions(
                        rawValue: (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0)
                    // 被其他 App 短暂打断（.mixWithOthers 场景通常不会 .began）；
                    // 有 shouldResume 才重新激活会话，否则直接恢复内部时钟
                    if opts.contains(.shouldResume) {
                        try? AVAudioSession.sharedInstance().setActive(true, options: [])
                    }
                    if !self.engine.isRunning { try? self.engine.start() }
                    self.silencePlayer?.play()
                    self.resumeSchedulerResetBaseline()
                    self.isInterrupted = false
                @unknown default: break
                }
            })
    }

    private func observeRouteChange() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
                switch reason {
                case .oldDeviceUnavailable:
                    self.stop() // 拔耳机：按 HIG 暂停，避免突然公放
                case .newDeviceAvailable, .categoryChange, .override:
                    if self.isPlaying, !self.engine.isRunning { try? self.engine.start() }
                default: break
                }
            })
    }

    private func suspendScheduler() {
        guard !schedulerSuspended else { return }
        scheduler?.suspend()
        schedulerSuspended = true
    }

    // MARK: - 锁屏 / 耳机线控

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            RunCommands.send(.resume)
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            RunCommands.send(.pause)
            return .success
        }
        center.skipForwardCommand.addTarget { _ in
            RunCommands.send(.bumpUp); return .success
        }
        center.skipBackwardCommand.addTarget { _ in
            RunCommands.send(.bumpDown); return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 5)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 5)]

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "TempoRun 节拍器",
            MPMediaItemPropertyArtist: "步频引导",
            MPNowPlayingInfoPropertyIsLiveStream: true
        ]
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func resumeSchedulerResetBaseline() {
        // 无论是否被挂起都重置基线，防止中断期间 nextBeatTime 落在过去导致节拍爆发
        if schedulerSuspended { scheduler?.resume(); schedulerSuspended = false }
        nextBeatTime = engineTime() + 0.08
    }
}
