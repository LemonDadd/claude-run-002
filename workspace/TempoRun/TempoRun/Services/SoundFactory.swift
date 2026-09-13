import AVFoundation

/// 节拍音色。所有音色由代码程序化合成（无需打包音频文件，控制包体积），
/// 每种音色生成 左/右 两版（音高+声像区分左右脚）。
enum BeatSound: String, CaseIterable, Identifiable {
    case click    = "滴答"
    case drum     = "鼓点"
    case woodblock = "木鱼"
    case electronic = "电子"
    case voice    = "人声"
    var id: String { rawValue }

    /// 右脚（强拍）基频；左脚使用 1.06 倍频 + 低强度，形成左右脚可辨提示
    fileprivate var baseFrequency: Double {
        switch self {
        case .click:      return 2500
        case .drum:       return 90
        case .woodblock:  return 880
        case .electronic: return 1320
        case .voice:      return 520
        }
    }
}

enum SoundFactory {
    static let sampleRate = 44_100.0
    static let frameCount = 8_820 // 0.2s，覆盖木鱼/人声余韵

    struct Buffer {
        let left: AVAudioPCMBuffer
        let right: AVAudioPCMBuffer
    }

    private static func makeBuffer() -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
    }

    /// 合成左右脚两个立体声缓冲
    static func makeBuffers(_ sound: BeatSound) -> Buffer? {
        guard let left = render(sound, foot: .left),
              let right = render(sound, foot: .right) else { return nil }
        return Buffer(left: left, right: right)
    }

    enum Foot { case left, right }

    static func render(_ sound: BeatSound, foot: Foot) -> AVAudioPCMBuffer? {
        guard let buffer = makeBuffer() else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let f0 = sound.baseFrequency * (foot == .left ? 1.06 : 1.0)

        guard let ch0 = buffer.floatChannelData?[0],
              let ch1 = buffer.floatChannelData?[1] else { return nil }

        // 声像：右脚偏右、左脚偏左（左右音色 + 空间方位双重区分）
        let (panL, panR) = foot == .right ? (0.35, 1.0) : (1.0, 0.35)

        for n in 0..<frameCount {
            let t = Double(n) / sampleRate
            let s = sample(sound, t: t, f0: f0)
            ch0[n] = Float(s * panL)
            ch1[n] = Float(s * panR)
        }
        return buffer
    }

    private static func sample(_ sound: BeatSound, t: Double, f0: Double) -> Double {
        switch sound {
        case .click:
            // 极短高频脉冲 + 快速指数衰减：听感尖锐，定位清晰，延迟感最低
            let dur = 0.035
            guard t < dur else { return 0 }
            let env = exp(-t * 140)
            return 0.9 * env * (sin(2 * .pi * f0 * t) + 0.3 * sin(2 * .pi * f0 * 2 * t))

        case .drum:
            // 低频正弦下扫 + 噪声瞬态，模拟底鼓
            let dur = 0.13
            guard t < dur else { return 0 }
            let pitch = f0 * (1 + 1.5 * exp(-t * 40)) // 90→225Hz 快速下扫
            let body = sin(2 * .pi * pitch * t) * exp(-t * 28)
            let noise = (Double.random(in: -1...1)) * exp(-t * 90) * 0.5
            return 0.9 * (body + noise)

        case .woodblock:
            // 高频起振 + 极快阻尼：木鱼“笃”声
            let dur = 0.07
            guard t < dur else { return 0 }
            let env = exp(-t * 75)
            return 0.85 * env * (
                sin(2 * .pi * f0 * t)
                + 0.5 * sin(2 * .pi * f0 * 2.7 * t)
                + 0.25 * sin(2 * .pi * f0 * 5.4 * t))

        case .electronic:
            // 方波感电子滴声 + 音头 click
            let dur = 0.09
            guard t < dur else { return 0 }
            let square = sin(2 * .pi * f0 * t) >= 0 ? 1.0 : -1.0
            let env = exp(-t * 45)
            let blip = t < 0.004 ? 0.5 : 0
            return 0.6 * env * (0.6 * square + 0.4 * sin(2 * .pi * f0 * t)) + blip

        case .voice:
            // 共振峰合成 “哒”：基频谐波 + 两个共振峰带通感 + 起音噪声
            let dur = 0.16
            guard t < dur else { return 0 }
            let env = min(1, t * 120) * exp(-t * 16)            // 慢起快收，像辅音+元音
            let harmonic = (1...5).reduce(0.0) { acc, k in
                acc + (1.0 / Double(k)) * sin(2 * .pi * f0 * Double(k) * t)
            }
            // 共振峰 F1≈750 F2≈1200（/a/ 元音）
            let formants = sin(2 * .pi * 750 * t) * 0.4 + sin(2 * .pi * 1200 * t) * 0.25
            let consonant = t < 0.02 ? Double.random(in: -1...1) * (1 - t * 50) * 0.3 : 0
            return 0.55 * env * (harmonic * 0.5 + formants) + consonant
        }
    }
}
