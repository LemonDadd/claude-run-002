import AVFoundation

/// 语音播报（阶段切换、步频偏离提醒）。
/// 与节拍引擎同处 .playback 会话：.mixWithOthers 下 duckOthers 让音乐短暂压低。
final class SpeechService {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        // 打断上一条未说完的提示（如连续阶段切换）
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.volume = 1.0
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}
