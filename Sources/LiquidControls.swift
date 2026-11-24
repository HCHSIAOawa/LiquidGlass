import SwiftUI

// MARK: - Single-Layer Lightweight Native iOS 26/27 Glass Background Plate (Zero Nesting / 120fps Safe)

extension View {
    /// Applies a single flat native `.glassEffect` background layer strictly behind `self`
    /// without wrapping child subtrees or creating full-screen backdrop container overhead.
    @ViewBuilder
    func singleLayerGlassPlate(
        useNative: Bool,
        tintMode: GlassTintMode,
        cornerRadius: CGFloat
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNative {
            self.background {
                if let tint = tintMode.nativeTintOverlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func singleLayerGlassCapsule(useNative: Bool, tintMode: GlassTintMode) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNative {
            self.background {
                if let tint = tintMode.nativeTintOverlay {
                    Capsule()
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(tint), in: .capsule)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .glassEffect(.regular, in: .capsule)
                }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Strict Single-Axis Horizontal Liquid Dock (Guaranteed Z-Order: Base -> Capsule -> Icons)

struct NativeLiquidDockOverlay: View {
    let controller: GlassSceneController
    let screenWidth: CGFloat

    @State private var dragLocalX: CGFloat? = nil
    @State private var isDraggingHorizontally: Bool = false
    @State private var horizontalStretch: CGFloat = 1.0
    @State private var scrubStartTab: DockTab = .lensLab

    var body: some View {
        let dockW = controller.dockWidth(for: screenWidth)
        let dockLeft = (screenWidth - dockW) * 0.5
        let slotCount = DockTab.allCases.count
        let innerPad: CGFloat = 6.0
        let slotW = (dockW - innerPad * 2.0) / CGFloat(slotCount)
        let minLocalCenterX = innerPad + slotW * 0.5
        let maxLocalCenterX = dockW - innerPad - slotW * 0.5

        let selectedCenterX = innerPad + slotW * (CGFloat(controller.selectedTab.rawValue) + 0.5)
        let currentLocalX = min(max(dragLocalX ?? selectedCenterX, minLocalCenterX), maxLocalCenterX)

        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let useNative = controller.useNativeSystemGlass

        ZStack {
            // LAYER 1 (zIndex 0): Dock Glass Base Plate
            if useNative {
                Color.clear
                    .frame(width: dockW, height: 64)
                    .singleLayerGlassCapsule(useNative: true, tintMode: controller.tintMode)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    )
                    .zIndex(0)
            } else {
                // In Metal mode, base plate is rendered in MTKView; subtle rim keeps crisp alignment
                Capsule()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    .frame(width: dockW, height: 64)
                    .zIndex(0)
            }

            // LAYER 2 (zIndex 1): Horizontal-Locked Refracting Selection Capsule (Strictly Above Base & Below Icons!)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: useNative
                            ? [
                                Color.white.opacity(isDraggingHorizontally ? 0.30 : 0.20),
                                Color.cyan.opacity(isDraggingHorizontally ? 0.24 : 0.14)
                            ]
                            : [
                                Color.white.opacity(isDraggingHorizontally ? 0.12 : 0.06),
                                Color.cyan.opacity(isDraggingHorizontally ? 0.10 : 0.04)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDraggingHorizontally ? 0.92 : 0.55),
                                    Color.cyan.opacity(isDraggingHorizontally ? 0.75 : 0.35),
                                    Color(red: 0.68, green: 0.48, blue: 1.0).opacity(isDraggingHorizontally ? 0.65 : 0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isDraggingHorizontally ? 1.5 : 1.0
                        )
                )
                .shadow(color: Color.cyan.opacity(isDraggingHorizontally ? 0.28 : 0.10), radius: 6, y: 0)
                .frame(width: max(36, slotW - 4.0), height: 52)
                .scaleEffect(x: horizontalStretch, y: 1.0)
                // Y is strictly locked to 32.0 (vertical center of 64pt Dock)!
                .position(x: currentLocalX, y: 32.0)
                .animation(
                    isDraggingHorizontally ? nil : .spring(response: 0.30, dampingFraction: 0.72),
                    value: currentLocalX
                )
                .zIndex(1)

            // LAYER 3 (zIndex 2): Navigation Icons & Text Labels (Strictly On Top!)
            HStack(spacing: 0) {
                ForEach(DockTab.allCases) { tab in
                    let tabCenterX = innerPad + slotW * (CGFloat(tab.rawValue) + 0.5)
                    let normDist = abs(tabCenterX - currentLocalX) / max(1.0, slotW)
                    let proximity = max(0.0, 1.0 - normDist)
                    let smoothProx = proximity * proximity * (3.0 - 2.0 * proximity)

                    // Subtle in-place optical zoom strictly inside slot bounds
                    let itemScale = 1.0 + (isDraggingHorizontally ? 0.16 : 0.06) * smoothProx
                    let isSelected = (controller.selectedTab == tab)
                    let isPinned = isTabPinned(tab)

                    VStack(spacing: 2.5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16.5, weight: isSelected ? .black : .semibold))
                                .foregroundStyle(
                                    smoothProx > 0.45
                                        ? (controller.wallpaper.isBrightBackground && controller.tintMode != .dark
                                            ? Color(red: 0.02, green: 0.38, blue: 0.65)
                                            : Color.cyan)
                                        : primary.opacity(isSelected ? 1.0 : 0.72)
                                )

                            if isPinned {
                                Circle()
                                    .fill(Color.cyan)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 6, y: -2)
                            }
                        }
                        .frame(height: 21)

                        Text(tab.title)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundStyle(primary.opacity(smoothProx > 0.45 ? 1.0 : 0.70))
                    }
                    .scaleEffect(itemScale)
                    .frame(width: slotW, height: 64)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, innerPad)
            .frame(width: dockW, height: 64)
            .zIndex(2)
        }
        .frame(width: dockW, height: 64)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDraggingHorizontally {
                        isDraggingHorizontally = true
                        scrubStartTab = controller.selectedTab
                        HapticsManager.shared.tapSoft(intensity: 0.55)
                    }

                    // Strictly lock to X axis ONLY — ignore value.location.y & value.translation.height completely!
                    let clampedX = min(max(value.location.x, minLocalCenterX), maxLocalCenterX)
                    dragLocalX = clampedX

                    let speedRatio = min(0.14, abs(value.velocity.width) / 2400.0)
                    horizontalStretch = 1.0 + speedRatio

                    controller.updateDockHorizontalScrub(
                        clampedScreenX: dockLeft + clampedX,
                        velocityX: value.velocity.width,
                        isDragging: true
                    )

                    let rawIdx = Int(((clampedX - innerPad) / max(1.0, slotW)).rounded(.down))
                    let idx = min(slotCount - 1, max(0, rawIdx))
                    let hovered = DockTab.allCases[idx]
                    if hovered != controller.selectedTab {
                        controller.selectedTab = hovered
                        HapticsManager.shared.selection()
                    }
                }
                .onEnded { value in
                    let movedX = abs(value.translation.width)
                    if movedX < 7.0 && controller.selectedTab == scrubStartTab && controller.selectedTab != .lensLab {
                        controller.selectedTab = .lensLab
                        HapticsManager.shared.selection()
                    } else {
                        HapticsManager.shared.tapLight(intensity: 0.45)
                    }

                    isDraggingHorizontally = false
                    dragLocalX = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                        horizontalStretch = 1.0
                    }
                    controller.endDockHorizontalScrub()
                }
        )
    }

    private func isTabPinned(_ tab: DockTab) -> Bool {
        switch tab {
        case .musicBeat: return controller.pinnedMusic
        case .controlHub: return controller.pinnedControl
        case .weatherSolar: return controller.pinnedWeather
        case .lensLab, .opticalStudio: return false
        }
    }
}

