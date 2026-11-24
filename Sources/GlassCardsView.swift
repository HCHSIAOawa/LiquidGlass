import SwiftUI
import PhotosUI

// MARK: - Top Safe-Area HUD (Clean Unobstructed Top Bar Below Status Bar)

struct TopStatusHUD: View {
    let controller: GlassSceneController
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        let isBright = controller.wallpaper.isBrightBackground
        let pillBg = isBright ? Color.black.opacity(0.70) : Color.black.opacity(0.42)

        HStack(spacing: 6) {
            // Instant Switch: Metal 120Hz Optics <-> iOS 27 Native Glass
            Button {
                controller.engineMode = controller.engineMode.toggled()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: controller.engineMode.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(controller.engineMode == .nativeAppleGlass ? DockTab.skyBlueAccent : Color(red: 1.0, green: 0.76, blue: 0.28))
                    Text(controller.engineMode.title)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6.5)
                .background(pillBg, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            if controller.selectedTab == .focusHourglass {
                Button {
                    controller.switchPomodoroMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: controller.pomodoroMode.icon)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(controller.pomodoroMode.accentColor)
                        Text(controller.pomodoroMode.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6.5)
                    .background(pillBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(controller.pomodoroMode.accentColor.opacity(0.35), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    controller.cycleLensShape()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: controller.lensShape.icon)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(DockTab.skyBlueAccent)
                        Text(controller.lensShape.shortTitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6.5)
                    .background(pillBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(controller.wallpaper == .customPhoto ? DockTab.skyBlueAccent : Color.white)
                    .frame(width: 30, height: 28)
                    .background(pillBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            Button {
                controller.resetPlaygroundLayout()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 28)
                    .background(pillBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.7))
            }
            .buttonStyle(.plain)

            if controller.showFPS {
                HStack(spacing: 4) {
                    Circle()
                        .fill(fpsStatusColor)
                        .frame(width: 6, height: 6)
                    Text("\(controller.currentFPS) FPS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .background(pillBg, in: Capsule())
                .overlay(Capsule().strokeBorder(fpsStatusColor.opacity(0.45), lineWidth: 0.7))
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
            return DockTab.skyBlueAccent
        } else {
            return Color.orange
        }
    }
}

// MARK: - Flagship Tab 0: Liquid Hourglass Pomodoro HUD & Zen Minimalist Controls

struct FocusHourglassOverlay: View {
    let controller: GlassSceneController
    let size: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let mode = controller.pomodoroMode
        let hgCenter = controller.hourglassCenter
        let dialRadius = controller.radialDialRadiusPt

        ZStack {
            // 1. Subtle Top Digital Time Readout Above Radial Ring (Smoothly scales down & fades in Zen Mode)
            if !controller.isZenMode {
                VStack(spacing: 3) {
                    Text(formatCountdown(controller.displayRemainingSeconds))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primary)
                        .contentTransition(.numericText(countsDown: true))
                        .shadow(color: Color.black.opacity(0.28), radius: 8, y: 2)

                    HStack(spacing: 6) {
                        Text(controller.isPomodoroRunning ? "\(mode.subtitle) · 滴落計時中" : "滑動外環設定 \(controller.targetMinutes) 分鐘 · 翻轉手機啟動")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(secondary)

                        if controller.completedPomodoros > 0 {
                            Text("· 🍅 \(controller.completedPomodoros)")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(mode.accentColor)
                        }
                    }
                }
                .allowsHitTesting(false)
                .position(x: size.width * 0.5, y: max(safeTop + 76, hgCenter.y - dialRadius - 42))
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            } else {
                // Ultra-minimal whisper readout in Zen Mode (pure floating hourglass remains focal hero!)
                Text(formatCountdown(controller.displayRemainingSeconds))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(primary.opacity(0.45))
                    .allowsHitTesting(false)
                    .position(x: size.width * 0.5, y: safeTop + 42)
                    .transition(.opacity)
            }

            // 2. Bottom Floating Liquid Glass Action Pill (Start/Pause, Physical Flip/Reset, Mode Switch, Zen Mode)
            if !controller.isZenMode {
                let pillW = min(size.width - 44.0, 316.0)
                let pillY = size.height - safeBottom - 116.0

                HStack(spacing: 8) {
                    // Mode Toggle: Focus 25m <-> Break 5m
                    Button {
                        controller.switchPomodoroMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(mode.accentColor)
                            Text(mode.shortTitle)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(primary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(subtleFill, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    // Primary Action: Start / Pause
                    Button {
                        controller.togglePomodoroStartPause()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: controller.isPomodoroRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 12.5, weight: .black))
                            Text(controller.isPomodoroRunning ? "暫停" : "開始專注")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            LinearGradient(
                                colors: [mode.accentColor, mode.secondaryColor.opacity(0.92)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)

                    // Flip & Reset Hourglass
                    Button {
                        controller.flipAndResetPomodoro(autoStart: false)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 38, height: 38)
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    // Enter Zen Minimalist Immersive Mode
                    Button {
                        controller.setZenMode(true)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 38, height: 38)
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(width: pillW, height: 54)
                .singleLayerGlassCapsule(useNative: controller.useNativeSystemGlass, tintMode: controller.tintMode)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .position(x: size.width * 0.5, y: pillY)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
    }

    private func formatCountdown(_ totalSec: Int) -> String {
        let clamped = max(0, totalSec)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}

// MARK: - Tab 1: Dual-Droplet Liquid Fusion Lab Pill Bar

struct LensFusionLabPillOverlay: View {
    let controller: GlassSceneController
    let pillWidth: CGFloat

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)

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
        .frame(width: pillWidth, height: 48)
        .singleLayerGlassCapsule(useNative: controller.useNativeSystemGlass, tintMode: controller.tintMode)
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
            .frame(height: 32)
            .background(isActive ? DockTab.skyBlueAccent : subtleFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 2: Dynamic Music Player & Synth Beat Shockwave Card (Velocity-Preserving Mid-Flight Grab!)

struct MusicPlayerCardOverlay: View {
    let controller: GlassSceneController
    let cardWidth: CGFloat
    let baseCenter: CGPoint

    @State private var springState = VelocityCardSpringState()
    @State private var lastScrubBucket: Int = -1
    @State private var activePadBounce: Int = -1

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let prominentFill = controller.tintMode.prominentFillColor(over: controller.wallpaper)
        let track = controller.currentTrack
        let liveOffset = springState.offset

        VStack(spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient(colors: [track.accentPrimary, track.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                        .shadow(color: track.accentPrimary.opacity(0.42), radius: 6, y: 2)

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
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button { controller.togglePlayPause() } label: {
                        Image(systemName: controller.isPlayingMusic ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(primary)
                            .frame(width: 32, height: 32)
                            .background(prominentFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button { controller.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 28, height: 28)
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)

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
                        let padX = baseCenter.x + liveOffset.width + CGFloat(pad.id - 1) * 72.0 - 36.0
                        controller.triggerBeatPad(index: pad.id, screenPoint: CGPoint(x: padX, y: baseCenter.y + liveOffset.height + 52))
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
                        .scaleEffect(isBouncing ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: 176)
        .singleLayerGlassPlate(useNative: controller.useNativeSystemGlass, tintMode: controller.tintMode, cornerRadius: 30)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .position(x: baseCenter.x + liveOffset.width, y: baseCenter.y + liveOffset.height)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { val in
                    springState.onDragChanged(translation: val.translation, velocity: val.velocity) { newOffset in
                        controller.setCardSpringTarget(tab: .musicBeat, offset: newOffset)
                    }
                }
                .onEnded { val in
                    springState.onDragEnded(velocity: val.velocity, bounds: CGSize(width: 24, height: 220)) { newOffset, rv in
                        controller.setCardSpringTarget(tab: .musicBeat, offset: newOffset, releaseVelocity: rv)
                    }
                }
        )
        .onDisappear {
            springState.stopDisplayLink()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct AudioSpectrumBarsView: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { timeline in
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

// MARK: - Tab 3: Liquid Control Hub (Includes Droplet Haptic Resonance, Phone Flip & Live Activity Toggles)

struct MiniControlCenterOverlay: View {
    @Bindable var controller: GlassSceneController
    let cardWidth: CGFloat
    let baseCenter: CGPoint

    @State private var springState = VelocityCardSpringState()
    @State private var lastBrightnessBucket: Int = -1

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let liveOffset = springState.offset

        VStack(spacing: 8) {
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
                    icon: "iphone.gen3.radiowaves.left.and.right",
                    title: "翻轉啟動",
                    isActive: controller.flipToStartEnabled,
                    activeColor: DockTab.skyBlueAccent,
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.flipToStartEnabled.toggle()
                    HapticsManager.shared.selection()
                }

                controlTile(
                    icon: controller.engineMode.icon,
                    title: controller.engineMode == .nativeAppleGlass ? "原生玻璃" : "Metal光學",
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
                    title: "沙漏水滴共鳴微震 (Droplet Haptics)",
                    icon: "drop.transmission",
                    isOn: $controller.dropletHapticsEnabled,
                    primaryColor: primary
                )
                LiquidJellyToggle(
                    title: "全局系統動態島 (Live Activity)",
                    icon: "capsule.portrait.tophalf.filled",
                    isOn: $controller.liveActivityEnabled,
                    primaryColor: primary
                )
                LiquidJellyToggle(
                    title: "超亮光譜稜鏡邊緣 (Prism Rim)",
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
        .frame(width: cardWidth, height: 268)
        .singleLayerGlassPlate(useNative: controller.useNativeSystemGlass, tintMode: controller.tintMode, cornerRadius: 30)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .position(x: baseCenter.x + liveOffset.width, y: baseCenter.y + liveOffset.height)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { val in
                    springState.onDragChanged(translation: val.translation, velocity: val.velocity) { newOffset in
                        controller.setCardSpringTarget(tab: .controlHub, offset: newOffset)
                    }
                }
                .onEnded { val in
                    springState.onDragEnded(velocity: val.velocity, bounds: CGSize(width: 24, height: 210)) { newOffset, rv in
                        controller.setCardSpringTarget(tab: .controlHub, offset: newOffset, releaseVelocity: rv)
                    }
                }
        )
        .onDisappear {
            springState.stopDisplayLink()
        }
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

// MARK: - Tab 4: Optical Studio + iPhone 18 Pro Hardware Cutout Precision Calibration

struct StudioDrawerOverlay: View {
    @Bindable var controller: GlassSceneController
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let drawerWidth: CGFloat

    @State private var showCutoutCalibration: Bool = false

    var body: some View {
        let primary: Color = controller.tintMode == .light
            ? Color(red: 0.08, green: 0.11, blue: 0.18)
            : Color.white
        let secondary = primary.opacity(0.68)
        let pillBg = controller.tintMode == .light
            ? Color.black.opacity(0.08)
            : Color.white.opacity(0.14)

        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Label(
                    showCutoutCalibration ? "iPhone 18 Pro 挖孔校準" : "光學與材質工作坊",
                    systemImage: showCutoutCalibration ? "capsule.portrait.tophalf.filled" : "sparkles.rectangle.stack.fill"
                )
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(primary)
                .lineLimit(1)

                Spacer(minLength: 4)

                Button {
                    showCutoutCalibration.toggle()
                    HapticsManager.shared.selection()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 10, weight: .bold))
                        Text(showCutoutCalibration ? "返回光學" : "挖孔微調")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(showCutoutCalibration ? Color.black : primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(showCutoutCalibration ? DockTab.skyBlueAccent : pillBg, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    controller.engineMode = controller.engineMode.toggled()
                } label: {
                    Text(controller.engineMode.badgeLabel)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            controller.engineMode == .nativeAppleGlass ? Color.white : DockTab.skyBlueAccent,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                Button {
                    HapticsManager.shared.tapLight()
                    controller.selectedTab = .focusHourglass
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secondary)
                        .frame(width: 26, height: 26)
                        .background(pillBg, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // 4 Wallpapers + Photo Picker
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
                        .background(selected ? Color.white : pillBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
                    .background(selected ? DockTab.skyBlueAccent : pillBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // 3 Glass Material Tints + FPS Toggle
            HStack(spacing: 6) {
                ForEach(GlassTintMode.allCases) { mode in
                    let isSelected = controller.tintMode == mode
                    Button {
                        controller.tintMode = mode
                        HapticsManager.shared.selection()
                    } label: {
                        Text(mode.shortTitle)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.black : primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color(red: 0.56, green: 0.90, blue: 1.0) : pillBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    controller.showFPS.toggle()
                    HapticsManager.shared.selection()
                } label: {
                    Text("120Hz")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(controller.showFPS ? Color.black : primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(controller.showFPS ? DockTab.skyBlueAccent : pillBg, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if showCutoutCalibration {
                // iPhone 18 Pro Compact Dynamic Island Cutout Pixel-Alignment Sliders (#000000 Black Hole)
                VStack(spacing: 7) {
                    LiquidJellySlider(
                        title: "挖孔寬度",
                        value: $controller.islandWidthPt,
                        range: 64...128,
                        format: "%.0f pt",
                        primaryColor: primary,
                        secondaryColor: secondary
                    )
                    LiquidJellySlider(
                        title: "挖孔高度",
                        value: $controller.islandHeightPt,
                        range: 22...42,
                        format: "%.0f pt",
                        primaryColor: primary,
                        secondaryColor: secondary
                    )
                    LiquidJellySlider(
                        title: "頂部距離",
                        value: $controller.islandTopMarginPt,
                        range: 6...24,
                        format: "%.1f pt",
                        primaryColor: primary,
                        secondaryColor: secondary
                    )
                    HStack {
                        Text("預設對齊 iPhone 18 Pro 窄版純黑挖孔 (#000000)")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(secondary)
                        Spacer()
                        Button("重置 88×32") {
                            controller.islandWidthPt = 88.0
                            controller.islandHeightPt = 32.0
                            controller.islandTopMarginPt = 12.0
                            HapticsManager.shared.selection()
                        }
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(DockTab.skyBlueAccent)
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            } else {
                // 4 Optical Sliders — Scrubbing ANY slider auto-activates Custom Metal Optics!
                VStack(spacing: 6) {
                    LiquidJellySlider(
                        title: "折射強度",
                        value: $controller.refraction,
                        range: 0...95,
                        format: "%.0f",
                        primaryColor: primary,
                        secondaryColor: secondary,
                        onScrub: { controller.activateMetalOpticsIfNeeded() }
                    )
                    LiquidJellySlider(
                        title: "倒角寬度",
                        value: $controller.bezel,
                        range: 6...68,
                        format: "%.0f pt",
                        primaryColor: primary,
                        secondaryColor: secondary,
                        onScrub: { controller.activateMetalOpticsIfNeeded() }
                    )
                    LiquidJellySlider(
                        title: "彩虹色散",
                        value: $controller.dispersion,
                        range: 0...0.28,
                        format: "%.2f",
                        primaryColor: primary,
                        secondaryColor: secondary,
                        onScrub: { controller.activateMetalOpticsIfNeeded() }
                    )
                    LiquidJellySlider(
                        title: "霧面磨砂",
                        value: $controller.frost,
                        range: 0...4.0,
                        format: "%.1f",
                        primaryColor: primary,
                        secondaryColor: secondary,
                        onScrub: { controller.activateMetalOpticsIfNeeded() }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: drawerWidth, height: 388)
        .singleLayerGlassPlate(useNative: controller.useNativeSystemGlass, tintMode: controller.tintMode, cornerRadius: 30)
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
                .background(isPinned ? DockTab.skyBlueAccent : subtleFill, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
