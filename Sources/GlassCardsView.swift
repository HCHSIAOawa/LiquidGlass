import SwiftUI
import PhotosUI

// MARK: - Top Safe-Area HUD (Title Pill, Shape Pill & Live 120Hz FPS Monitor)

struct TopStatusHUD: View {
    let controller: GlassSceneController

    var body: some View {
        let isBright = controller.wallpaper.isBrightBackground
        let pillBg = isBright ? Color.black.opacity(0.68) : Color.black.opacity(0.36)

        HStack(spacing: 8) {
            // App Badge + Quick Lens Morph Button
            Button {
                controller.cycleLensShape()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: controller.lensShape.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text("LiquidGlass")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("· \(controller.lensShape.shortTitle)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(pillBg, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Spacer()

            // Gyro Indicator Pill
            Button {
                controller.gyroEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: controller.gyroEnabled ? "gyroscope" : "hand.point.up.left.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(controller.gyroEnabled ? Color.mint : Color.white.opacity(0.6))
                    Text(controller.gyroEnabled ? "陀螺儀" : "觸控光")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(pillBg, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            // Live 120Hz ProMotion FPS Monitor Badge
            if controller.showFPS {
                HStack(spacing: 5) {
                    Circle()
                        .fill(fpsStatusColor)
                        .frame(width: 6, height: 6)
                    Text("\(controller.currentFPS) FPS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(String(format: "%.1fms", controller.currentFrameMs))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.68))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(pillBg, in: Capsule())
                .overlay(Capsule().strokeBorder(fpsStatusColor.opacity(0.45), lineWidth: 0.8))
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
            return .cyan
        } else {
            return .orange
        }
    }
}

// MARK: - Dynamic Music Player Liquid Glass Card

struct MusicPlayerCardOverlay: View {
    let controller: GlassSceneController
    let cardWidth: CGFloat

    @State private var lastScrubBucket: Int = -1

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)
        let prominentFill = controller.tintMode.prominentFillColor(over: controller.wallpaper)
        let track = controller.currentTrack

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Animated Album Orb + Audio Spectrum Bars
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [track.accentPrimary, track.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: track.accentPrimary.opacity(0.45), radius: 8, y: 3)

                    AudioSpectrumBarsView(isPlaying: controller.isPlayingMusic)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                    }
                    Text(track.artist)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }

                // Playback Transport Buttons
                HStack(spacing: 6) {
                    Button {
                        controller.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 30, height: 30)
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Image(systemName: controller.isPlayingMusic ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(primary)
                            .frame(width: 34, height: 34)
                            .background(prominentFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(primary)
                            .frame(width: 30, height: 30)
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        HapticsManager.shared.tapLight()
                        controller.showMusicCard = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(secondary)
                            .frame(width: 24, height: 24)
                            .background(subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Interactive Progress Scrubber
            HStack(spacing: 8) {
                Text(formatTime(controller.trackProgress * track.duration))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondary)
                    .frame(width: 32, alignment: .leading)

                GeometryReader { barGeo in
                    let fullW = max(1, barGeo.size.width)
                    let prog = min(max(controller.trackProgress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(subtleFill)
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [track.accentPrimary, track.accentSecondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, fullW * prog), height: 6)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let next = min(max(Double(val.location.x / fullW), 0.0), 0.999)
                                controller.trackProgress = next
                                HapticsManager.shared.sliderTick(
                                    normalized: next,
                                    buckets: 20,
                                    lastBucket: &lastScrubBucket
                                )
                            }
                            .onEnded { _ in
                                lastScrubBucket = -1
                            }
                    )
                }
                .frame(height: 16)

                Text("-\(formatTime((1.0 - controller.trackProgress) * track.duration))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: 114)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("screen"))
                .onChanged { value in
                    controller.updateMusicCardDrag(translation: value.translation, velocity: value.velocity)
                }
                .onEnded { value in
                    controller.endMusicCardDrag(velocity: value.velocity)
                }
        )
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Self-contained 30Hz audio spectrum leaf view so animated bars never invalidate parent layout.
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
                        .fill(.white.opacity(0.95))
                        .frame(width: 3.5, height: CGFloat(8.0 + 16.0 * level))
                }
            }
        }
    }
}

// MARK: - Mini Control Center Liquid Glass Card

struct MiniControlCenterOverlay: View {
    let controller: GlassSceneController
    let cardWidth: CGFloat

    @State private var lastBrightnessBucket: Int = -1

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let secondary = controller.tintMode.secondaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)

        VStack(spacing: 12) {
            // Header Drag Handle + Title + Collapse
            HStack {
                Label("迷你控制中心", systemImage: "switch.2")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)
                Spacer()
                Text("可拖曳")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(secondary)
                Button {
                    HapticsManager.shared.tapLight()
                    controller.showControlCenter = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(secondary)
                        .frame(width: 24, height: 24)
                        .background(subtleFill, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // 4 Interactive Control Tiles
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
                    icon: controller.frost > 1.2 ? "aqi.medium" : "drop.halffull",
                    title: controller.frost > 1.2 ? "柔霧" : "清透",
                    isActive: controller.frost > 1.2,
                    activeColor: Color(red: 0.36, green: 0.68, blue: 1.0),
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.frost = controller.frost > 1.2 ? 0.25 : 2.10
                    HapticsManager.shared.selection()
                }

                controlTile(
                    icon: "iphone.radiowaves.left.and.right",
                    title: "觸覺",
                    isActive: controller.hapticsEnabled,
                    activeColor: Color(red: 0.96, green: 0.36, blue: 0.62),
                    primary: primary,
                    subtleFill: subtleFill
                ) {
                    controller.hapticsEnabled.toggle()
                }
            }

            // Apple Control-Center-Style Glowing Capsule Brightness Slider
            GeometryReader { geo in
                let fullW = max(1, geo.size.width)
                let minB = 0.45
                let maxB = 1.30
                let norm = min(max((controller.sceneBrightness - minB) / (maxB - minB), 0.0), 1.0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(subtleFill)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color(red: 1.0, green: 0.92, blue: 0.68).opacity(0.68)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(36, fullW * norm))

                    HStack {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(primary)
                        Text("環境輝度")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(primary)
                        Spacer()
                        Text("\(Int((controller.sceneBrightness * 100).rounded()))%")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
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
                            HapticsManager.shared.sliderTick(
                                normalized: ratio,
                                buckets: 16,
                                lastBucket: &lastBrightnessBucket
                            )
                        }
                        .onEnded { _ in
                            lastBrightnessBucket = -1
                        }
                )
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: 168)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("screen"))
                .onChanged { value in
                    controller.updateControlCardDrag(translation: value.translation, velocity: value.velocity)
                }
                .onEnded { value in
                    controller.endControlCardDrag(velocity: value.velocity)
                }
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
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isActive ? Color(red: 0.06, green: 0.08, blue: 0.14) : primary)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? Color(red: 0.06, green: 0.08, blue: 0.14) : primary.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? activeColor : subtleFill)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collapsible Optical & Wallpaper Studio Drawer

