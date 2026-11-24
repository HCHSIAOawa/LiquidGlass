import SwiftUI
import UIKit
import QuartzCore
import Observation
import ActivityKit
import simd

@MainActor
@Observable
final class GlassSceneController {
    // MARK: - Dual Engine Mode (iOS 27 Native Compositor vs Custom Metal Optics)

    var engineMode: GlassEngineMode = .nativeAppleGlass {
        didSet {
            HapticsManager.shared.selection()
            syncLiveActivityIfNeeded()
        }
    }

    var isNativeCompositorSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    /// True when UI chrome & cards should be rendered by Apple's native `.glassEffect()` compositor.
    var useNativeSystemGlass: Bool {
        engineMode == .nativeAppleGlass && isNativeCompositorSupported
    }

    // MARK: - Active Bottom Tab & Pinning States

    var selectedTab: DockTab = .lensLab
    var pinnedMusic: Bool = false
    var pinnedControl: Bool = false
    var pinnedWeather: Bool = false

    // MARK: - Dynamic Island Hardware Vault & Swallow States

    var isDropletSwallowedByIsland: Bool = false
    var isVaultedInIsland: Bool = false
    private var savedVaultState: (tab: DockTab, music: Bool, control: Bool, weather: Bool)?

    var liveActivityEnabled: Bool = false {
        didSet {
            if liveActivityEnabled != oldValue {
                handleLiveActivityToggle(enabled: liveActivityEnabled)
            }
        }
    }

    // MARK: - Optical, Atmosphere & Physics Toggles

    var wallpaper: WallpaperPreset = .aurora {
        didSet { syncLiveActivityIfNeeded() }
    }
    var tintMode: GlassTintMode = .clear
    var lensShape: LensShapeMode = .circle

    var refraction: Double = 50.0
    var bezel: Double = 34.0
    var dispersion: Double = 0.14
    var frost: Double = 0.42

    var dualDropletEnabled: Bool = true {
        didSet { HapticsManager.shared.tapMedium() }
    }
    var metaballFusionEnabled: Bool = true
    var gravityModeEnabled: Bool = false {
        didSet {
            if gravityModeEnabled && !gyroEnabled {
                gyroEnabled = true
            }
            HapticsManager.shared.selection()
        }
    }
    var touchRipplesEnabled: Bool = true
    var prismRimBoostEnabled: Bool = false

    var gyroEnabled: Bool = true {
        didSet {
            motionManager.setEnabled(gyroEnabled)
            HapticsManager.shared.selection()
        }
    }

    var hapticsEnabled: Bool = true {
        didSet {
            HapticsManager.shared.isEnabled = hapticsEnabled
            if hapticsEnabled { HapticsManager.shared.selection() }
        }
    }

    var showFPS: Bool = true
    var showTypographyOnPhoto: Bool = false
    var showGestureHint: Bool = true

    // MARK: - Control Hub & Spatial Weather States

    var flashlightOn: Bool = false
    var sceneBrightness: Double = 1.0

    var weatherCondition: WeatherCondition = .sunny
    var solarHour: Double = 16.5

    // MARK: - Music & Beat Pad States

    var isPlayingMusic: Bool = true {
        didSet { syncLiveActivityIfNeeded() }
    }
    var currentTrackIndex: Int = 0 {
        didSet { syncLiveActivityIfNeeded() }
    }
    var trackProgress: Double = 0.28
    var totalRippleCount: Int = 0

    var currentTrack: MusicTrack {
        MusicTrack.catalog[currentTrackIndex % MusicTrack.catalog.count]
    }

    // Computed visibility per interactive zone (respects Dynamic Island Vault!)
    var isLensLabBarVisible: Bool { !isVaultedInIsland && selectedTab == .lensLab }
    var isMusicVisible: Bool { !isVaultedInIsland && (selectedTab == .musicBeat || pinnedMusic) }
    var isControlVisible: Bool { !isVaultedInIsland && (selectedTab == .controlHub || pinnedControl) }
    var isWeatherVisible: Bool { !isVaultedInIsland && (selectedTab == .weatherSolar || pinnedWeather) }
    var isStudioVisible: Bool { !isVaultedInIsland && selectedTab == .opticalStudio }

    // MARK: - Spring Reveal Progress (0...1)

    private(set) var labBarReveal: CGFloat = 1.0
    private(set) var musicReveal: CGFloat = 0.0
    private(set) var controlReveal: CGFloat = 0.0
    private(set) var weatherReveal: CGFloat = 0.0
    private(set) var drawerReveal: CGFloat = 0.0
    private(set) var companionReveal: CGFloat = 1.0

    // MARK: - Live Positioned Geometry

    private(set) var hardwareIslandCenter: CGPoint = CGPoint(x: 196, y: 29)
    private(set) var islandPullProgress: CGFloat = 0.0

    private(set) var lensPosition: CGPoint = CGPoint(x: 162, y: 440)
    private(set) var lensHalfSize: CGSize = CGSize(width: 88, height: 88)
    private(set) var lensCornerRadius: CGFloat = 88

    private(set) var companionPosition: CGPoint = CGPoint(x: 258, y: 515)
    private(set) var companionRadius: CGFloat = 54

    private(set) var musicCardCenter: CGPoint = CGPoint(x: 196, y: 198)
    private(set) var controlCardCenter: CGPoint = CGPoint(x: 196, y: 224)
    private(set) var weatherCardCenter: CGPoint = CGPoint(x: 196, y: 210)

    private(set) var dockThumbScreenPos: CGPoint = CGPoint(x: 80, y: 780)
    private(set) var dockThumbLiftValue: CGFloat = 0.0
    private(set) var isScrubbingDock: Bool = false
    private(set) var isPullingUpToPin: Bool = false

    private(set) var currentFPS: Int = 120
    private(set) var currentFrameMs: Double = 8.3

    var hasCustomPhoto: Bool = false

    // MARK: - Observation-Ignored 120Hz Physics & GPU Buffers

    @ObservationIgnored var sceneUniforms = SceneUniforms()
    @ObservationIgnored var elementUniforms = [GlassElementUniform](repeating: GlassElementUniform(), count: 12)

    @ObservationIgnored var customPhotoImage: UIImage?
    @ObservationIgnored var customPhotoRevision: Int = 0
    @ObservationIgnored var customPhotoAspect: Float = 0.75

    @ObservationIgnored private let motionManager = MotionManager()
    @ObservationIgnored private var intentObserver: NSObjectProtocol?

    @ObservationIgnored private var hasInitializedLayout: Bool = false
    @ObservationIgnored private var safeTopInset: CGFloat = 59
    @ObservationIgnored private var safeBottomInset: CGFloat = 34
    @ObservationIgnored private var viewportSize: CGSize = CGSize(width: 393, height: 852)

    // Hero Lens & Island Swallow physics
    @ObservationIgnored private var isDraggingLens: Bool = false
    @ObservationIgnored private var lensDragStart: CGPoint = .zero
    @ObservationIgnored private var lensVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var lensZoomScale: Float = 1.0
    @ObservationIgnored private var pinchStartScale: Float = 1.0

    @ObservationIgnored private var animHalfSize = SIMD2<Float>(88, 88)
    @ObservationIgnored private var animHalfSizeVel = SIMD2<Float>(0, 0)
    @ObservationIgnored private var animCornerRadius: Float = 88
    @ObservationIgnored private var animCornerVel: Float = 0

    @ObservationIgnored private var lensLiftScale: Float = 1.0
    @ObservationIgnored private var lensLiftVel: Float = 0.0
    @ObservationIgnored private var lensStretchFactor: Float = 1.0
    @ObservationIgnored private var lensStretchVel: Float = 0.0
    @ObservationIgnored private var lensStretchAngle: Float = 0.0
    @ObservationIgnored private var heroVisibilityScale: Float = 1.0
    @ObservationIgnored private var heroVisibilityVel: Float = 0.0

