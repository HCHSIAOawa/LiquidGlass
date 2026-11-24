import SwiftUI
import QuartzCore
import simd

// MARK: - Single-Layer Lightweight Native iOS 26/27 Glass Background Plates (Zero Nesting / 120fps Safe)

extension View {
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

    @ViewBuilder
    func singleLayerGlassCircle(useNative: Bool, tintMode: GlassTintMode) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNative {
            self.background {
                if let tint = tintMode.nativeTintOverlay {
                    Circle()
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(tint), in: .circle)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .glassEffect(.regular, in: .circle)
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

// MARK: - Apple Native Two-Part Single-Axis Optical Magnifier Liquid Dock
// Structure: Left Main Capsule (78% width: 專注, 探索, 音樂, 控制) + 10pt Gap + Right Independent Circular Glass Sphere (工坊)

struct NativeLiquidDockOverlay: View {
    let controller: GlassSceneController
    let screenWidth: CGFloat

    @State private var dragLocalX: CGFloat? = nil
    @State private var isDraggingHorizontally: Bool = false
    @State private var horizontalStretch: CGFloat = 1.0
    @State private var scrubStartTab: DockTab = .focusHourglass
    @State private var isPressingStudioOrb: Bool = false

    var body: some View {
        let mainW = controller.dockMainCapsuleWidth(for: screenWidth)
        let gap = controller.dockSplitGap
        let orbD = controller.dockStudioOrbDiameter
        let dockH = controller.dockHeight
        let totalW = controller.dockTotalAssemblyWidth(for: screenWidth)
        let assemblyLeft = controller.dockAssemblyLeft(for: screenWidth)

        let mainTabs = DockTab.mainCapsuleTabs
        let slotCount = mainTabs.count
        let innerPad: CGFloat = 5.0
        let slotW = (mainW - innerPad * 2.0) / CGFloat(slotCount)
        let minLocalCenterX = innerPad + slotW * 0.5
        let maxLocalCenterX = mainW - innerPad - slotW * 0.5

        let activeMainIdx = controller.selectedTab.isMainCapsuleTab ? controller.selectedTab.rawValue : 0
        let selectedCenterX = innerPad + slotW * (CGFloat(activeMainIdx) + 0.5)
        let currentLocalX = min(max(dragLocalX ?? selectedCenterX, minLocalCenterX), maxLocalCenterX)

        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let useNative = controller.useNativeSystemGlass
        let showMainPillIndicator = controller.selectedTab.isMainCapsuleTab || isDraggingHorizontally

        HStack(spacing: gap) {
            // PART 1: Left Main Capsule (78% width — 專注, 探索, 音樂, 控制)
            ZStack {
                // LAYER 0: Base Plate (Automatically becomes clearer/more transparent when sliding!)
                if useNative {
                    Color.clear
                        .frame(width: mainW, height: dockH)
                        .singleLayerGlassCapsule(useNative: true, tintMode: controller.tintMode)
                        .opacity(isDraggingHorizontally ? 0.68 : 1.0)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(isDraggingHorizontally ? 0.30 : 0.20), lineWidth: 0.8)
                        )
                        .zIndex(0)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(isDraggingHorizontally ? 0.01 : 0.03))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(isDraggingHorizontally ? 0.26 : 0.16), lineWidth: 0.75)
                        )
                        .frame(width: mainW, height: dockH)
                        .zIndex(0)
                }

                // LAYER 1: Dual-State Resting Inset <-> Expanding High-Refraction Convex Magnifier Water-Droplet!
                if showMainPillIndicator {
                    let lensWidth = isDraggingHorizontally ? (slotW + 8.0) : max(36.0, slotW - 4.0)
                    let lensHeight: CGFloat = isDraggingHorizontally ? 56.0 : 48.0

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isDraggingHorizontally
                                    ? [
                                        Color.white.opacity(useNative ? 0.34 : 0.16),
                                        DockTab.skyBlueAccent.opacity(useNative ? 0.22 : 0.10)
                                    ]
                                    : [
                                        Color.white.opacity(useNative ? 0.14 : 0.08),
                                        Color.white.opacity(useNative ? 0.08 : 0.04)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: isDraggingHorizontally
                                            ? [
                                                Color.white.opacity(0.96),
                                                DockTab.skyBlueAccent.opacity(0.88),
                                                Color(red: 0.68, green: 0.46, blue: 1.0).opacity(0.76),
                                                Color(red: 1.0, green: 0.52, blue: 0.64).opacity(0.62)
                                            ]
                                            : [
                                                Color.white.opacity(0.28),
                                                DockTab.skyBlueAccent.opacity(0.20)
                                            ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isDraggingHorizontally ? 1.65 : 0.85
                                )
                        )
                        .shadow(
                            color: DockTab.skyBlueAccent.opacity(isDraggingHorizontally ? 0.34 : 0.06),
                            radius: isDraggingHorizontally ? 9 : 4,
                            y: 0
                        )
                        .frame(width: lensWidth, height: lensHeight)
                        .scaleEffect(
                            x: horizontalStretch,
                            y: isDraggingHorizontally ? (1.0 / max(0.92, sqrt(horizontalStretch))) : 1.0
                        )
                        // Y-Axis strictly locked to dockH * 0.5 (31.0pt)! Vertical drag 100% ignored!
                        .position(x: currentLocalX, y: dockH * 0.5)
                        .animation(
                            isDraggingHorizontally ? nil : .spring(response: 0.32, dampingFraction: 0.64),
                            value: currentLocalX
                        )
                        .animation(.spring(response: 0.24, dampingFraction: 0.68), value: isDraggingHorizontally)
                        .zIndex(1)
                }

                // LAYER 2: 4 Main Tab Icons & Labels (Optical Magnification + Chromatic Fringe Under Moving Lens!)
                HStack(spacing: 0) {
                    ForEach(mainTabs) { tab in
                        let tabCenterX = innerPad + slotW * (CGFloat(tab.rawValue) + 0.5)
                        let normDist = abs(tabCenterX - currentLocalX) / max(1.0, slotW * 0.95)
                        let proximity = showMainPillIndicator ? max(0.0, 1.0 - normDist) : 0.0
                        let smoothProx = proximity * proximity * (3.0 - 2.0 * proximity)

                        // Optical convex lens zoom when droplet glides across slot!
                        let itemScale = 1.0 + (isDraggingHorizontally ? 0.22 : 0.04) * smoothProx
                        let isSelected = (controller.selectedTab == tab)
                        let isPinned = isTabPinned(tab)
                        let chromaOffset = isDraggingHorizontally ? (1.25 * smoothProx) : 0.0

                        let activeIconColor: Color = controller.wallpaper.isBrightBackground && controller.tintMode != .dark
                            ? Color(red: 0.02, green: 0.44, blue: 0.76)
                            : DockTab.skyBlueAccent // #38BDF8 Bright Sky Blue!

                        VStack(spacing: 2.5) {
                            ZStack(alignment: .topTrailing) {
                                // Subtle RGB chromatic dispersion halo when inside moving convex water droplet!
                                if chromaOffset > 0.15 {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 16.5, weight: .bold))
                                        .foregroundStyle(Color(red: 1.0, green: 0.28, blue: 0.48).opacity(0.48 * smoothProx))
                                        .offset(x: -chromaOffset, y: -0.3)
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 16.5, weight: .bold))
                                        .foregroundStyle(Color.cyan.opacity(0.55 * smoothProx))
                                        .offset(x: chromaOffset, y: 0.3)
                                }

                                Image(systemName: tab.icon)
                                    .font(.system(size: 16.5, weight: isSelected ? .black : .semibold))
                                    .foregroundStyle(
                                        (isSelected || (isDraggingHorizontally && smoothProx > 0.45))
                                            ? activeIconColor
                                            : primary.opacity(0.68)
                                    )

                                if isPinned {
                                    Circle()
                                        .fill(DockTab.skyBlueAccent)
                                        .frame(width: 5, height: 5)
                                        .offset(x: 6, y: -2)
                                }
                            }
                            .frame(height: 21)

