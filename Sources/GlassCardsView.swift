import SwiftUI
import PhotosUI

// MARK: - Top Safe-Area HUD (One-Tap Engine Switcher, Photo Import, Reset & 120Hz FPS)

struct TopStatusHUD: View {
    let controller: GlassSceneController
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let namespace: Namespace.ID

    var body: some View {
        let useNative = controller.useNativeSystemGlass
        let isBright = controller.wallpaper.isBrightBackground
        let pillBg = useNative
            ? Color.clear
            : (isBright ? Color.black.opacity(0.68) : Color.black.opacity(0.38))

        HStack(spacing: 6) {
            // One-Tap Instant Switch: iOS 27 Native Glass <-> Custom Metal 120Hz Optics
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    controller.engineMode = controller.engineMode.toggled()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: controller.engineMode.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(controller.engineMode == .nativeAppleGlass ? Color.cyan : Color(red: 1.0, green: 0.72, blue: 0.28))
                    Text(controller.engineMode.title)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(useNative && isBright ? Color.black : Color.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6.5)
                .background(pillBg, in: Capsule())
                .adaptiveLiquidGlassCapsule(
                    useNative: useNative,
                    isClear: false,
                    morphID: "hud-engine-switch",
                    unionID: "hud-left-union",
                    namespace: namespace
                )
            }
            .buttonStyle(.plain)

            Button {
                controller.cycleLensShape()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: controller.lensShape.icon)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text(controller.lensShape.shortTitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(useNative && isBright ? Color.black : Color.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .background(pillBg, in: Capsule())
                .adaptiveLiquidGlassCapsule(
                    useNative: useNative,
                    isClear: false,
                    morphID: "hud-shape-switch",
                    unionID: "hud-left-union",
                    namespace: namespace
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(controller.wallpaper == .customPhoto ? Color.cyan : (useNative && isBright ? Color.black : Color.white))
                    .frame(width: 29, height: 28)
                    .background(pillBg, in: Capsule())
                    .adaptiveLiquidGlassCapsule(
                        useNative: useNative,
                        isClear: false,
                        unionID: "hud-right-union",
                        namespace: namespace
                    )
            }
            .buttonStyle(.plain)

            Button {
                controller.resetPlaygroundLayout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(useNative && isBright ? Color.black : Color.white)
                    .frame(width: 29, height: 28)
                    .background(pillBg, in: Capsule())
                    .adaptiveLiquidGlassCapsule(
                        useNative: useNative,
                        isClear: false,
                        unionID: "hud-right-union",
                        namespace: namespace
                    )
            }
            .buttonStyle(.plain)

            if controller.showFPS {
                HStack(spacing: 4) {
                    Circle()
                        .fill(fpsStatusColor)
                        .frame(width: 6, height: 6)
                    Text("\(controller.currentFPS)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(useNative && isBright ? Color.black : Color.white)
                    Text("FPS")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle((useNative && isBright ? Color.black : Color.white).opacity(0.68))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .background(pillBg, in: Capsule())
                .adaptiveLiquidGlassCapsule(
                    useNative: useNative,
                    isClear: false,
                    morphID: "hud-fps-pill",
                    namespace: namespace
                )
                .onTapGesture {
                    HapticsManager.shared.selection()
                    controller.showFPS = false
                }
            }
        }
    }

    private var fpsStatusColor: Color {
        if controller.currentFPS >= 110 {
            return Color(red: 0.22, green: 0.96, blue: 0.62)
        } else if controller.currentFPS >= 56 {
            return Color.cyan
        } else {
            return Color.orange
        }
    }
}

// MARK: - Zone 0: Dual-Droplet Liquid Fusion Lab Pill Bar (With glassEffectUnion)

struct LensFusionLabPillOverlay: View {
    let controller: GlassSceneController
    let pillWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let useNative = controller.useNativeSystemGlass

        HStack(spacing: 6) {
            labChip(icon: "drop.degreesign.fill", title: "雙水滴", isActive: controller.dualDropletEnabled, primary: primary, subtleFill: subtleFill) {
                controller.dualDropletEnabled.toggle()
            }
            labChip(icon: "infinity", title: "液態融合", isActive: controller.metaballFusionEnabled && controller.dualDropletEnabled, primary: primary, subtleFill: subtleFill) {
                if !controller.dualDropletEnabled { controller.dualDropletEnabled = true }
                controller.metaballFusionEnabled.toggle()
                HapticsManager.shared.selection()
            }
            labChip(icon: "gyroscope", title: "重力滾動", isActive: controller.gravityModeEnabled, primary: primary, subtleFill: subtleFill) {
                controller.gravityModeEnabled.toggle()
            }
            labChip(icon: "water.waves", title: "水波觸控", isActive: controller.touchRipplesEnabled, primary: primary, subtleFill: subtleFill) {
                controller.touchRipplesEnabled.toggle()
                HapticsManager.shared.selection()
            }
        }
        .padding(.horizontal, 10)
        .frame(width: pillWidth, height: 50)
        .adaptiveLiquidGlassCapsule(
            useNative: useNative,
            isClear: controller.tintMode == .clear,
            tint: controller.tintMode.nativeTintOverlay,
            morphID: "zone-lab-pill",
            unionID: "lab-bar-union",
            namespace: namespace
        )
    }

    private func labChip(
        icon: String,
        title: String,
        isActive: Bool,
        primary: Color,
        subtleFill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.black : primary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(isActive ? Color.cyan : subtleFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Zone 1: Dynamic Music Player & Synth Beat Shockwave Card

struct MusicPlayerCardOverlay: View {
    let controller: GlassSceneController
    let cardWidth: CGFloat
    let namespace: Namespace.ID

    @State private var lastScrubBucket: Int = -1
    @State private var activePadBounce: Int = -1

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let prominentFill = controller.tintMode.prominentFillColor(over: controller.wallpaper)
        let useNative = controller.useNativeSystemGlass
        let track = controller.currentTrack

        VStack(spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [track.accentPrimary, track.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: track.accentPrimary.opacity(0.45), radius: 8, y: 3)

                    AudioSpectrumBarsView(isPlaying: controller.isPlayingMusic)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 2)

                HStack(spacing: 5) {
                    Button { controller.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 28, height: 28)
                            .background(useNative ? Color.clear : subtleFill, in: Circle())
                    }
                    .adaptiveGlassButtonStyle(useNative: useNative)

                    Button { controller.togglePlayPause() } label: {
                        Image(systemName: controller.isPlayingMusic ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(useNative ? Color.white : primary)
                            .frame(width: 32, height: 32)
                            .background(useNative ? Color.clear : prominentFill, in: Circle())
                    }
                    .adaptiveGlassButtonStyle(useNative: useNative, prominent: true)

                    Button { controller.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 28, height: 28)
                            .background(useNative ? Color.clear : subtleFill, in: Circle())
                    }
                    .adaptiveGlassButtonStyle(useNative: useNative)

                    CardPinButton(isPinned: controller.pinnedMusic, primary: primary, subtleFill: subtleFill) {
                        controller.togglePin(for: .musicBeat)
                    }
                }
            }

            HStack(spacing: 8) {
                Text(formatTime(controller.trackProgress * track.duration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondary)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { barGeo in
                    let fullW = max(1, barGeo.size.width)
                    let prog = min(max(controller.trackProgress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(subtleFill).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [track.accentPrimary, track.accentSecondary], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, fullW * prog), height: 6)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let next = min(max(Double(val.location.x / fullW), 0.0), 0.999)
                                controller.trackProgress = next
                                HapticsManager.shared.sliderTick(normalized: next, buckets: 20, lastBucket: &lastScrubBucket)
                            }
                            .onEnded { _ in lastScrubBucket = -1 }
                    )
                }
                .frame(height: 16)

                Text("-\(formatTime((1.0 - controller.trackProgress) * track.duration))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 7) {
                ForEach(BeatPadItem.pads) { pad in
                    let isBouncing = (activePadBounce == pad.id)
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.45)) { activePadBounce = pad.id }
                        let padX = controller.musicCardCenter.x + CGFloat(pad.id - 1) * 72.0 - 36.0
                        controller.triggerBeatPad(index: pad.id, screenPoint: CGPoint(x: padX, y: controller.musicCardCenter.y + 52))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
                                if activePadBounce == pad.id { activePadBounce = -1 }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: pad.icon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(pad.color)
                            Text(pad.name)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(isBouncing ? pad.color.opacity(0.38) : subtleFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(pad.color.opacity(isBouncing ? 0.9 : 0.28), lineWidth: 0.9)
                        )
                        .scaleEffect(isBouncing ? 1.10 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: 176)
        .adaptiveLiquidGlassCard(
            useNative: useNative,
            tintMode: controller.tintMode,
            cornerRadius: 30,
            morphID: controller.isVaultedInIsland ? "island-vault-anchor" : "card-music",
            namespace: namespace
        )
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("screen"))
                .onChanged { val in controller.updateMusicCardDrag(translation: val.translation, velocity: val.velocity) }
                .onEnded { val in controller.endMusicCardDrag(velocity: val.velocity) }
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct AudioSpectrumBarsView: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<4, id: \.self) { idx in
                    let phase = t * (4.8 + Double(idx) * 1.15) + Double(idx) * 0.9
                    let level = isPlaying ? (0.32 + 0.68 * abs(sin(phase))) : 0.24
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 3.5, height: CGFloat(8.0 + 16.0 * level))
                }
            }
        }
    }
}

