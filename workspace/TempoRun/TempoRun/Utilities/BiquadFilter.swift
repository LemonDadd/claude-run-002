import Foundation
import Accelerate

/// RBJ Biquad 二阶 IIR 滤波器（vDSP 单样本实现，60Hz 下 CPU 可忽略）。
/// 串联 highpass(1Hz) + lowpass(5Hz) 实现 1–5Hz 带通（Butterworth, Q=0.707）。
final class BiquadFilter {
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    enum Kind { case lowpass, highpass }

    init(kind: Kind, sampleRate: Double, cutoffHz: Double, q: Double = 0.7071068) {
        let w0 = 2.0 * .pi * cutoffHz / sampleRate
        let cosw = cos(w0), sinw = sin(w0)
        let alpha = sinw / (2 * q)
        switch kind {
        case .lowpass:
            b0 = (1 - cosw) / 2 / (1 + alpha)
            b1 = (1 - cosw) / (1 + alpha)
            b2 = (1 - cosw) / 2 / (1 + alpha)
        case .highpass:
            b0 = (1 + cosw) / 2 / (1 + alpha)
            b1 = -(1 + cosw) / (1 + alpha)
            b2 = (1 + cosw) / 2 / (1 + alpha)
        }
        a1 = (-2 * cosw) / (1 + alpha)
        a2 = (1 - alpha) / (1 + alpha)
    }

    @inline(__always)
    func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }

    func reset() { x1 = 0; x2 = 0; y1 = 0; y2 = 0 }
}

/// 带通滤波器链：去除重力分量与高频抖动，保留步频基频 1–5Hz（60–300SPM）
final class BandPass1to5Hz {
    private let hp: BiquadFilter
    private let lp: BiquadFilter
    private var dc = 0.0 // 估计直流分量（重力）

    init(sampleRate: Double = AppConstants.accelerometerHz) {
        hp = BiquadFilter(kind: .highpass, sampleRate: sampleRate, cutoffHz: AppConstants.bandpassLowHz)
        lp = BiquadFilter(kind: .lowpass, sampleRate: sampleRate, cutoffHz: AppConstants.bandpassHighHz)
    }

    /// 输入合加速度模长 g，输出滤波后信号
    @inline(__always)
    func process(_ magnitude: Double) -> Double {
        dc += 0.001 * (magnitude - dc)          // 慢跟踪重力基线
        let centered = magnitude - dc
        return lp.process(hp.process(centered))
    }

    func reset() { hp.reset(); lp.reset(); dc = 0 }
}