                            Text(tab.title)
                                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(
                                    isSelected
                                        ? activeIconColor
                                        : primary.opacity(smoothProx > 0.45 ? 0.96 : 0.66)
                                )
                        }
                        .scaleEffect(itemScale)
                        .frame(width: slotW, height: dockH)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, innerPad)
                .frame(width: mainW, height: dockH)
                .zIndex(2)
            }
            .frame(width: mainW, height: dockH)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingHorizontally {
                            isDraggingHorizontally = true
                            scrubStartTab = controller.selectedTab
                            // Velocity-preserving mid-flight catch: start from live spring X if already in main capsule!
                            if controller.selectedTab.isMainCapsuleTab {
                                let liveX = min(max(controller.liveDockThumbLocalX, minLocalCenterX), maxLocalCenterX)
                                let targetX = min(max(value.location.x, minLocalCenterX), maxLocalCenterX)
                                dragLocalX = liveX + (targetX - liveX) * 0.65
                            } else {
                                dragLocalX = min(max(value.location.x, minLocalCenterX), maxLocalCenterX)
                            }
                            HapticsManager.shared.tapSoft(intensity: 0.55)
                        } else {
                            // Strictly 1D X-axis lock — Y movement 100% ignored!
                            let clampedX = min(max(value.location.x, minLocalCenterX), maxLocalCenterX)
                            dragLocalX = clampedX
                        }

                        // Allow sliding right across the 10pt gap onto the Studio Orb!
                        if value.location.x > mainW + gap * 0.6 {
                            if controller.selectedTab != .opticalStudio {
                                controller.selectedTab = .opticalStudio
                                controller.triggerStudioOrbPulse()
                                HapticsManager.shared.selection()
                            }
                            return
                        }

                        let activeX = dragLocalX ?? selectedCenterX
                        let speedRatio = min(0.18, abs(value.velocity.width) / 2100.0)
                        horizontalStretch = 1.0 + speedRatio

                        controller.updateDockHorizontalScrub(
                            clampedScreenX: assemblyLeft + activeX,
                            velocityX: value.velocity.width,
                            isDragging: true
                        )

                        let rawIdx = Int(((activeX - innerPad) / max(1.0, slotW)).rounded(.down))
                        let idx = min(slotCount - 1, max(0, rawIdx))
                        let hovered = mainTabs[idx]
                        if hovered != controller.selectedTab {
                            controller.selectedTab = hovered
                            HapticsManager.shared.selection()
                        }
                    }
                    .onEnded { value in
                        let movedX = abs(value.translation.width)
                        if movedX < 6.0 && controller.selectedTab == scrubStartTab && controller.selectedTab != .focusHourglass {
                            // Tapping an already-active secondary tab can stay or give light tactile acknowledgement
                            HapticsManager.shared.tapLight(intensity: 0.42)
                        } else {
                            HapticsManager.shared.tapLight(intensity: 0.46)
                        }

                        isDraggingHorizontally = false
                        dragLocalX = nil
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.62)) {
                            horizontalStretch = 1.0
                        }
                        controller.endDockHorizontalScrub(releaseVelocityX: value.velocity.width)
                    }
            )

            // PART 2: Independent Circular Glass Sphere (10pt Gap — 工坊 Optical Lab!)
            let isStudioActive = (controller.selectedTab == .opticalStudio)
            let studioIconColor: Color = controller.wallpaper.isBrightBackground && controller.tintMode != .dark
                ? Color(red: 0.02, green: 0.44, blue: 0.76)
                : DockTab.skyBlueAccent

            ZStack {
                if useNative {
                    Color.clear
                        .frame(width: orbD, height: orbD)
                        .singleLayerGlassCircle(useNative: true, tintMode: controller.tintMode)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: isStudioActive
                                            ? [Color.white.opacity(0.90), DockTab.skyBlueAccent.opacity(0.75)]
                                            : [Color.white.opacity(0.26), Color.white.opacity(0.10)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isStudioActive ? 1.4 : 0.8
                                )
                        )
                } else {
                    Circle()
                        .fill(isStudioActive ? DockTab.skyBlueAccent.opacity(0.10) : Color.white.opacity(0.03))
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: isStudioActive
                                            ? [Color.white.opacity(0.88), DockTab.skyBlueAccent.opacity(0.78), Color(red: 0.68, green: 0.48, blue: 1.0).opacity(0.55)]
                                            : [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isStudioActive ? 1.4 : 0.75
                                )
                        )
                        .frame(width: orbD, height: orbD)
                }

                VStack(spacing: 2.5) {
                    Image(systemName: DockTab.opticalStudio.icon)
                        .font(.system(size: 16.5, weight: isStudioActive ? .black : .semibold))
                        .foregroundStyle(isStudioActive ? studioIconColor : primary.opacity(0.76))
                        .frame(height: 21)

                    Text(DockTab.opticalStudio.title)
                        .font(.system(size: 10.5, weight: isStudioActive ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isStudioActive ? studioIconColor : primary.opacity(0.70))
                }
            }
            .frame(width: orbD, height: orbD)
            .scaleEffect(isPressingStudioOrb ? 1.12 : (isStudioActive ? 1.04 : 1.0))
            .shadow(color: DockTab.skyBlueAccent.opacity(isStudioActive || isPressingStudioOrb ? 0.28 : 0.0), radius: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.58), value: isPressingStudioOrb)
            .animation(.spring(response: 0.30, dampingFraction: 0.65), value: isStudioActive)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressingStudioOrb {
                            isPressingStudioOrb = true
                            controller.triggerStudioOrbPulse()
                            HapticsManager.shared.tapSoft(intensity: 0.58)
                        }
                    }
                    .onEnded { _ in
                        isPressingStudioOrb = false
                        if controller.selectedTab == .opticalStudio {
                            controller.selectedTab = .focusHourglass
                        } else {
                            controller.selectedTab = .opticalStudio
                        }
                        HapticsManager.shared.selection()
                    }
            )
        }
        .frame(width: totalW, height: dockH)
    }

    private func isTabPinned(_ tab: DockTab) -> Bool {
        switch tab {
        case .musicBeat: return controller.pinnedMusic
        case .controlHub: return controller.pinnedControl
        default: return false
        }
    }
}