// MARK: - Zone 2: Liquid Control Hub (With System Live Activity Jelly Toggle)

struct MiniControlCenterOverlay: View {
    @Bindable var controller: GlassSceneController
    let cardWidth: CGFloat
    let namespace: Namespace.ID

    @State private var lastBrightnessBucket: Int = -1

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let useNative = controller.useNativeSystemGlass

        VStack(spacing: 9) {
            HStack {
                Label("液態控制中樞", systemImage: "switch.2")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                Spacer()
                Text(controller.engineMode.badgeLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(secondary)
                CardPinButton(isPinned: controller.pinnedControl, primary: primary, subtleFill: subtleFill) {
                    controller.togglePin(for: .controlHub)
                }
            }

            HStack(spacing: 8) {
                controlTile(
                    icon: controller.flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    title: "聚光燈",
                    isActive: controller.flashlightOn,
                    activeColor: Color(red: 1.0, green: 0.78, blue: 0.22),
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.flashlightOn.toggle()
                    HapticsManager.shared.tapMedium()
                }

                controlTile(
                    icon: "gyroscope",
                    title: "陀螺反光",
                    isActive: controller.gyroEnabled,
                    activeColor: Color(red: 0.18, green: 0.86, blue: 0.74),
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.gyroEnabled.toggle()
                }

                controlTile(
                    icon: "arrow.down.circle.fill",
                    title: "重力場",
                    isActive: controller.gravityModeEnabled,
                    activeColor: Color(red: 0.36, green: 0.72, blue: 1.0),
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.gravityModeEnabled.toggle()
                }

                controlTile(
                    icon: controller.engineMode.icon,
                    title: controller.engineMode == .nativeAppleGlass ? "原生引擎" : "Metal引擎",
                    isActive: controller.engineMode == .nativeAppleGlass,
                    activeColor: Color(red: 0.45, green: 0.92, blue: 1.0),
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.engineMode = controller.engineMode.toggled()
                }
            }

            VStack(spacing: 5) {
                LiquidJellyToggle(
                    title: "釘選至系統動態島 (Live Activity)",
                    icon: "capsule.portrait.tophalf.filled",
                    isOn: $controller.liveActivityEnabled,
                    primaryColor: primary
                )
                LiquidJellyToggle(
                    title: "雙水滴與動態島磁吸融合",
                    icon: "drop.degreesign.fill",
                    isOn: $controller.metaballFusionEnabled,
                    primaryColor: primary
                )
                LiquidJellyToggle(
                    title: "超亮稜鏡邊緣光 (Prism Rim)",
                    icon: "sparkle.magnifyingglass",
                    isOn: $controller.prismRimBoostEnabled,
                    primaryColor: primary
                )
            }

            GeometryReader { geo in
                let fullW = max(1, geo.size.width)
                let minB = 0.45
                let maxB = 1.30
                let norm = min(max((controller.sceneBrightness - minB) / (maxB - minB), 0.0), 1.0)

                ZStack(alignment: .leading) {
                    Capsule().fill(subtleFill)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.42), Color(red: 1.0, green: 0.92, blue: 0.68).opacity(0.68)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(36, fullW * norm))

                    HStack {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(primary)
                        Text("環境輝度")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(primary)
                        Spacer()
                        Text("\(Int((controller.sceneBrightness * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(primary)
                    }
                    .padding(.horizontal, 12)
                }
                .clipShape(Capsule())
                .contentShape(Capsule())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let ratio = min(max(Double(val.location.x / fullW), 0.0), 1.0)
                            controller.sceneBrightness = minB + ratio * (maxB - minB)
                            HapticsManager.shared.sliderTick(normalized: ratio, buckets: 16, lastBucket: &lastBrightnessBucket)
                        }
                        .onEnded { _ in lastBrightnessBucket = -1 }
                )
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: cardWidth, height: 252)
        .adaptiveLiquidGlassCard(
            useNative: useNative,
            tintMode: controller.tintMode,
            cornerRadius: 30,
            morphID: controller.isVaultedInIsland ? "island-vault-anchor" : "card-control",
            namespace: namespace
        )
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("screen"))
                .onChanged { val in controller.updateControlCardDrag(translation: val.translation, velocity: val.velocity) }
                .onEnded { val in controller.endControlCardDrag(velocity: val.velocity) }
        )
    }

    private func controlTile(
        icon: String,
        title: String,
        isActive: Bool,
        activeColor: Color,
        primary: Color,
        subtleFill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isActive ? Color(red: 0.06, green: 0.08, blue: 0.14) : primary)
                Text(title)
                    .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? Color(red: 0.06, green: 0.08, blue: 0.14) : primary.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isActive ? activeColor : subtleFill)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Zone 3: Spatial Weather & 24h Solar Arc Liquid Glass Card

