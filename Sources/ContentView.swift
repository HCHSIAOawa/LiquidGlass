import SwiftUI

struct ContentView: View {
    @State private var lensOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var lightPoint: CGPoint = CGPoint(x: 120, y: 180)

    @State private var refraction: Double = 46
    @State private var bezel: Double = 34
    @State private var dispersion: Double = 0.12
    @State private var frost: Double = 0.6
    @State private var isPillShape: Bool = false

    private let words = ["LIQUID GLASS", "REFRACTION", "METAL SHADER", "SPECULAR", "SWIFTUI", "CLARITY"]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(
                x: size.width / 2 + lensOffset.width,
                y: size.height * 0.42 + lensOffset.height
            )
            let halfSize = isPillShape
                ? CGSize(width: 145, height: 64)
                : CGSize(width: 96, height: 96)
            let cornerRadius: CGFloat = isPillShape ? 32 : 96

            ZStack {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    wallpaperLayer(size: size, time: t)
                        .layerEffect(
                            ShaderLibrary.liquidGlass(
                                .boundingRect,
                                .float2(Float(center.x), Float(center.y)),
                                .float2(Float(halfSize.width), Float(halfSize.height)),
                                .float(Float(cornerRadius)),
                                .float(Float(refraction)),
                                .float(Float(bezel)),
                                .float(Float(dispersion)),
                                .float(Float(frost)),
                                .float2(Float(lightPoint.x), Float(lightPoint.y))
                            ),
                            maxSampleOffset: CGSize(width: 160, height: 160)
                        )
                }

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.001))
                    .frame(width: halfSize.width * 2, height: halfSize.height * 2)
                    .scaleEffect(isDragging ? 1.07 : 1.0)
                    .animation(.spring(response: 0.32, dampingFraction: 0.58), value: isDragging)
                    .position(center)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStart = lensOffset
                                }
                                lensOffset = CGSize(
                                    width: dragStart.width + value.translation.width,
                                    height: dragStart.height + value.translation.height
                                )
                                lightPoint = value.location
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )

                VStack {
                    Spacer()
                    controlPanel
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func wallpaperLayer(size: CGSize, time: TimeInterval) -> some View {
        ZStack {
            Color(red: 0.03, green: 0.05, blue: 0.11)

            Circle()
                .fill(Color(red: 1.0, green: 0.18, blue: 0.34).opacity(0.75))
                .frame(width: 300, height: 300)
                .blur(radius: 65)
                .offset(x: sin(time * 0.7) * 90 - 60, y: cos(time * 0.5) * 80 - 160)

            Circle()
                .fill(Color(red: 0.37, green: 0.36, blue: 0.90).opacity(0.75))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: cos(time * 0.6) * 95 + 70, y: sin(time * 0.45) * 90 - 40)

            Circle()
                .fill(Color(red: 0.0, green: 0.78, blue: 0.75).opacity(0.7))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: sin(time * 0.5 + 1.5) * 85, y: cos(time * 0.65) * 70 + 130)

            VStack(spacing: 10) {
                ForEach(0..<8, id: \.self) { row in
                    let line = (words + words).joined(separator: " — ")
                    let dir: CGFloat = row % 2 == 0 ? -1 : 1
                    let shift = CGFloat((time * 28).truncatingRemainder(dividingBy: 360)) * dir
                    Text(line)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(row % 2 == 0 ? Color.white.opacity(0.92) : Color.cyan.opacity(0.85))
                        .fixedSize()
                        .offset(x: shift)
                }
            }
            .rotationEffect(.degrees(-8))
        }
        .frame(width: size.width, height: size.height)
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SwiftUI + Metal 液態玻璃")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(isPillShape ? "切換圓形" : "切換膠囊") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isPillShape.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.18), in: Capsule())
            }

            paramRow(title: "折射強度", value: $refraction, range: 0...95, format: "%.0f")
            paramRow(title: "倒角寬度", value: $bezel, range: 6...64, format: "%.0f px")
            paramRow(title: "彩虹色散", value: $dispersion, range: 0...0.25, format: "%.2f")
            paramRow(title: "霧面磨砂", value: $frost, range: 0...4.0, format: "%.1f")
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        )
    }

    private func paramRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Slider(value: value, in: range)
                .tint(.cyan)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
        }
    }
}