// MARK: - Velocity-Preserving 120Hz Spring Card State (Zero Mid-Flight Grab Jump & Zero Idle CPU!)

@MainActor
@Observable
final class VelocityCardSpringState {
    var offset: CGSize = .zero
    private var velocity: SIMD2<Float> = .zero
    private var isDragging: Bool = false
    private var lastTranslation: CGSize = .zero
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    func onDragChanged(translation: CGSize, velocity gestureVel: CGSize, sync: (CGSize) -> Void) {
        if !isDragging {
            isDragging = true
            lastTranslation = .zero
            stopDisplayLink()
            // Notice: offset & velocity keep their EXACT live mid-flight values — zero teleport!
        }
        let dx = translation.width - lastTranslation.width
        let dy = translation.height - lastTranslation.height
        lastTranslation = translation

        offset = CGSize(width: offset.width + dx, height: offset.height + dy)
        let gv = SIMD2<Float>(Float(gestureVel.width), Float(gestureVel.height))
        velocity = velocity * 0.30 + gv * 0.70
        sync(offset)
    }

    func onDragEnded(velocity gestureVel: CGSize, bounds: CGSize, sync: @escaping (CGSize, CGSize?) -> Void) {
        isDragging = false
        lastTranslation = .zero
        let gv = SIMD2<Float>(Float(gestureVel.width), Float(gestureVel.height))
        velocity = velocity * 0.25 + gv * 0.75
        sync(offset, gestureVel)
        startSettleLoop(bounds: bounds, sync: sync)
    }