struct WeatherSolarCardOverlay: View {
    @Bindable var controller: GlassSceneController
    let cardWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let useNative = controller.useNativeSystemGlass
        let cond = controller.weatherCondition
        let tempOffset = Int((sin((controller.solarHour - 9.0) / 24.0 * 2.0 * .pi) * 4.0).rounded())
        let displayTemp = cond.baseTemp + tempOffset

        VStack(spacing: 11) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Image(systemName: isNightHour ? "moon.stars.fill" : cond.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(isNightHour ? Color.cyan : Color(red: 1.0, green: 0.80, blue: 0.28))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(displayTemp)° · \(cond.title)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(primary)
                        Text("\(cond.citySubtitle) · 濕度 \(cond.humidity)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(secondary)
                    }
                }

                Spacer()

                CardPinButton(isPinned: controller.pinnedWeather, primary: primary, subtleFill: subtleFill) {
                    controller.togglePin(for: .weatherSolar)
                }
            }

            HStack(spacing: 6) {
                ForEach(WeatherCondition.allCases) { item in
                    let selected = (controller.weatherCondition == item)
                    Button {
                        controller.weatherCondition = item
                        controller.triggerRipple(at: controller.weatherCardCenter, strength: 0.70)
                        HapticsManager.shared.selection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(item.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(selected ? Color.black : primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            selected ? Color.white : subtleFill,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            LiquidJellySlider(
                title: isNightHour ? "星夜時光" : "日照軌跡",
                value: $controller.solarHour,
                range: 0.0...23.9,
                format: "%02.0f:00",
                primaryColor: primary,
                secondaryColor: secondary
            )
            .onChange(of: Int(controller.solarHour)) { _, _ in
                controller.syncLiveActivityIfNeeded()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: 196)
        .adaptiveLiquidGlassCard(
            useNative: useNative,
            tintMode: controller.tintMode,
            cornerRadius: 30,
            morphID: controller.isVaultedInIsland ? "island-vault-anchor" : "card-weather",
            namespace: namespace
        )
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("screen"))
                .onChanged { val in controller.updateWeatherCardDrag(translation: val.translation, velocity: val.velocity) }
                .onEnded { val in controller.endWeatherCardDrag(velocity: val.velocity) }
        )
    }

    private var isNightHour: Bool {
        controller.solarHour < 5.8 || controller.solarHour > 19.2
    }
}

// MARK: - Zone 4: Optical & Wallpaper Studio Drawer

struct StudioDrawerOverlay: View {
    @Bindable var controller: GlassSceneController
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let drawerWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        let useNative = controller.useNativeSystemGlass
        let primary: Color = controller.tintMode == .light
            ? Color(red: 0.08, green: 0.11, blue: 0.18)
            : Color.white
        let secondary = primary.opacity(0.68)
        let pillBg = controller.tintMode == .light
            ? Color.black.opacity(0.08)
            : Color.white.opacity(0.14)

        VStack(spacing: 10) {
            HStack {
                Label("光學與雙引擎工作坊", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) {
                        controller.engineMode = controller.engineMode.toggled()
                    }
                } label: {
                    Text(controller.engineMode.badgeLabel)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.cyan, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    HapticsManager.shared.tapLight()
                    controller.selectedTab = .lensLab
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secondary)
                        .frame(width: 26, height: 26)
                        .background(pillBg, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(WallpaperPreset.builtInPresets) { preset in
                    let selected = controller.wallpaper == preset
                    Button {
                        controller.wallpaper = preset
                        HapticsManager.shared.selection()
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 13, weight: .bold))
                            Text(preset.title)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(selected ? Color.black : primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            selected ? Color.white : pillBg,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    let selected = controller.wallpaper == .customPhoto
                    VStack(spacing: 3) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("相簿")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selected ? Color.black : primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        selected ? Color.cyan : pillBg,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(GlassTintMode.allCases) { mode in
                    let isSelected = controller.tintMode == mode
                    Button {
                        controller.tintMode = mode
                        HapticsManager.shared.selection()
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.black : primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color(red: 0.56, green: 0.94, blue: 1.0) : pillBg,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }

                if controller.wallpaper == .customPhoto {
                    Button {
                        controller.showTypographyOnPhoto.toggle()
                        HapticsManager.shared.selection()
                    } label: {
                        Image(systemName: "textformat")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(controller.showTypographyOnPhoto ? Color.black : primary)
                            .frame(width: 34, height: 30)
                            .background(controller.showTypographyOnPhoto ? Color.white : pillBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 6) {
                LiquidJellySlider(title: "折射強度", value: $controller.refraction, range: 0...95, format: "%.0f", primaryColor: primary, secondaryColor: secondary)
                LiquidJellySlider(title: "倒角寬度", value: $controller.bezel, range: 6...68, format: "%.0f pt", primaryColor: primary, secondaryColor: secondary)
                LiquidJellySlider(title: "彩虹色散", value: $controller.dispersion, range: 0...0.28, format: "%.2f", primaryColor: primary, secondaryColor: secondary)
                LiquidJellySlider(title: "霧面磨砂", value: $controller.frost, range: 0...4.0, format: "%.1f", primaryColor: primary, secondaryColor: secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: drawerWidth, height: 360)
        .adaptiveLiquidGlassCard(
            useNative: useNative,
            tintMode: controller.tintMode,
            cornerRadius: 32,
            morphID: "card-studio-drawer",
            namespace: namespace
        )
    }
}

private struct CardPinButton: View {
    let isPinned: Bool
    let primary: Color
    let subtleFill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isPinned ? Color.black : primary.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(isPinned ? Color.cyan : subtleFill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
