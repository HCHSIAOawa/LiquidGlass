import SwiftUI

// MARK: - iOS 26 / 27 Native Liquid Glass Bridge Modifiers (With Safe Compiler & OS Guards)

struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let useNativeGlass: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNativeGlass {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

extension View {
    @ViewBuilder
    func adaptiveLiquidGlassCard(
        useNative: Bool,
        tintMode: GlassTintMode,
        cornerRadius: CGFloat,
        morphID: String,
        namespace: Namespace.ID
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNative {
            if let tint = tintMode.nativeTintOverlay {
                self
                    .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
                    .glassEffectID(morphID, in: namespace)
                    .glassEffectTransition(.matchedGeometry)
            } else {
                self
                    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: cornerRadius))
                    .glassEffectID(morphID, in: namespace)
                    .glassEffectTransition(.matchedGeometry)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    @ViewBuilder
    func adaptiveLiquidGlassCapsule(
        useNative: Bool,
        isClear: Bool = false,
        tint: Color? = nil,
        morphID: String? = nil,
        unionID: String? = nil,
        namespace: Namespace.ID
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNative {
            self
                .applyBaseCapsuleGlass(isClear: isClear, tint: tint)
                .applyOptionalGlassIdentity(morphID: morphID, unionID: unionID, namespace: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    @ViewBuilder
    fileprivate func applyBaseCapsuleGlass(isClear: Bool, tint: Color?) -> some View {
        if let tint {
            self.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else if isClear {
            self.glassEffect(.clear.interactive(), in: .capsule)
        } else {
            self.glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    fileprivate func applyOptionalGlassIdentity(
        morphID: String?,
        unionID: String?,
        namespace: Namespace.ID
    ) -> some View {
        if let morphID, let unionID {
            self
                .glassEffectID(morphID, in: namespace)
                .glassEffectUnion(id: unionID, namespace: namespace)
                .glassEffectTransition(.matchedGeometry)
        } else if let morphID {
            self
                .glassEffectID(morphID, in: namespace)
                .glassEffectTransition(.matchedGeometry)
        } else if let unionID {
            self.glassEffectUnion(id: unionID, namespace: namespace)
        } else {
            self
        }
    }
    #endif

    @ViewBuilder
    func adaptiveGlassButtonStyle(useNative: Bool, prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), useNative {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(.plain)
        }
        #else
        self.buttonStyle(.plain)
        #endif
    }
}

// MARK: - In-App Hardware Dynamic Island Interactive Portal (iPhone 18 Pro Calibrated)

struct DynamicIslandPortalOverlay: View {
    let controller: GlassSceneController
    let namespace: Namespace.ID

    var body: some View {
        let hasStoredItems = controller.isVaultedInIsland || controller.isDropletSwallowedByIsland

        ZStack {
            // Subtle interactive aura pill aligned directly over physical Dynamic Island cutout
            Capsule()
                .fill(Color.white.opacity(0.002))
                .frame(width: 150, height: 42)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(hasStoredItems ? 0.85 : 0.25),
                                    Color(red: 0.62, green: 0.42, blue: 1.0).opacity(hasStoredItems ? 0.85 : 0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: hasStoredItems ? 1.5 : 0.7
                        )
                )
                .adaptiveLiquidGlassCapsule(
                    useNative: controller.useNativeSystemGlass && hasStoredItems,
                    isClear: true,
                    morphID: controller.isVaultedInIsland ? "island-vault-anchor" : nil,
                    namespace: namespace
                )

            // Status micro-badge right beneath hardware cutout when cards/droplet are inside Island
            if hasStoredItems || controller.liveActivityEnabled {
                HStack(spacing: 4) {
                    if controller.liveActivityEnabled {
                        Circle()
                            .fill(Color(red: 0.22, green: 0.96, blue: 0.65))
                            .frame(width: 5, height: 5)
                    }
                    Text(islandHintText)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.88))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(Color.black.opacity(0.52), in: Capsule())
                .offset(y: 26)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 168, height: 52)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.68)) {
                controller.toggleIslandCardVault()
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            controller.liveActivityEnabled.toggle()
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if value.translation.height > 0 {
                        controller.updateIslandPullDown(translationY: value.translation.height)
                    }
                }
                .onEnded { _ in
                    controller.endIslandPullDown()
                }
        )
        .position(controller.hardwareIslandCenter)
    }

    private var islandHintText: String {
        if controller.isVaultedInIsland {
            return "已收納視窗 · 點擊噴發展開"
        } else if controller.isDropletSwallowedByIsland {
            return "已吸入水滴 · 下拉吐出"
        } else {
            return "系統動態島同步中"
        }
    }
}

// MARK: - Native Sliding Jelly-Magnifier Liquid Dock (Hybrid iOS 27 Glass + Metal Droplet)

struct NativeLiquidDockOverlay: View {
    let controller: GlassSceneController
    let screenWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        let dockW = controller.dockWidth(for: screenWidth)
        let dockLeft = (screenWidth - dockW) * 0.5
        let slotCount = DockTab.allCases.count
        let slotW = (dockW - 16.0) / CGFloat(slotCount)
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let lift = controller.dockThumbLiftValue
        let useNative = controller.useNativeSystemGlass

        ZStack(alignment: .top) {
            if controller.isScrubbingDock && controller.selectedTab.supportsPinning {
                HStack(spacing: 5) {
                    Image(systemName: controller.isPullingUpToPin ? "pin.fill" : "arrow.up")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(controller.isPullingUpToPin ? Color.black : Color.white)
                    Text(controller.isPullingUpToPin ? "放開以固定/取消固定卡片" : "向上拉可固定多重視窗")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(controller.isPullingUpToPin ? Color.black : Color.white.opacity(0.92))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    controller.isPullingUpToPin ? Color.cyan : Color.black.opacity(0.52),
                    in: Capsule()
                )
                .offset(y: -38)
                .allowsHitTesting(false)
            }

            ZStack {
                // Native resting selection pill when in iOS 27 Native Glass mode & not mid-scrub
                if useNative && !controller.isScrubbingDock {
                    let selectedX = 8.0 + slotW * (CGFloat(controller.selectedTab.rawValue) + 0.5) - dockW * 0.5
                    Capsule()
                        .fill(Color.cyan.opacity(0.18))
                        .frame(width: slotW * 0.92, height: 52)
                        .adaptiveLiquidGlassCapsule(
                            useNative: true,
                            isClear: true,
                            morphID: "dock-selection-pill",
                            namespace: namespace
                        )
                        .offset(x: selectedX)
                        .animation(.spring(response: 0.34, dampingFraction: 0.68), value: controller.selectedTab)
                }

                HStack(spacing: 0) {
                    ForEach(DockTab.allCases) { tab in
                        let slotCenterScreenX = dockLeft + 8.0 + slotW * (CGFloat(tab.rawValue) + 0.5)
                        let normDist = (slotCenterScreenX - controller.dockThumbScreenPos.x) / max(1.0, slotW)
                        let proximity = max(0.0, 1.0 - abs(normDist) * 0.92)
                        let lensCurve = proximity * proximity * (3.0 - 2.0 * proximity)

                        let iconScale = 1.0 + (0.08 + 0.28 * lift) * lensCurve
                        let parallaxX = -normDist * 5.2 * lensCurve * lift
                        let parallaxY = -3.8 * lensCurve * lift
                        let isSelected = (controller.selectedTab == tab)
                        let isPinned = isTabPinned(tab)

                        VStack(spacing: 3) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 17, weight: isSelected ? .black : .semibold))
                                    .foregroundStyle(
                                        lensCurve > 0.45
                                            ? (controller.wallpaper.isBrightBackground && controller.tintMode != .dark
                                                ? Color(red: 0.02, green: 0.36, blue: 0.62)
                                                : Color.cyan)
                                            : primary.opacity(isSelected ? 1.0 : 0.72)
                                    )

                                if isPinned {
                                    Circle()
                                        .fill(Color.cyan)
                                        .frame(width: 5.5, height: 5.5)
                                        .offset(x: 6, y: -3)
                                }
                            }
                            .frame(height: 22)

                            Text(tab.title)
                                .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(primary.opacity(lensCurve > 0.4 ? 1.0 : 0.68))
                        }
                        .scaleEffect(iconScale)
                        .offset(x: parallaxX, y: parallaxY)
                        .frame(width: slotW, height: 68)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(width: dockW, height: 68)
            .adaptiveLiquidGlassCapsule(
                useNative: useNative,
                isClear: controller.tintMode == .clear,
                tint: controller.tintMode.nativeTintOverlay,
                morphID: "bottom-liquid-dock",
                namespace: namespace
            )
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        controller.updateDockScrub(
                            localLocation: value.location,
                            velocityX: value.velocity.width
                        )
                    }
                    .onEnded { value in
                        let movedDist = hypot(value.translation.width, value.translation.height)
                        controller.endDockScrub(wasTap: movedDist < 8.0)
                    }
            )
        }
        .frame(width: dockW, height: 68)
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

// MARK: - Native iOS 26 / 27 Liquid Glass Jelly Toggle Switch

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
                    .shadow(color: Color.black.opacity(isPressing ? 0.35 : 0.18), radius: isPressing ? 7 : 3, y: 2)
                    .frame(width: isPressing ? 31 : 23, height: isPressing ? 25 : 23)
                    .scaleEffect(x: isPressing ? 1.16 : 1.0, y: isPressing ? 1.12 : 1.0)
                    .offset(x: 2.0 + effectiveProg * travel - (isPressing ? 4.0 : 0.0))
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPressing)
                    .animation(.spring(response: 0.30, dampingFraction: 0.62), value: isOn)
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