    private func startSettleLoop(bounds: CGSize, sync: @escaping (CGSize, CGSize?) -> Void) {
        stopDisplayLink()
        lastTick = CACurrentMediaTime()
        let proxy = DisplayLinkTarget { [weak self] link in
            guard let self = self else {
                link.invalidate()
                return
            }
            self.stepSettle(now: link.timestamp, bounds: bounds, sync: sync)
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkTarget.tick(_:)))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stepSettle(now: CFTimeInterval, bounds: CGSize, sync: (CGSize, CGSize?) -> Void) {
        let dt = Float(min(max(now - lastTick, 1.0 / 240.0), 1.0 / 30.0))
        lastTick = now

        // Soft boundary clamping with spring overshoot & momentum decay
        let cur = SIMD2<Float>(Float(offset.width), Float(offset.height))
        let maxX = Float(bounds.width)
        let maxY = Float(bounds.height)
        let clampedTarget = SIMD2<Float>(
            min(max(cur.x, -maxX), maxX),
            min(max(cur.y, -maxY), maxY)
        )

        let boundaryForce = -320.0 * (cur - clampedTarget)
        velocity += boundaryForce * dt
        velocity *= exp(-7.5 * dt)
        let next = cur + velocity * dt
        offset = CGSize(width: CGFloat(next.x), height: CGFloat(next.y))
        sync(offset, nil)

        if simd_length(velocity) < 3.0 && simd_distance(next, clampedTarget) < 0.6 {
            offset = CGSize(width: CGFloat(clampedTarget.x), height: CGFloat(clampedTarget.y))
            velocity = .zero
            sync(offset, nil)
            stopDisplayLink()
        }
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

private final class DisplayLinkTarget: NSObject {
    let handler: @MainActor (CADisplayLink) -> Void

    init(handler: @escaping @MainActor (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @MainActor
    @objc func tick(_ link: CADisplayLink) {
        handler(link)
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
                .foregroundStyle(isOn ? DockTab.skyBlueAccent : primaryColor.opacity(0.75))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryColor)
                .lineLimit(1)

            Spacer()

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Color(red: 0.16, green: 0.80, blue: 0.78) : Color.black.opacity(0.22))
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
                                        DockTab.skyBlueAccent.opacity(isPressing ? 0.85 : 0.0)
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

// MARK: - Native Liquid Glass Jelly Slider (Auto-Switches to Metal Optics on Scrub)

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
                                colors: [DockTab.skyBlueAccent, Color(red: 0.45, green: 0.65, blue: 1.0)],
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
                                        colors: [Color.white, isScrubbing ? DockTab.skyBlueAccent : Color.white.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isScrubbing ? 1.8 : 0.8
                                )
                        )
                        .shadow(color: DockTab.skyBlueAccent.opacity(isScrubbing ? 0.42 : 0.0), radius: 6)
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
