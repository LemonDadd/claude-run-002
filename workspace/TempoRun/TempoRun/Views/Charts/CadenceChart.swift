import SwiftUI
import Charts

/// 步频曲线图：X 时间 / Y 步频，目标步频虚线，双指缩放 + 拖动
struct CadenceChart: View {
    let series: [CadenceSample]
    let target: Int

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var xOffset: CGFloat = 0
    @State private var lastOffset: CGFloat = 0
    @State private var selected: CadenceSample?

    private var windowCount: Int {
        max(20, Int(CGFloat(series.count) / scale))
    }

    var body: some View {
        Chart {
            ForEach(visibleSeries) { sample in
                LineMark(
                    x: .value("时间", sample.timestamp),
                    y: .value("步频", sample.spm))
                .foregroundStyle(Color.accentColor)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("时间", sample.timestamp),
                    y: .value("步频", sample.spm))
                .foregroundStyle(.linearGradient(
                    colors: [.accentColor.opacity(0.22), .accentColor.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            }

            RuleMark(y: .value("目标步频", target))
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("目标 \(target)").font(.caption2).foregroundColor(.orange)
                }

            if let selected {
                RuleMark(x: .value("选中", selected.timestamp))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("时间", selected.timestamp),
                          y: .value("步频", selected.spm))
                    .foregroundStyle(.primary)
                    .annotation {
                        Text("\(selected.spm) SPM")
                            .font(.caption2.bold())
                            .padding(6)
                            .background(.thinMaterial, in: Capsule())
                    }
            }
        }
        .chartYScale(domain: 0...240)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(magnificationGesture.simultaneously(with: panGesture(width: geo.size.width)))
                    .onTapGesture { location in
                        guard let date: Date = proxy.value(atX: location.x, as: Date.self) else { return }
                        selected = visibleSeries.min(by: {
                            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                        })
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { selected = nil }
                    }
            }
        }
        .frame(height: 240)
        .accessibilityLabel("步频曲线，目标 \(target)，双指缩放，单指拖动查看")
    }

    // MARK: 窗口 & 手势

    private var visibleSeries: [CadenceSample] {
        guard !series.isEmpty else { return [] }
        let n = windowCount
        let maxOffset = max(0, series.count - n)
        let indexOffset = min(maxOffset, max(0, Int(-xOffset / 8)))
        let end = series.count - indexOffset
        let start = max(0, end - n)
        return Array(series[start..<end])
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(5, max(1, lastScale * value))
            }
            .onEnded { _ in lastScale = scale }
    }

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                xOffset = lastOffset + v.translation.width
            }
            .onEnded { _ in lastOffset = xOffset }
    }
}