// MARK: - Native Liquid Glass Jelly Magnifier Slider

struct LiquidJellySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let primaryColor: Color
    let secondaryColor: Color

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
                let thumbW: CGFloat = isScrubbing ? 32.0 : 20.0
                let thumbH: CGFloat = isScrubbing ? 24.0 : 16.0
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
                        .fill(isScrubbing ? Color.white.opacity(0.24) : Color.white)
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
                        .shadow(color: Color.cyan.opacity(isScrubbing ? 0.45 : 0.0), radius: 8)
                        .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
                        .frame(width: thumbW, height: thumbH)
                        .scaleEffect(x: stretchX, y: 2.0 - min(1.3, stretchX) * 0.85)
                        .position(x: thumbCenterX, y: geo.size.height * 0.5)
                        .animation(.spring(response: 0.26, dampingFraction: 0.52), value: isScrubbing)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            if !isScrubbing {
                                isScrubbing = true
                                HapticsManager.shared.tapSoft(intensity: 0.50)
                            }
                            let nextNorm = min(1.0, max(0.0, Double((drag.location.x - 10.0) / usableW)))
                            value = range.lowerBound + nextNorm * span
                            stretchX = 1.0 + min(0.32, abs(drag.velocity.width) / 1600.0)
                            HapticsManager.shared.sliderTick(normalized: nextNorm, buckets: 18, lastBucket: &lastBucket)
                        }
                        .onEnded { _ in
                            isScrubbing = false
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.48)) {
                                stretchX = 1.0
                            }
                            lastBucket = -1
                        }
                )
            }
            .frame(height: 28)

            Text(String(format: format, value))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(secondaryColor)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