    // Dynamic Island halo & tether physics
    @ObservationIgnored private var islandHaloScale: Float = 0.15
    @ObservationIgnored private var islandHaloVel: Float = 0.0
    @ObservationIgnored private var islandPullStretchPt: Float = 0.0
    @ObservationIgnored private var hasFiredIslandSpitThisGesture: Bool = false
    @ObservationIgnored private var nextIslandSpitIndex: Int = 0

    // Companion Droplet physics
    @ObservationIgnored private var isDraggingCompanion: Bool = false
    @ObservationIgnored private var companionDragStart: CGPoint = .zero
    @ObservationIgnored private var companionVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var companionLiftScale: Float = 1.0
    @ObservationIgnored private var companionLiftVel: Float = 0.0
    @ObservationIgnored private var companionStretchFactor: Float = 1.0
    @ObservationIgnored private var companionStretchVel: Float = 0.0
    @ObservationIgnored private var companionStretchAngle: Float = 0.0
    @ObservationIgnored private var companionRevealVel: Float = 0.0
    @ObservationIgnored private var wasDropletsFused: Bool = true

    // Sliding Dock Crystal Jelly Magnifier physics
    @ObservationIgnored private var dockThumbPos = SIMD2<Float>(80, 780)
    @ObservationIgnored private var dockThumbVel = SIMD2<Float>(0, 0)
    @ObservationIgnored private var dockThumbTarget = SIMD2<Float>(80, 780)
    @ObservationIgnored private var dockThumbLift: Float = 0.0
    @ObservationIgnored private var dockThumbLiftVel: Float = 0.0
    @ObservationIgnored private var dockThumbStretch: Float = 1.0
    @ObservationIgnored private var dockThumbStretchVel: Float = 0.0
    @ObservationIgnored private var dockScrubStartTab: DockTab = .lensLab

    // Card reveal velocities & draggable card physics
    @ObservationIgnored private var labBarRevealVel: Float = 0
    @ObservationIgnored private var musicRevealVel: Float = 0
    @ObservationIgnored private var controlRevealVel: Float = 0
    @ObservationIgnored private var weatherRevealVel: Float = 0
    @ObservationIgnored private var drawerRevealVel: Float = 0

    @ObservationIgnored private var musicOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var musicDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var musicVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var isDraggingMusic: Bool = false

    @ObservationIgnored private var controlOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var controlDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var controlVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var isDraggingControl: Bool = false

    @ObservationIgnored private var weatherOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var weatherDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var weatherVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var isDraggingWeather: Bool = false

    // Shockwave ripple & lighting state
    @ObservationIgnored private var rippleCenter = SIMD2<Float>(196, 420)
    @ObservationIgnored private var rippleRadius: Float = 0.0
    @ObservationIgnored private var rippleStrength: Float = 0.0
    @ObservationIgnored private var spotlightAnim: Float = 0.0
    @ObservationIgnored private var currentLightDir = SIMD2<Float>(-0.58, -0.81)
    @ObservationIgnored private var touchLightPos: SIMD2<Float>?

    @ObservationIgnored private var startTime: CFTimeInterval = CACurrentMediaTime()
    @ObservationIgnored private var lastStepTime: CFTimeInterval = 0
    @ObservationIgnored private var fpsFrameCount: Int = 0
    @ObservationIgnored private var fpsAccumDuration: CFTimeInterval = 0
    @ObservationIgnored private var audioProgressAccum: Double = 0

    init() {
        motionManager.setEnabled(true)
        observeLiveActivityIntents()
        liveActivityEnabled = !Activity<LiquidGlassActivityAttributes>.activities.isEmpty
    }

    // MARK: - Dynamic Island & Dock Geometry Calibration

    func dockWidth(for screenWidth: CGFloat) -> CGFloat {
        min(screenWidth - 24.0, 362.0)
    }

    func dockCenterY(for screenHeight: CGFloat, safeBottom: CGFloat) -> CGFloat {
        screenHeight - safeBottom - 38.0
    }

    func dockSlotScreenX(index: Int, screenWidth: CGFloat) -> CGFloat {
        let dWidth = dockWidth(for: screenWidth)
        let innerLeft = (screenWidth - dWidth) * 0.5 + 8.0
        let slotW = (dWidth - 16.0) / CGFloat(DockTab.allCases.count)
        return innerLeft + slotW * (CGFloat(index) + 0.5)
    }

    func updateGeometry(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        guard size.width > 40, size.height > 40 else { return }
        viewportSize = size
        safeTopInset = safeTop
        safeBottomInset = safeBottom

        // Calibrate exact hardware Dynamic Island pill center from top safe area inset
        let islandY: CGFloat = safeTop >= 48 ? max(25.0, safeTop * 0.49) : 26.0
        hardwareIslandCenter = CGPoint(x: size.width * 0.5, y: islandY)

        if !hasInitializedLayout {
            hasInitializedLayout = true
            lensPosition = CGPoint(x: size.width * 0.41, y: size.height * 0.51)
            companionPosition = CGPoint(x: size.width * 0.64, y: size.height * 0.58)
            musicCardCenter = CGPoint(x: size.width * 0.5, y: safeTop + 158)
            controlCardCenter = CGPoint(x: size.width * 0.5, y: safeTop + 190)
            weatherCardCenter = CGPoint(x: size.width * 0.5, y: safeTop + 174)

            let slotX = Float(dockSlotScreenX(index: selectedTab.rawValue, screenWidth: size.width))
            let dockY = Float(dockCenterY(for: size.height, safeBottom: safeBottom))
            dockThumbPos = SIMD2<Float>(slotX, dockY)
            dockThumbTarget = dockThumbPos
            dockThumbScreenPos = CGPoint(x: CGFloat(slotX), y: CGFloat(dockY))
        }
    }

    // MARK: - In-App Hardware Dynamic Island Gestures (Vault, Swallow & Pull-Down Spit)

    func toggleIslandCardVault() {
        if isVaultedInIsland {
            isVaultedInIsland = false
            if let saved = savedVaultState {
                selectedTab = saved.tab
                pinnedMusic = saved.music
                pinnedControl = saved.control
                pinnedWeather = saved.weather
            }
            if isDropletSwallowedByIsland {
                spitDropletFromIsland()
            } else {
                HapticsManager.shared.playLiquidSnap()
            }
            islandHaloVel += 4.2
            triggerRipple(at: hardwareIslandCenter, strength: 0.92)
        } else {
            let hasOpenCards = isMusicVisible || isControlVisible || isWeatherVisible || isStudioVisible
            if hasOpenCards {
                savedVaultState = (selectedTab, pinnedMusic, pinnedControl, pinnedWeather)
                isVaultedInIsland = true
                islandHaloVel += 4.5
                HapticsManager.shared.playIslandSwallow()
                triggerRipple(at: hardwareIslandCenter, strength: 0.85)
            } else if isDropletSwallowedByIsland {
                spitDropletFromIsland()
            } else {
                // Swallow Hero Droplet on tap if no cards are open, or pulse island!
                swallowDropletIntoIsland()
            }
        }
    }

    func swallowDropletIntoIsland() {
        isDropletSwallowedByIsland = true
        lensVelocity = .zero
        lensPosition = hardwareIslandCenter
        islandHaloVel += 5.2
        triggerRipple(at: hardwareIslandCenter, strength: 0.95)
        HapticsManager.shared.playIslandSwallow()
    }

    func spitDropletFromIsland() {
        isDropletSwallowedByIsland = false
        lensPosition = CGPoint(x: hardwareIslandCenter.x, y: hardwareIslandCenter.y + 62)
        lensVelocity = SIMD2<Float>(Float.random(in: -85...85), 560.0)
        lensStretchAngle = .pi * 0.5
        lensStretchVel += 3.8
        islandHaloVel -= 3.2
        triggerRipple(at: CGPoint(x: hardwareIslandCenter.x, y: hardwareIslandCenter.y + 38), strength: 0.95)
        HapticsManager.shared.playLiquidSnap()
    }