// MARK: - Native Liquid Glass Jelly Toggle Switch

struct LiquidJellyToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let primaryColor: Color

    @State private var isPressing: Bool = false
    @State private var dragProgress: CGFloat? = nil

    var body: some View {
        let effectiveProg = dragProgress ?? (isOn ? 1.0 : 0.0)
        let travel: CGFloat = 22.0

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(isOn ? Color.cyan : primaryColor.opacity(0.75))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryColor)
                .lineLimit(1)

            Spacer()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Color(red: 0.16, green: 0.84, blue: 0.72) : Color.black.opacity(0.22))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
                    .frame(width: 50, height: 27)

                Capsule()
                    .fill(isPressing ? Color.white.opacity(0.28) : Color.white)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isPressing ? 0.98 : 0.4),
                                        Color.cyan.opacity(isPressing ? 0.85 : 0.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isPressing ? 1.8 : 0.5
                            )
                    )
                    .shadow(color: Color.black.opacity(isPressing ? 0.35 : 0.18), radius: isPressing ? 6 : 3, y: 2)
                    .frame(width: isPressing ? 31 : 23, height: isPressing ? 25 : 23)
                    .offset(x: 2.0 + effectiveProg * travel - (isPressing ? 4.0 : 0.0))
                    .animation(.spring(response: 0.26, dampingFraction: 0.60), value: isPressing)
                    .animation(.spring(response: 0.28, dampingFraction: 0.66), value: isOn)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !isPressing {
                            isPressing = true
                            HapticsManager.shared.tapSoft(intensity: 0.55)
                        }
                        if abs(val.translation.width) > 3 {
                            let base: CGFloat = isOn ? 1.0 : 0.0
                            dragProgress = min(1.0, max(0.0, base + val.translation.width / 26.0))
                        }
                    }
                    .onEnded { val in
                        let moved = abs(val.translation.width)
                        let newState = moved < 5 ? !isOn : ((dragProgress ?? 0.0) >= 0.5)
                        dragProgress = nil
                        isPressing = false
                        if newState != isOn {
                            isOn = newState
                            HapticsManager.shared.selection()
                        } else {
                            HapticsManager.shared.tapLight(intensity: 0.4)
                        }
                    }
            )
        }
    }
}