struct StudioDrawerOverlay: View {
    @Bindable var controller: GlassSceneController
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let drawerWidth: CGFloat

    @State private var refBucket: Int = -1
    @State private var bezBucket: Int = -1
    @State private var dispBucket: Int = -1
    @State private var frostBucket: Int = -1

    var body: some View {
        let primary: Color = controller.tintMode == .light
            ? Color(red: 0.08, green: 0.11, blue: 0.18)
            : Color.white
        let secondary = primary.opacity(0.68)
        let pillBg = controller.tintMode == .light
            ? Color.black.opacity(0.08)
            : Color.white.opacity(0.14)

        VStack(spacing: 11) {
            // Header Row
            HStack {
                Label("光學與材質工作坊", systemImage: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(primary)

                Spacer()

                Button {
                    controller.showFPS.toggle()
                    HapticsManager.shared.selection()
                } label: {
                    Text("120Hz 指標")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(controller.showFPS ? Color.black : primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            controller.showFPS ? Color.cyan : pillBg,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                Button {
                    HapticsManager.shared.tapLight()
                    controller.showSettingsDrawer = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secondary)
                        .frame(width: 26, height: 26)
                        .background(pillBg, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // 4 Wallpapers + Photo Library Picker
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

            // 3 Glass Material Tints + Optional Photo Typography Toggle
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
                            .background(
                                controller.showTypographyOnPhoto ? Color.white : pillBg,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 4 Optical Parameter Sliders with Haptic Detents
            VStack(spacing: 7) {
                opticalSliderRow(
                    title: "折射強度",
                    value: $controller.refraction,
                    range: 0...95,
                    format: "%.0f",
                    primary: primary,
                    secondary: secondary,
                    bucket: $refBucket
                )
                opticalSliderRow(
                    title: "倒角寬度",
                    value: $controller.bezel,
                    range: 6...68,
                    format: "%.0f pt",
                    primary: primary,
                    secondary: secondary,
                    bucket: $bezBucket
                )
                opticalSliderRow(
                    title: "彩虹色散",
                    value: $controller.dispersion,
                    range: 0...0.28,
                    format: "%.2f",
                    primary: primary,
                    secondary: secondary,
                    bucket: $dispBucket
                )
                opticalSliderRow(
                    title: "霧面磨砂",
                    value: $controller.frost,
                    range: 0...4.0,
                    format: "%.1f",
                    primary: primary,
                    secondary: secondary,
                    bucket: $frostBucket
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: drawerWidth, height: 352)
    }

    private func opticalSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        primary: Color,
        secondary: Color,
        bucket: Binding<Int>
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(primary.opacity(0.9))
                .frame(width: 54, alignment: .leading)

            Slider(value: value, in: range)
                .tint(.cyan)
                .onChange(of: value.wrappedValue) { _, newVal in
                    let norm = (newVal - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
                    var b = bucket.wrappedValue
                    HapticsManager.shared.sliderTick(normalized: norm, buckets: 18, lastBucket: &b)
                    bucket.wrappedValue = b
                }

            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

// MARK: - Bottom Floating Liquid Dock

struct FloatingLiquidDockOverlay: View {
    let controller: GlassSceneController
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let dockWidth: CGFloat

    var body: some View {
        let primary = controller.tintMode.primaryTextColor(over: controller.wallpaper)
        let subtleFill = controller.tintMode.subtleFillColor(over: controller.wallpaper)

        HStack(spacing: 0) {
            dockButton(
                icon: "music.note",
                label: "音樂卡",
                isActive: controller.showMusicCard,
                primary: primary,
                subtleFill: subtleFill
            ) {
                HapticsManager.shared.tapMedium()
                controller.showMusicCard.toggle()
            }

            Spacer(minLength: 4)

            dockButton(
                icon: "switch.2",
                label: "控制中心",
                isActive: controller.showControlCenter,
                primary: primary,
                subtleFill: subtleFill
            ) {
                HapticsManager.shared.tapMedium()
                controller.showControlCenter.toggle()
            }

            Spacer(minLength: 4)

            dockButton(
                icon: "slider.horizontal.3",
                label: "光學面板",
                isActive: controller.showSettingsDrawer,
                primary: primary,
                subtleFill: subtleFill
            ) {
                HapticsManager.shared.tapMedium()
                controller.showSettingsDrawer.toggle()
            }

            Spacer(minLength: 4)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                dockItemLabel(
                    icon: "photo.on.rectangle.angled",
                    label: "匯入相片",
                    isActive: controller.wallpaper == .customPhoto,
                    primary: primary,
                    subtleFill: subtleFill
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            dockButton(
                icon: "arrow.counterclockwise",
                label: "重置透鏡",
                isActive: false,
                primary: primary,
                subtleFill: subtleFill
            ) {
                controller.resetPlaygroundLayout()
            }
        }
        .padding(.horizontal, 14)
        .frame(width: dockWidth, height: 68)
    }

    private func dockButton(
        icon: String,
        label: String,
        isActive: Bool,
        primary: Color,
        subtleFill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            dockItemLabel(
                icon: icon,
                label: label,
                isActive: isActive,
                primary: primary,
                subtleFill: subtleFill
            )
        }
        .buttonStyle(.plain)
    }

    private func dockItemLabel(
        icon: String,
        label: String,
        isActive: Bool,
        primary: Color,
        subtleFill: Color
    ) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? Color.cyan.opacity(0.32) : subtleFill)
                    .frame(width: 44, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(primary)
            }
            Circle()
                .fill(isActive ? Color.cyan : Color.clear)
                .frame(width: 4.5, height: 4.5)
        }
        .accessibilityLabel(label)
    }
}