    func updateIslandPullDown(translationY: CGFloat) {
        let pull = max(0.0, min(92.0, translationY))
        islandPullStretchPt = Float(pull)
        islandPullProgress = pull / 68.0

        if pull >= 68.0 && !hasFiredIslandSpitThisGesture {
            hasFiredIslandSpitThisGesture = true
            islandPullStretchPt = 0.0
            islandPullProgress = 0.0

            if isVaultedInIsland {
                toggleIslandCardVault()
            } else if isDropletSwallowedByIsland {
                spitDropletFromIsland()
            } else {
                // Spit out & pin the next interactive Liquid Glass Card from Dynamic Island!
                let cycle: [DockTab] = [.musicBeat, .controlHub, .weatherSolar]
                let target = cycle[nextIslandSpitIndex % cycle.count]
                nextIslandSpitIndex += 1
                selectedTab = target
                switch target {
                case .musicBeat:
                    pinnedMusic = true
                    musicOffset = .zero
                    musicVelocity = SIMD2<Float>(0, 340)
                case .controlHub:
                    pinnedControl = true
                    controlOffset = .zero
                    controlVelocity = SIMD2<Float>(0, 340)
                case .weatherSolar:
                    pinnedWeather = true
                    weatherOffset = .zero
                    weatherVelocity = SIMD2<Float>(0, 340)
                default:
                    break
                }
                triggerRipple(at: CGPoint(x: hardwareIslandCenter.x, y: hardwareIslandCenter.y + 42), strength: 0.92)
                HapticsManager.shared.playLiquidSnap()
            }
        }
    }

    func endIslandPullDown() {
        islandPullStretchPt = 0.0
        islandPullProgress = 0.0
        hasFiredIslandSpitThisGesture = false
    }

    // MARK: - System Live Activity (ActivityKit — Zero App Groups)