// MARK: - Native Liquid Glass Jelly Slider (Supports Auto-Switching to Metal Optics on Scrub)

struct LiquidJellySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let primaryColor: Color
    let secondaryColor: Color
    var onScrub: (() -> Void)? = nil

    @State private var isScrubbing: Bool = false
    @State private var stretchX: CGFloat = 1.0
    @State private var lastBucket: Int = -1

    var body: some View {
        let span = max(0.0001, range.upperBound - range.lowerBound)
        let norm = min(1.0, max(0.0, (value - range.lowerBound) / span))

        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryColor.opacity(0.92))
                .frame(width: 54, alignment: .leading)

            GeometryReader { geo in
                let trackW = max(1.0, geo.size.width)
                let thumbW: CGFloat = isScrubbing ? 30.0 : 20.0
                let thumbH: CGFloat = isScrubbing ? 22.0 : 16.0
                let usableW = max(1.0, trackW - 20.0)
                let thumbCenterX = 10.0 + usableW * CGFloat(norm)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(primaryColor.opacity(0.14))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan, Color(red: 0.45, green: 0.65, blue: 1.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8.0, thumbCenterX), height: 6)

                    Capsule()
                        .fill(isScrubbing ? Color.white.opacity(0.26) : Color.white)
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white, isScrubbing ? Color.cyan : Color.white.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isScrubbing ? 1.8 : 0.8
                                )
                        )
                        .shadow(color: Color.cyan.opacity(isScrubbing ? 0.42 : 0.0), radius: 6)
                        .shadow(color: Color.black.opacity(0.24), radius: 3, y: 1.5)
                        .frame(width: thumbW, height: thumbH)
                        .scaleEffect(x: stretchX, y: 1.0)
                        .position(x: thumbCenterX, y: geo.size.height * 0.5)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if !isScrubbing {
                                isScrubbing = true
                                onScrub?()
                                HapticsManager.shared.tapSoft(intensity: 0.50)
                            }
                            let nextNorm = min(1.0, max(0.0, Double((drag.location.x - 10.0) / usableW)))
                            value = range.lowerBound + nextNorm * span
                            stretchX = 1.0 + min(0.24, abs(drag.velocity.width) / 1800.0)
                            HapticsManager.shared.sliderTick(normalized: nextNorm, buckets: 18, lastBucket: &lastBucket)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.62)) {
                                stretchX = 1.0
                            }
                            lastBucket = -1
                        }
                )
            }
            .frame(height: 26)

            Text(String(format: format, value))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(secondaryColor)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