    private func handleLiveActivityToggle(enabled: Bool) {
        if enabled {
            startOrUpdateLiveActivity()
            HapticsManager.shared.success()
        } else {
            Task { @MainActor in
                for activity in Activity<LiquidGlassActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            HapticsManager.shared.selection()
        }
    }

    func syncLiveActivityIfNeeded() {
        guard liveActivityEnabled else { return }
        let state = makeCurrentActivityState()
        Task { @MainActor in
            let existing = Activity<LiquidGlassActivityAttributes>.activities
            if existing.isEmpty {
                let attrs = LiquidGlassActivityAttributes(sessionTitle: "LiquidGlass ProMotion")
                _ = try? Activity.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                for activity in existing {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                }
            }
        }
    }

    private func startOrUpdateLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivityEnabled = false
            return
        }
        syncLiveActivityIfNeeded()
    }

    private func makeCurrentActivityState() -> LiquidGlassActivityAttributes.ContentState {
        LiquidGlassActivityAttributes.ContentState(
            engineName: engineMode.badgeLabel,
            wallpaperTitle: wallpaper.title,
            wallpaperIndex: wallpaper.rawValue,
            trackTitle: currentTrack.title,
            trackArtist: currentTrack.artist,
            isPlaying: isPlayingMusic,
            solarHour: Int(solarHour.rounded()) % 24,
            rippleCount: totalRippleCount
        )
    }

    private func observeLiveActivityIntents() {
        intentObserver = NotificationCenter.default.addObserver(
            forName: .liquidGlassIntentCommand,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let action = note.userInfo?["action"] as? String
            let wpIdx = note.userInfo?["wallpaperIndex"] as? Int
            let playing = note.userInfo?["isPlaying"] as? Bool
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch action {
                case "togglePlay":
                    if let playing { self.isPlayingMusic = playing } else { self.isPlayingMusic.toggle() }
                    HapticsManager.shared.selection()
                case "cycleWallpaper":
                    if let wpIdx, let preset = WallpaperPreset(rawValue: wpIdx) {
                        self.wallpaper = preset
                        HapticsManager.shared.selection()
                    }
                case "triggerRipple":
                    self.triggerRipple(at: self.hardwareIslandCenter, strength: 1.0)
                    HapticsManager.shared.playLiquidSnap()
                default:
                    break
                }
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "liquidglass" else { return }
        triggerRipple(at: hardwareIslandCenter, strength: 0.95)
        islandHaloVel += 3.6
        HapticsManager.shared.tapMedium()
    }

    // MARK: - Native Sliding Jelly Magnifier Dock Gestures

    func updateDockScrub(localLocation: CGPoint, velocityX: CGFloat) {
        if isVaultedInIsland { isVaultedInIsland = false }

        let dWidth = dockWidth(for: viewportSize.width)
        let dockLeft = (viewportSize.width - dWidth) * 0.5
        let dockY = dockCenterY(for: viewportSize.height, safeBottom: safeBottomInset)

        if !isScrubbingDock {
            isScrubbingDock = true
            dockScrubStartTab = selectedTab
            HapticsManager.shared.tapSoft(intensity: 0.65)
        }

        let minLocalX: CGFloat = 34.0
        let maxLocalX: CGFloat = dWidth - 34.0
        var clampedLocalX = localLocation.x
        if clampedLocalX < minLocalX {
            clampedLocalX = minLocalX + (clampedLocalX - minLocalX) * 0.28
        } else if clampedLocalX > maxLocalX {
            clampedLocalX = maxLocalX + (clampedLocalX - maxLocalX) * 0.28
        }

        let relY = localLocation.y - 34.0
        let rubberY = max(-26.0, min(10.0, relY * 0.34))

        dockThumbTarget = SIMD2<Float>(Float(dockLeft + clampedLocalX), Float(dockY + rubberY))

        let speedX = Float(abs(velocityX))
        let desiredStretch = 1.0 + min(0.46, speedX / 1350.0)
        if desiredStretch > dockThumbStretch {
            dockThumbStretch += (desiredStretch - dockThumbStretch) * 0.35
        }

        let slotCount = DockTab.allCases.count
        let slotW = (dWidth - 16.0) / CGFloat(slotCount)
        let rawIndex = Int(((localLocation.x - 8.0) / max(1.0, slotW)).rounded(.down))
        let clampedIndex = min(slotCount - 1, max(0, rawIndex))
        let hoveredTab = DockTab.allCases[clampedIndex]

        if hoveredTab != selectedTab {
            selectedTab = hoveredTab
            dockThumbStretchVel += 1.8
            HapticsManager.shared.selection()
        }

        let pullingUp = (relY < -48.0) && hoveredTab.supportsPinning
        if pullingUp != isPullingUpToPin {
            isPullingUpToPin = pullingUp
            if pullingUp {
                HapticsManager.shared.tapMedium(intensity: 0.85)
            }
        }
    }

    func endDockScrub(wasTap: Bool = false) {
        if isPullingUpToPin {
            togglePin(for: selectedTab)
            triggerRipple(at: CGPoint(x: dockThumbScreenPos.x, y: dockThumbScreenPos.y - 24), strength: 0.85)
        } else if wasTap && selectedTab == dockScrubStartTab && selectedTab != .lensLab {
            selectedTab = .lensLab
            HapticsManager.shared.selection()
        }
        isScrubbingDock = false
        isPullingUpToPin = false
        dockThumbStretchVel -= 2.2
        HapticsManager.shared.tapLight(intensity: 0.50)
    }

    func togglePin(for tab: DockTab) {
        switch tab {
        case .musicBeat:
            pinnedMusic.toggle()
            HapticsManager.shared.playLiquidSnap()
        case .controlHub:
            pinnedControl.toggle()
            HapticsManager.shared.playLiquidSnap()
        case .weatherSolar:
            pinnedWeather.toggle()
            HapticsManager.shared.playLiquidSnap()
        case .lensLab, .opticalStudio:
            break
        }
    }

    // MARK: - Ripples & Droplet Gestures

    func triggerRipple(at point: CGPoint, strength: Float = 0.80) {
        guard touchRipplesEnabled else { return }
        rippleCenter = SIMD2<Float>(Float(point.x), Float(point.y))
        rippleRadius = 8.0
        rippleStrength = min(1.0, max(0.25, strength))
        totalRippleCount += 1
        if liveActivityEnabled && totalRippleCount % 3 == 0 {
            syncLiveActivityIfNeeded()
        }
    }

    func triggerBeatPad(index: Int, screenPoint: CGPoint) {
        triggerRipple(at: screenPoint, strength: 0.92)
        islandHaloVel += 3.6
        lensLiftVel += 2.2
        companionLiftVel += 2.6
        HapticsManager.shared.playLiquidSnap()
    }

    func updateLensDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if isDropletSwallowedByIsland {
            isDropletSwallowedByIsland = false
        }
        if !isDraggingLens {
            isDraggingLens = true
            lensDragStart = lensPosition
            lensVelocity = .zero
            showGestureHint = false
            HapticsManager.shared.tapSoft(intensity: 0.55)
        }
        var targetX = lensDragStart.x + translation.width
        var targetY = lensDragStart.y + translation.height

        // Magnetic attraction toward Hardware Dynamic Island when dragged near top cutout!
        let distToIsland = hypot(targetX - hardwareIslandCenter.x, targetY - hardwareIslandCenter.y)
        if distToIsland < 118.0 {
            let pullFactor = (1.0 - distToIsland / 118.0) * 0.42
            targetX += (hardwareIslandCenter.x - targetX) * pullFactor
            targetY += (hardwareIslandCenter.y - targetY) * pullFactor
        } else {
            let minX = lensHalfSize.width * 0.85 + 8
            let maxX = viewportSize.width - lensHalfSize.width * 0.85 - 8
            let maxY = viewportSize.height - safeBottomInset - 82 - lensHalfSize.height * 0.85
            if targetX < minX { targetX = minX + (targetX - minX) * 0.32 }
            if targetX > maxX { targetX = maxX + (targetX - maxX) * 0.32 }
            if targetY > maxY { targetY = maxY + (targetY - maxY) * 0.32 }
        }

        lensPosition = CGPoint(x: targetX, y: targetY)
        lensVelocity = lensVelocity * 0.35 + SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.65
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endLensDrag(velocity: CGSize) {
        isDraggingLens = false
        touchLightPos = nil

        // Swallow into Hardware Dynamic Island if released inside magnetic capture zone!
        let distToIsland = hypot(lensPosition.x - hardwareIslandCenter.x, lensPosition.y - hardwareIslandCenter.y)
        if distToIsland < 62.0 {
            swallowDropletIntoIsland()
            return
        }

        lensVelocity = clampVelocity(velocity, maxSpeed: 2600.0)
    }

    func updateCompanionDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if !isDraggingCompanion {
            isDraggingCompanion = true
            companionDragStart = companionPosition
            companionVelocity = .zero
            showGestureHint = false
            HapticsManager.shared.tapSoft(intensity: 0.50)
        }
        companionPosition = CGPoint(
            x: companionDragStart.x + translation.width,
            y: companionDragStart.y + translation.height
        )
        companionVelocity = companionVelocity * 0.35 + SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.65
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endCompanionDrag(velocity: CGSize) {
        isDraggingCompanion = false
        touchLightPos = nil
        companionVelocity = clampVelocity(velocity, maxSpeed: 2600.0)
    }

    private func clampVelocity(_ velocity: CGSize, maxSpeed: Float) -> SIMD2<Float> {
        var v = SIMD2<Float>(Float(velocity.width), Float(velocity.height))
        let speed = simd_length(v)
        if speed > maxSpeed { v = (v / speed) * maxSpeed }
        return v
    }

    func updateLensPinch(magnification: CGFloat) {
        showGestureHint = false
        lensZoomScale = min(max(pinchStartScale * Float(magnification), 0.58), 1.82)
    }

    func endLensPinch() {
        pinchStartScale = lensZoomScale
        HapticsManager.shared.tapLight(intensity: 0.45)
    }

    func cycleLensShape() {
        if isDropletSwallowedByIsland {
            spitDropletFromIsland()
            return
        }
        showGestureHint = false
        lensShape = lensShape.next()
        lensLiftVel += 3.4
        lensStretchVel += 2.2
        triggerRipple(at: lensPosition, strength: 0.72)
        HapticsManager.shared.playLiquidSnap()
    }

    func resetPlaygroundLayout() {
        isVaultedInIsland = false
        isDropletSwallowedByIsland = false
        lensShape = .circle
        lensZoomScale = 1.0
        pinchStartScale = 1.0
        lensPosition = CGPoint(x: viewportSize.width * 0.41, y: viewportSize.height * 0.51)
        companionPosition = CGPoint(x: viewportSize.width * 0.64, y: viewportSize.height * 0.58)
        lensVelocity = SIMD2<Float>(-140, -180)
        companionVelocity = SIMD2<Float>(140, 140)
        musicOffset = .zero
        controlOffset = .zero
        weatherOffset = .zero
        lensLiftVel += 3.0
        companionLiftVel += 3.0
        triggerRipple(at: CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5), strength: 0.90)
        HapticsManager.shared.tapMedium()
    }

    // MARK: - Draggable Cards Gestures

    func updateMusicCardDrag(translation: CGSize, velocity: CGSize) {
        if !isDraggingMusic {
            isDraggingMusic = true
            musicDragStart = musicOffset
            HapticsManager.shared.tapSoft(intensity: 0.45)
        }
        musicOffset = musicDragStart + SIMD2<Float>(Float(translation.width), Float(translation.height))
        musicVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height))
    }

    func endMusicCardDrag(velocity: CGSize) {
        isDraggingMusic = false
        musicVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.42
    }

    func updateControlCardDrag(translation: CGSize, velocity: CGSize) {
        if !isDraggingControl {
            isDraggingControl = true
            controlDragStart = controlOffset
            HapticsManager.shared.tapSoft(intensity: 0.45)
        }
        controlOffset = controlDragStart + SIMD2<Float>(Float(translation.width), Float(translation.height))
        controlVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height))
    }

    func endControlCardDrag(velocity: CGSize) {
        isDraggingControl = false
        controlVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.42
    }

    func updateWeatherCardDrag(translation: CGSize, velocity: CGSize) {
        if !isDraggingWeather {
            isDraggingWeather = true
            weatherDragStart = weatherOffset
            HapticsManager.shared.tapSoft(intensity: 0.45)
        }
        weatherOffset = weatherDragStart + SIMD2<Float>(Float(translation.width), Float(translation.height))
        weatherVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height))
    }

    func endWeatherCardDrag(velocity: CGSize) {
        isDraggingWeather = false
        weatherVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.42
    }

    // MARK: - Music & Photo Helpers

    func togglePlayPause() {
        isPlayingMusic.toggle()
        HapticsManager.shared.tapLight()
    }

    func nextTrack() {
        currentTrackIndex = (currentTrackIndex + 1) % MusicTrack.catalog.count
        trackProgress = 0.0
        isPlayingMusic = true
        HapticsManager.shared.selection()
    }

    func previousTrack() {
        currentTrackIndex = (currentTrackIndex - 1 + MusicTrack.catalog.count) % MusicTrack.catalog.count
        trackProgress = 0.0
        isPlayingMusic = true
        HapticsManager.shared.selection()
    }

    func applyCustomPhotoData(_ data: Data) {
        guard let rawImage = UIImage(data: data) else { return }
        let normalized = Self.downscaleAndNormalizeImage(rawImage, maxDimension: 2048)
        customPhotoImage = normalized
        customPhotoAspect = Float(normalized.size.width / max(normalized.size.height, 1.0))
        customPhotoRevision &+= 1
        hasCustomPhoto = true
        wallpaper = .customPhoto
        HapticsManager.shared.success()
    }

    private static func downscaleAndNormalizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let srcSize = image.size
        let maxSide = max(srcSize.width, srcSize.height)
        let scaleRatio = maxSide > maxDimension ? (maxDimension / maxSide) : 1.0
        let dstSize = CGSize(
            width: max(1, floor(srcSize.width * scaleRatio)),
            height: max(1, floor(srcSize.height * scaleRatio))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: dstSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: dstSize))
        }
    }

    // MARK: - 120Hz Lockstep Physics & Uniform Builder

    func stepFrame(now: CFTimeInterval, drawablePointSize: CGSize) {
        if drawablePointSize.width > 40, drawablePointSize.height > 40 {
            viewportSize = drawablePointSize
        }

        let rawDt = (lastStepTime == 0) ? (1.0 / 120.0) : (now - lastStepTime)
        lastStepTime = now

        if rawDt > 0.0005 && rawDt < 0.5 {
            fpsFrameCount += 1
            fpsAccumDuration += rawDt
            if fpsAccumDuration >= 0.25 {
                let avgFps = Double(fpsFrameCount) / fpsAccumDuration
                let roundedFps = min(120, max(1, Int(avgFps.rounded())))
                let ms = (fpsAccumDuration / Double(fpsFrameCount)) * 1000.0
                if currentFPS != roundedFps || abs(currentFrameMs - ms) >= 0.15 {
                    currentFPS = roundedFps
                    currentFrameMs = ms
                }
                fpsFrameCount = 0
                fpsAccumDuration = 0
            }
        }

        let dt = Float(min(max(rawDt, 1.0 / 240.0), 1.0 / 28.0))
        let elapsed = Float(now - startTime)

        if isPlayingMusic {
            audioProgressAccum += Double(dt)
            if audioProgressAccum >= 0.12 {
                let delta = audioProgressAccum / currentTrack.duration
                audioProgressAccum = 0
                let nextProg = trackProgress + delta
                if nextProg >= 1.0 {
                    currentTrackIndex = (currentTrackIndex + 1) % MusicTrack.catalog.count
                    trackProgress = 0.0
                } else {
                    trackProgress = nextProg
                }
            }
        }

        if rippleStrength > 0.003 {
            rippleRadius += 520.0 * dt
            rippleStrength *= exp(-2.7 * dt)
            if rippleStrength < 0.004 { rippleStrength = 0.0 }
        }

        stepSpringReveals(dt: dt, elapsed: elapsed)
        stepDockMagnifierPhysics(dt: dt)
        stepDropletsPhysics(dt: dt)
        stepDraggableCardsPhysics(dt: dt)
        stepLightingAndBuildUniforms(dt: dt, elapsed: elapsed)
    }

    private func stepSpringReveals(dt: Float, elapsed: Float) {
        updateRevealSpring(value: &labBarReveal, vel: &labBarRevealVel, active: isLensLabBarVisible, omega: 24.0, zeta: 0.78, dt: dt)
        updateRevealSpring(value: &musicReveal, vel: &musicRevealVel, active: isMusicVisible, omega: 22.0, zeta: 0.76, dt: dt)
        updateRevealSpring(value: &controlReveal, vel: &controlRevealVel, active: isControlVisible, omega: 22.0, zeta: 0.76, dt: dt)
        updateRevealSpring(value: &weatherReveal, vel: &weatherRevealVel, active: isWeatherVisible, omega: 22.0, zeta: 0.76, dt: dt)
        updateRevealSpring(value: &drawerReveal, vel: &drawerRevealVel, active: isStudioVisible, omega: 24.0, zeta: 0.82, dt: dt)
        updateRevealSpring(value: &companionReveal, vel: &companionRevealVel, active: dualDropletEnabled && !isVaultedInIsland, omega: 20.0, zeta: 0.68, dt: dt)

        // Hero visibility shrinks smoothly into Dynamic Island when swallowed!
        let targetHeroVis: Float = isDropletSwallowedByIsland ? 0.0 : 1.0
        stepSpring1D(pos: &heroVisibilityScale, vel: &heroVisibilityVel, target: targetHeroVis, omega: 24.0, zeta: 0.68, dt: dt)
        heroVisibilityScale = min(1.2, max(0.0, heroVisibilityScale))

        // Dynamic Island audio & swallow breathing halo
        let audioWave: Float = isPlayingMusic ? (0.18 + 0.16 * abs(sin(elapsed * 5.6))) : 0.04
        let swallowBoost: Float = (isDropletSwallowedByIsland || isVaultedInIsland) ? 0.62 : 0.0
        stepSpring1D(pos: &islandHaloScale, vel: &islandHaloVel, target: audioWave + swallowBoost, omega: 20.0, zeta: 0.52, dt: dt)
        islandHaloScale = min(1.45, max(0.0, islandHaloScale))

        let spotTarget: Float = flashlightOn ? 1.0 : 0.0
        spotlightAnim += (spotTarget - spotlightAnim) * min(1.0, dt * 14.0)
    }

    private func updateRevealSpring(value: inout CGFloat, vel: inout Float, active: Bool, omega: Float, zeta: Float, dt: Float) {
        var pos = Float(value)
        stepSpring1D(pos: &pos, vel: &vel, target: active ? 1.0 : 0.0, omega: omega, zeta: zeta, dt: dt)
        if abs(CGFloat(pos) - value) > 0.0008 {
            value = CGFloat(max(0.0, pos))
        } else if !active && pos < 0.002 && value != 0 {
            value = 0
        } else if active && abs(pos - 1.0) < 0.002 && value != 1.0 {
            value = 1.0
        }
    }

    private func stepDockMagnifierPhysics(dt: Float) {
        if !isScrubbingDock {
            let slotX = Float(dockSlotScreenX(index: selectedTab.rawValue, screenWidth: viewportSize.width))
            let dockY = Float(dockCenterY(for: viewportSize.height, safeBottom: safeBottomInset))
            dockThumbTarget = SIMD2<Float>(slotX, dockY)
        }

        stepSpring2D(
            pos: &dockThumbPos,
            vel: &dockThumbVel,
            target: dockThumbTarget,
            omega: isScrubbingDock ? 36.0 : 26.0,
            zeta: isScrubbingDock ? 0.64 : 0.56,
            dt: dt
        )

        stepSpring1D(pos: &dockThumbLift, vel: &dockThumbLiftVel, target: isScrubbingDock ? 1.0 : 0.0, omega: 28.0, zeta: 0.54, dt: dt)

        let speedX = abs(dockThumbVel.x)
        stepSpring1D(pos: &dockThumbStretch, vel: &dockThumbStretchVel, target: 1.0 + min(0.42, speedX / 1200.0), omega: 28.0, zeta: 0.36, dt: dt)
        dockThumbStretch = min(max(dockThumbStretch, 0.76), 1.50)

        let pt = CGPoint(x: CGFloat(dockThumbPos.x), y: CGFloat(dockThumbPos.y))
        if hypot(pt.x - dockThumbScreenPos.x, pt.y - dockThumbScreenPos.y) > 0.05 {
            dockThumbScreenPos = pt
        }
        let clampedLift = CGFloat(min(1.25, max(0.0, dockThumbLift)))
        if abs(clampedLift - dockThumbLiftValue) > 0.002 {
            dockThumbLiftValue = clampedLift
        }
    }

    private func stepDropletsPhysics(dt: Float) {
        let targetHalf = lensShape.baseHalfSize * lensZoomScale
        let targetCorner = lensShape.baseCornerRadius * lensZoomScale
        stepSpring2D(pos: &animHalfSize, vel: &animHalfSizeVel, target: targetHalf, omega: 20.0, zeta: 0.66, dt: dt)
        stepSpring1D(pos: &animCornerRadius, vel: &animCornerVel, target: targetCorner, omega: 20.0, zeta: 0.66, dt: dt)

        stepSpring1D(pos: &lensLiftScale, vel: &lensLiftVel, target: isDraggingLens ? 1.07 : 1.0, omega: 24.0, zeta: 0.56, dt: dt)
        stepSpring1D(pos: &companionLiftScale, vel: &companionLiftVel, target: isDraggingCompanion ? 1.09 : 1.0, omega: 24.0, zeta: 0.56, dt: dt)

        let effectiveHalf = animHalfSize * max(0.15, lensLiftScale * max(0.15, heroVisibilityScale))
        let effectiveCorner = animCornerRadius * max(0.15, lensLiftScale * max(0.15, heroVisibilityScale))

        if abs(CGFloat(effectiveHalf.x) - lensHalfSize.width) > 0.08 ||
           abs(CGFloat(effectiveHalf.y) - lensHalfSize.height) > 0.08 {
            lensHalfSize = CGSize(width: CGFloat(effectiveHalf.x), height: CGFloat(effectiveHalf.y))
        }
        if abs(CGFloat(effectiveCorner) - lensCornerRadius) > 0.08 {
            lensCornerRadius = CGFloat(effectiveCorner)
        }

        let compRad = 54.0 * max(0.5, companionLiftScale)
        if abs(CGFloat(compRad) - companionRadius) > 0.08 {
            companionRadius = CGFloat(compRad)
        }

        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)
        let gravityAccel = gravityModeEnabled ? (motionManager.screenGravity * 920.0) : SIMD2<Float>(0, 0)
        let dragRate: Float = gravityModeEnabled ? 0.85 : 2.05

        if !isDraggingLens && !isDropletSwallowedByIsland {
            var pos = SIMD2<Float>(Float(lensPosition.x), Float(lensPosition.y))
            lensVelocity += gravityAccel * dt
            pos += lensVelocity * dt
            lensVelocity *= exp(-dragRate * dt)

            // Swallow into Dynamic Island if flung upward into top cutout!
            let islPos = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
            if simd_distance(pos, islPos) < 52.0 && lensVelocity.y < -40.0 {
                swallowDropletIntoIsland()
                return
            }

            let minX = effectiveHalf.x + 10.0
            let maxX = max(minX + 1.0, w - effectiveHalf.x - 10.0)
            let minY = Float(safeTopInset) + 52.0 + effectiveHalf.y
            let maxY = max(minY + 1.0, h - Float(safeBottomInset) - 86.0 - effectiveHalf.y)
            let restitution: Float = 0.75

            if pos.x < minX {
                let spd = abs(lensVelocity.x); pos.x = minX
                if lensVelocity.x < 0 { lensVelocity.x = -lensVelocity.x * restitution; injectLensSquish(angle: 0, speed: spd) }
            } else if pos.x > maxX {
                let spd = abs(lensVelocity.x); pos.x = maxX
                if lensVelocity.x > 0 { lensVelocity.x = -lensVelocity.x * restitution; injectLensSquish(angle: 0, speed: spd) }
            }
            if pos.y < minY {
                let spd = abs(lensVelocity.y); pos.y = minY
                if lensVelocity.y < 0 { lensVelocity.y = -lensVelocity.y * restitution; injectLensSquish(angle: .pi * 0.5, speed: spd) }
            } else if pos.y > maxY {
                let spd = abs(lensVelocity.y); pos.y = maxY
                if lensVelocity.y > 0 { lensVelocity.y = -lensVelocity.y * restitution; injectLensSquish(angle: .pi * 0.5, speed: spd) }
            }

            if !gravityModeEnabled && simd_length(lensVelocity) < 2.0 { lensVelocity = .zero }
            let newPt = CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.y))
            if hypot(newPt.x - lensPosition.x, newPt.y - lensPosition.y) > 0.04 {
                lensPosition = newPt
            }
        }

        if dualDropletEnabled && !isVaultedInIsland {
            if !isDraggingCompanion {
                var cPos = SIMD2<Float>(Float(companionPosition.x), Float(companionPosition.y))
                companionVelocity += gravityAccel * dt

                if metaballFusionEnabled && !isDropletSwallowedByIsland {
                    let heroPos = SIMD2<Float>(Float(lensPosition.x), Float(lensPosition.y))
                    let delta = heroPos - cPos
                    let dist = simd_length(delta)
                    let mergeBand = max(effectiveHalf.x, effectiveHalf.y) + compRad + 34.0
                    if dist > 26.0 && dist < mergeBand {
                        companionVelocity += (delta / dist) * 165.0 * dt
                    }
                }

                cPos += companionVelocity * dt
                companionVelocity *= exp(-dragRate * dt)

                let cMinX = compRad + 10.0
                let cMaxX = max(cMinX + 1.0, w - compRad - 10.0)
                let cMinY = Float(safeTopInset) + 52.0 + compRad
                let cMaxY = max(cMinY + 1.0, h - Float(safeBottomInset) - 86.0 - compRad)
                let rest: Float = 0.78

                if cPos.x < cMinX {
                    let spd = abs(companionVelocity.x); cPos.x = cMinX
                    if companionVelocity.x < 0 { companionVelocity.x = -companionVelocity.x * rest; injectCompanionSquish(angle: 0, speed: spd) }
                } else if cPos.x > cMaxX {
                    let spd = abs(companionVelocity.x); cPos.x = cMaxX
                    if companionVelocity.x > 0 { companionVelocity.x = -companionVelocity.x * rest; injectCompanionSquish(angle: 0, speed: spd) }
                }
                if cPos.y < cMinY {
                    let spd = abs(companionVelocity.y); cPos.y = cMinY
                    if companionVelocity.y < 0 { companionVelocity.y = -companionVelocity.y * rest; injectCompanionSquish(angle: .pi * 0.5, speed: spd) }
                } else if cPos.y > cMaxY {
                    let spd = abs(companionVelocity.y); cPos.y = cMaxY
                    if companionVelocity.y > 0 { companionVelocity.y = -companionVelocity.y * rest; injectCompanionSquish(angle: .pi * 0.5, speed: spd) }
                }

                if !gravityModeEnabled && simd_length(companionVelocity) < 2.0 { companionVelocity = .zero }
                let newCPt = CGPoint(x: CGFloat(cPos.x), y: CGFloat(cPos.y))
                if hypot(newCPt.x - companionPosition.x, newCPt.y - companionPosition.y) > 0.04 {
                    companionPosition = newCPt
                }
            }

            if metaballFusionEnabled && !isDropletSwallowedByIsland {
                let pA = SIMD2<Float>(Float(lensPosition.x), Float(lensPosition.y))
                let pB = SIMD2<Float>(Float(companionPosition.x), Float(companionPosition.y))
                let dist = simd_length(pA - pB)
                let nowFused = dist < (min(effectiveHalf.x, effectiveHalf.y) + compRad + 22.0)
                if nowFused != wasDropletsFused {
                    wasDropletsFused = nowFused
                    let mid = CGPoint(x: CGFloat((pA.x + pB.x) * 0.5), y: CGFloat((pA.y + pB.y) * 0.5))
                    if nowFused {
                        HapticsManager.shared.tapSoft(intensity: 0.60)
                    } else {
                        lensStretchVel -= 2.0
                        companionStretchVel -= 2.4
                        triggerRipple(at: mid, strength: 0.78)
                        HapticsManager.shared.playLiquidSnap()
                    }
                }
            }
        }

        updateDropletStretch(vel: lensVelocity, angle: &lensStretchAngle, stretch: &lensStretchFactor, stretchVel: &lensStretchVel, dt: dt)
        updateDropletStretch(vel: companionVelocity, angle: &companionStretchAngle, stretch: &companionStretchFactor, stretchVel: &companionStretchVel, dt: dt)
    }

    private func updateDropletStretch(vel: SIMD2<Float>, angle: inout Float, stretch: inout Float, stretchVel: inout Float, dt: Float) {
        let speed = simd_length(vel)
        if speed > 28.0 {
            let targetAngle = atan2(vel.y, vel.x)
            var delta = targetAngle - angle
            while delta > .pi { delta -= 2.0 * .pi }
            while delta < -.pi { delta += 2.0 * .pi }
            angle += delta * min(1.0, dt * 18.0)
        }
        stepSpring1D(pos: &stretch, vel: &stretchVel, target: 1.0 + min(0.28, speed / 2450.0), omega: 26.0, zeta: 0.38, dt: dt)
        stretch = min(max(stretch, 0.72), 1.40)
    }

    private func injectLensSquish(angle: Float, speed: Float) {
        guard speed > 75.0 else { return }
        lensStretchAngle = angle
        lensStretchVel -= min(4.2, speed * 0.0038)
        HapticsManager.shared.wallBounce(speed: speed)
    }

    private func injectCompanionSquish(angle: Float, speed: Float) {
        guard speed > 75.0 else { return }
        companionStretchAngle = angle
        companionStretchVel -= min(4.2, speed * 0.0040)
        HapticsManager.shared.wallBounce(speed: speed)
    }

    private func stepDraggableCardsPhysics(dt: Float) {
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)
        let islandVec = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))

        let baseMusic = isVaultedInIsland ? islandVec : SIMD2<Float>(w * 0.5, Float(safeTopInset) + 158.0)
        stepSingleCard(basePos: baseMusic, offset: &musicOffset, velocity: &musicVelocity, isDragging: isDraggingMusic, halfHeight: 88.0, centerOut: &musicCardCenter, w: w, h: h, dt: dt)

        let baseControl = isVaultedInIsland ? islandVec : SIMD2<Float>(w * 0.5, Float(safeTopInset) + 190.0)
        stepSingleCard(basePos: baseControl, offset: &controlOffset, velocity: &controlVelocity, isDragging: isDraggingControl, halfHeight: 126.0, centerOut: &controlCardCenter, w: w, h: h, dt: dt)

        let baseWeather = isVaultedInIsland ? islandVec : SIMD2<Float>(w * 0.5, Float(safeTopInset) + 174.0)
        stepSingleCard(basePos: baseWeather, offset: &weatherOffset, velocity: &weatherVelocity, isDragging: isDraggingWeather, halfHeight: 98.0, centerOut: &weatherCardCenter, w: w, h: h, dt: dt)
    }

    private func stepSingleCard(
        basePos: SIMD2<Float>,
        offset: inout SIMD2<Float>,
        velocity: inout SIMD2<Float>,
        isDragging: Bool,
        halfHeight: Float,
        centerOut: inout CGPoint,
        w: Float,
        h: Float,
        dt: Float
    ) {
        if !isDragging && !isVaultedInIsland {
            offset += velocity * dt
            velocity *= exp(-6.5 * dt)
            if simd_length(velocity) < 1.5 { velocity = .zero }

            let cardPos = basePos + offset
            let minX: Float = 176.0
            let maxX = max(minX, w - 176.0)
            let minY = Float(safeTopInset) + 56.0 + halfHeight
            let maxY = max(minY, h - Float(safeBottomInset) - 96.0 - halfHeight)

            var clamped = cardPos
            clamped.x = min(max(clamped.x, minX), maxX)
            clamped.y = min(max(clamped.y, minY), maxY)
            offset += (clamped - cardPos) * min(1.0, dt * 14.0)
        }
        let targetPos = isVaultedInIsland ? basePos : (basePos + offset)
        let current = SIMD2<Float>(Float(centerOut.x), Float(centerOut.y))
        let next = current + (targetPos - current) * min(1.0, dt * 18.0)
        if hypot(CGFloat(next.x) - centerOut.x, CGFloat(next.y) - centerOut.y) > 0.05 {
            centerOut = CGPoint(x: CGFloat(next.x), y: CGFloat(next.y))
        }
    }

    private func stepLightingAndBuildUniforms(dt: Float, elapsed: Float) {
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)

        var desiredLight = gyroEnabled
            ? motionManager.targetLightDir
            : SIMD2<Float>(cos(elapsed * 0.45) * 0.55 - 0.35, sin(elapsed * 0.38) * 0.45 - 0.68)

        if let touch = touchLightPos {
            let lensC = SIMD2<Float>(Float(lensPosition.x), Float(lensPosition.y))
            let delta = touch - lensC
            let len = simd_length(delta)
            if len > 8.0 { desiredLight = simd_normalize(desiredLight * 0.55 + (delta / len) * 0.45) }
        }

        currentLightDir += (desiredLight - currentLightDir) * min(1.0, dt * 14.0)
        let normLight = simd_length(currentLightDir) > 1e-3 ? simd_normalize(currentLightDir) : SIMD2<Float>(-0.58, -0.81)

        let cardW = min(w - 32.0, 346.0)
        let spotOrigin = (controlReveal > 0.05)
            ? SIMD2<Float>(Float(controlCardCenter.x) - cardW * 0.32, Float(controlCardCenter.y) - 46.0)
            : SIMD2<Float>(w * 0.5, Float(safeTopInset) + 20.0)

        let textMix: Float = (wallpaper == .customPhoto) ? (showTypographyOnPhoto ? 0.72 : 0.0) : 1.0

        let solarWarmth: Float
        if weatherReveal > 0.02 {
            let phase = Float((solarHour / 24.0) * 2.0 * .pi)
            solarWarmth = Float(weatherReveal) * (-cos(phase) * 0.55 + sin(phase * 2.0) * 0.25)
        } else {
            solarWarmth = 0.0
        }

        var count = 0
        let renderMetalUIChrome = !useNativeSystemGlass

        if renderMetalUIChrome {
            let dockW = Float(dockWidth(for: viewportSize.width))
            let dockY = Float(dockCenterY(for: viewportSize.height, safeBottom: safeBottomInset))
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(w * 0.5, dockY, dockW * 0.5, 34.0),
                shapeAndTransform: SIMD4<Float>(34.0, 0.0, 1.0, 1.06),
                styleParams: SIMD4<Float>(1.0, 0.52, 0.70, 0.92),
                tintOverride: SIMD4<Float>(0.90, 0.96, 1.0, 0.04)
            )
            count += 1

            if labBarReveal > 0.005 {
                let lScale = Float(0.88 + 0.12 * labBarReveal)
                let pillHalfW = (min(w - 32.0, 336.0) * 0.5) * lScale
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, Float(safeTopInset) + 84.0, pillHalfW, 25.0 * lScale),
                    shapeAndTransform: SIMD4<Float>(25.0 * lScale, 0.0, 1.0, 1.08),
                    styleParams: SIMD4<Float>(Float(min(1.0, labBarReveal)), 0.55, 0.55, 0.85),
                    tintOverride: SIMD4<Float>(0.25, 0.88, 1.0, gravityModeEnabled ? 0.14 : 0.04)
                )
                count += 1
            }

            if musicReveal > 0.005 {
                let mScale = Float(0.84 + 0.16 * musicReveal)
                let mSpeed = simd_length(musicVelocity)
                let mAngle = mSpeed > 20.0 ? atan2(musicVelocity.y, musicVelocity.x) : 0.0
                let trackTint = currentTrack.shaderTint
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(Float(musicCardCenter.x), Float(musicCardCenter.y), (cardW * 0.5) * mScale, 88.0 * mScale),
                    shapeAndTransform: SIMD4<Float>(30.0 * mScale, mAngle, 1.0 + min(0.08, mSpeed / 3600.0), 1.10),
                    styleParams: SIMD4<Float>(Float(min(1.0, musicReveal)), 0.58, 0.55, isDraggingMusic ? 1.26 : 0.96),
                    tintOverride: SIMD4<Float>(trackTint.x, trackTint.y, trackTint.z, isPlayingMusic ? 0.13 : 0.04)
                )
                count += 1
            }

            if controlReveal > 0.005 {
                let cScale = Float(0.84 + 0.16 * controlReveal)
                let cSpeed = simd_length(controlVelocity)
                let cAngle = cSpeed > 20.0 ? atan2(controlVelocity.y, controlVelocity.x) : 0.0
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(Float(controlCardCenter.x), Float(controlCardCenter.y), (cardW * 0.5) * cScale, 126.0 * cScale),
                    shapeAndTransform: SIMD4<Float>(30.0 * cScale, cAngle, 1.0 + min(0.08, cSpeed / 3600.0), flashlightOn ? 1.35 : 1.10),
                    styleParams: SIMD4<Float>(Float(min(1.0, controlReveal)), 0.56, 0.60, isDraggingControl ? 1.26 : 0.98),
                    tintOverride: SIMD4<Float>(0.96, 0.88, 0.58, flashlightOn ? 0.14 : 0.03)
                )
                count += 1
            }

            if weatherReveal > 0.005 {
                let wScale = Float(0.84 + 0.16 * weatherReveal)
                let wSpeed = simd_length(weatherVelocity)
                let wAngle = wSpeed > 20.0 ? atan2(weatherVelocity.y, weatherVelocity.x) : 0.0
                let wTint = weatherCondition.shaderTint
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(Float(weatherCardCenter.x), Float(weatherCardCenter.y), (cardW * 0.5) * wScale, 98.0 * wScale),
                    shapeAndTransform: SIMD4<Float>(30.0 * wScale, wAngle, 1.0 + min(0.08, wSpeed / 3600.0), 1.12),
                    styleParams: SIMD4<Float>(Float(min(1.0, weatherReveal)), 0.56, 0.56, isDraggingWeather ? 1.26 : 0.98),
                    tintOverride: SIMD4<Float>(wTint.x, wTint.y, wTint.z, 0.14)
                )
                count += 1
            }
        }

        // Always render Hero Liquid Lens + Companion Droplet in 120Hz Metal Lab (fuses with Hardware Dynamic Island!)
        if heroVisibilityScale > 0.02 && count < 11 {
            let fuseWithCompanion = metaballFusionEnabled && (companionReveal > 0.01) && (count + 1 < 11)
            let leaderFlag: Float = fuseWithCompanion ? -1.0 : -2.0
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(
                    Float(lensPosition.x),
                    Float(lensPosition.y),
                    Float(lensHalfSize.width),
                    Float(lensHalfSize.height)
                ),
                shapeAndTransform: SIMD4<Float>(
                    Float(lensCornerRadius),
                    lensStretchAngle,
                    lensStretchFactor,
                    isDraggingLens ? 1.32 : 1.18
                ),
                styleParams: SIMD4<Float>(min(1.0, heroVisibilityScale), 1.04, 0.0, isDraggingLens ? 1.34 : 1.02),
                tintOverride: SIMD4<Float>(0.0, 0.0, 0.0, leaderFlag)
            )
            count += 1
        }

        if companionReveal > 0.01 && count < 11 {
            let compScale = Float(0.35 + 0.65 * min(1.0, companionReveal))
            let r = Float(companionRadius) * compScale
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(Float(companionPosition.x), Float(companionPosition.y), r, r),
                shapeAndTransform: SIMD4<Float>(r, companionStretchAngle, companionStretchFactor, isDraggingCompanion ? 1.32 : 1.18),
                styleParams: SIMD4<Float>(Float(min(1.0, companionReveal)), 1.08, -0.25, isDraggingCompanion ? 1.30 : 1.0),
                tintOverride: SIMD4<Float>(0.35, 0.92, 1.0, 0.05)
            )
            count += 1
        }

        if renderMetalUIChrome {
            if drawerReveal > 0.005 && count < 11 {
                let dScale = Float(0.92 + 0.08 * drawerReveal)
                let drawerH: Float = 360.0
                let drawerHalfW = (min(w - 24.0, 366.0) * 0.5) * dScale
                let drawerHalfH = (drawerH * 0.5) * dScale
                let drawerBaseY = h - Float(safeBottomInset) - 86.0 - drawerH * 0.5
                let slideOffset = (1.0 - Float(min(1.0, drawerReveal))) * 44.0
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, drawerBaseY + slideOffset, drawerHalfW, drawerHalfH),
                    shapeAndTransform: SIMD4<Float>(32.0 * dScale, 0.0, 1.0, 1.12),
                    styleParams: SIMD4<Float>(Float(min(1.0, drawerReveal)), 0.48, 0.95, 1.18),
                    tintOverride: SIMD4<Float>(0.08, 0.12, 0.22, tintMode == .light ? 0.0 : 0.18)
                )
                count += 1
            }

            if count < 12 {
                let dockW = Float(dockWidth(for: viewportSize.width))
                let lift = min(1.25, max(0.0, dockThumbLift))
                let slotW = (dockW - 16.0) / Float(DockTab.allCases.count)
                let liftedHalfW = (slotW * 0.46) * (1.0 + 0.34 * lift)
                let liftedHalfH: Float = 26.0 * (1.0 + 0.34 * lift)
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(dockThumbPos.x, dockThumbPos.y, liftedHalfW, liftedHalfH),
                    shapeAndTransform: SIMD4<Float>(liftedHalfH, 0.0, dockThumbStretch, 0.95 + 0.62 * min(1.0, lift)),
                    styleParams: SIMD4<Float>(0.52 + 0.46 * min(1.0, lift), 0.42 + 0.92 * min(1.0, lift), -4.2 * min(1.0, lift), 0.35 + 1.15 * min(1.0, lift)),
                    tintOverride: SIMD4<Float>(0.35, 0.92, 1.0, isPullingUpToPin ? 0.28 : (0.08 * (1.0 - min(1.0, lift))))
                )
                count += 1
            }
        } else if isScrubbingDock && count < 12 {
            // Even in iOS 27 Native Glass mode, add the crystal convex magnifying water-droplet lens while scrubbing Dock!
            let dockW = Float(dockWidth(for: viewportSize.width))
            let lift = min(1.25, max(0.0, dockThumbLift))
            let slotW = (dockW - 16.0) / Float(DockTab.allCases.count)
            let liftedHalfW = (slotW * 0.48) * (1.0 + 0.30 * lift)
            let liftedHalfH: Float = 27.0 * (1.0 + 0.30 * lift)
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(dockThumbPos.x, dockThumbPos.y, liftedHalfW, liftedHalfH),
                shapeAndTransform: SIMD4<Float>(liftedHalfH, 0.0, dockThumbStretch, 1.45),
                styleParams: SIMD4<Float>(0.90 * min(1.0, lift), 1.25, -4.2, 1.35),
                tintOverride: SIMD4<Float>(0.35, 0.92, 1.0, isPullingUpToPin ? 0.28 : 0.04)
            )
            count += 1
        }

        sceneUniforms = SceneUniforms(
            viewportAndTime: SIMD4<Float>(w, h, elapsed, Float(wallpaper.rawValue)),
            opticalParams: SIMD4<Float>(Float(refraction), Float(bezel), Float(dispersion), Float(frost)),
            lightingParams: SIMD4<Float>(normLight.x, normLight.y, Float(tintMode.rawValue), Float(sceneBrightness)),
            spotlightParams: SIMD4<Float>(spotOrigin.x, spotOrigin.y, -normLight.x * 0.45, spotlightAnim),
            layerFlags: SIMD4<Float>(Float(count), hasCustomPhoto ? 1.0 : 0.0, customPhotoAspect, textMix),
            rippleParams: SIMD4<Float>(rippleCenter.x, rippleCenter.y, rippleRadius, rippleStrength),
            atmosphereParams: SIMD4<Float>(solarWarmth, prismRimBoostEnabled ? 1.38 : 1.0, 38.0, 1.0),
            islandParams: SIMD4<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y), islandHaloScale, islandPullStretchPt)
        )
    }

    private func stepSpring1D(pos: inout Float, vel: inout Float, target: Float, omega: Float, zeta: Float, dt: Float) {
        let force = -omega * omega * (pos - target) - 2.0 * zeta * omega * vel
        vel += force * dt
        pos += vel * dt
    }

    private func stepSpring2D(pos: inout SIMD2<Float>, vel: inout SIMD2<Float>, target: SIMD2<Float>, omega: Float, zeta: Float, dt: Float) {
        let force = -omega * omega * (pos - target) - 2.0 * zeta * omega * vel
        vel += force * dt
        pos += vel * dt
    }
}
