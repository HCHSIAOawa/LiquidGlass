import SwiftUI
import UIKit
import QuartzCore
import Observation
import ActivityKit
import simd

@MainActor
@Observable
final class GlassSceneController {
    // MARK: - Dual Engine Mode (Defaults to Custom Metal Optics when Optical Sliders Move)

    var engineMode: GlassEngineMode = .customMetalOptics {
        didSet {
            if engineMode != oldValue {
                HapticsManager.shared.selection()
                syncLiveActivityNow()
            }
        }
    }

    var isNativeCompositorSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    var useNativeSystemGlass: Bool {
        engineMode == .nativeAppleGlass && isNativeCompositorSupported
    }

    /// Automatically switches to Metal Optical Engine when user adjusts optical sliders in Studio.
    func activateMetalOpticsIfNeeded() {
        if engineMode != .customMetalOptics {
            engineMode = .customMetalOptics
        }
    }

    // MARK: - Active Bottom Tab & Pinning States

    var selectedTab: DockTab = .lensLab {
        didSet {
            if selectedTab == .opticalStudio {
                // Nudge Hero Specimen Lens into open upper arena above Studio Drawer so sliders show live feedback!
                let clearUpperY = Float(safeTopInset) + 150.0
                if heroPos.y > clearUpperY + 40.0 || isDropletSwallowedByIsland {
                    isDropletSwallowedByIsland = false
                    heroPos = SIMD2<Float>(Float(viewportSize.width) * 0.5, clearUpperY)
                    heroVel = SIMD2<Float>(0.0, -40.0)
                }
            }
        }
    }

    var pinnedMusic: Bool = false
    var pinnedControl: Bool = false
    var pinnedWeather: Bool = false

    // MARK: - iPhone 18 Pro Compact Hardware Cutout Calibration (Persisted, Default 88x32 @ Top 12pt)

    var islandWidthPt: Double = 88.0 {
        didSet { UserDefaults.standard.set(islandWidthPt, forKey: "lg.islandWidthPt") }
    }
    var islandHeightPt: Double = 32.0 {
        didSet { UserDefaults.standard.set(islandHeightPt, forKey: "lg.islandHeightPt") }
    }
    var islandTopMarginPt: Double = 12.0 {
        didSet { UserDefaults.standard.set(islandTopMarginPt, forKey: "lg.islandTopMarginPt") }
    }

    // MARK: - System Live Activity State (Global Native Dynamic Island Outside App)

    var liveActivityEnabled: Bool = true {
        didSet {
            if liveActivityEnabled != oldValue {
                handleLiveActivityToggle(enabled: liveActivityEnabled)
            }
        }
    }

    // MARK: - Optical, Wallpaper & Physics Parameters

    var wallpaper: WallpaperPreset = .aurora {
        didSet { syncLiveActivityNow() }
    }
    var tintMode: GlassTintMode = .clear
    var lensShape: LensShapeMode = .circle

    var refraction: Double = 54.0
    var bezel: Double = 36.0
    var dispersion: Double = 0.16
    var frost: Double = 0.25

    var dualDropletEnabled: Bool = true {
        didSet { HapticsManager.shared.tapMedium() }
    }
    var metaballFusionEnabled: Bool = true
    var gravityModeEnabled: Bool = false {
        didSet {
            if gravityModeEnabled && !gyroEnabled { gyroEnabled = true }
            HapticsManager.shared.selection()
        }
    }
    var touchRipplesEnabled: Bool = true
    var prismRimBoostEnabled: Bool = true

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

    // MARK: - Control Hub, Weather & Music States

    var flashlightOn: Bool = false
    var sceneBrightness: Double = 1.0

    var weatherCondition: WeatherCondition = .sunny
    var solarHour: Double = 16.5

    var isPlayingMusic: Bool = true {
        didSet { syncLiveActivityNow() }
    }
    var currentTrackIndex: Int = 0 {
        didSet { syncLiveActivityNow() }
    }
    var trackProgress: Double = 0.28

    var currentTrack: MusicTrack {
        MusicTrack.catalog[currentTrackIndex % MusicTrack.catalog.count]
    }

    var isLensLabBarVisible: Bool { selectedTab == .lensLab }
    var isMusicVisible: Bool { selectedTab == .musicBeat || pinnedMusic }
    var isControlVisible: Bool { selectedTab == .controlHub || pinnedControl }
    var isWeatherVisible: Bool { selectedTab == .weatherSolar || pinnedWeather }
    var isStudioVisible: Bool { selectedTab == .opticalStudio }

    // Throttled FPS badge readout (updated at most 2x/sec ONLY when integer changes)
    private(set) var currentFPS: Int = 120
    private(set) var currentFrameMs: Double = 8.3

    var hasCustomPhoto: Bool = false

    // MARK: - Observation-Ignored Pure 120Hz GPU & Physics State (NEVER Triggers SwiftUI Layout!)

    @ObservationIgnored var sceneUniforms = SceneUniforms()
    @ObservationIgnored var elementUniforms = [GlassElementUniform](repeating: GlassElementUniform(), count: 12)

    @ObservationIgnored var customPhotoImage: UIImage?
    @ObservationIgnored var customPhotoRevision: Int = 0
    @ObservationIgnored var customPhotoAspect: Float = 0.75

    @ObservationIgnored private let motionManager = MotionManager()
    @ObservationIgnored private var intentObserver: NSObjectProtocol?

    @ObservationIgnored private var hasInitializedLayout: Bool = false
    @ObservationIgnored private(set) var safeTopInset: CGFloat = 54
    @ObservationIgnored private(set) var safeBottomInset: CGFloat = 34
    @ObservationIgnored private(set) var viewportSize: CGSize = CGSize(width: 393, height: 852)

    // Hero Droplet & OLED Black-Hole Island Swallow state
    @ObservationIgnored private(set) var isDropletSwallowedByIsland: Bool = false
    @ObservationIgnored private var isDraggingLens: Bool = false
    @ObservationIgnored private var lensDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var heroPos = SIMD2<Float>(162, 430)
    @ObservationIgnored private var heroVel = SIMD2<Float>(0, 0)
    @ObservationIgnored private var lensZoomScale: Float = 1.0
    @ObservationIgnored private var pinchStartScale: Float = 1.0

    @ObservationIgnored private var animHalfSize = SIMD2<Float>(84, 84)
    @ObservationIgnored private var animHalfSizeVel = SIMD2<Float>(0, 0)
    @ObservationIgnored private var animCornerRadius: Float = 84
    @ObservationIgnored private var animCornerVel: Float = 0

    @ObservationIgnored private var lensLiftScale: Float = 1.0
    @ObservationIgnored private var lensLiftVel: Float = 0.0
    @ObservationIgnored private var lensStretchFactor: Float = 1.0
    @ObservationIgnored private var lensStretchVel: Float = 0.0
    @ObservationIgnored private var lensStretchAngle: Float = 0.0
    @ObservationIgnored private var heroVisibilityScale: Float = 1.0
    @ObservationIgnored private var heroVisibilityVel: Float = 0.0

    // Hardware Cutout Pull-Down state
    @ObservationIgnored private var islandPullStretchPt: Float = 0.0
    @ObservationIgnored private var hasSpitDuringPull: Bool = false

    // Companion Droplet state
    @ObservationIgnored private var isDraggingCompanion: Bool = false
    @ObservationIgnored private var companionDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var companionPos = SIMD2<Float>(258, 510)
    @ObservationIgnored private var companionVel = SIMD2<Float>(0, 0)
    @ObservationIgnored private var companionLiftScale: Float = 1.0
    @ObservationIgnored private var companionLiftVel: Float = 0.0
    @ObservationIgnored private var companionStretchFactor: Float = 1.0
    @ObservationIgnored private var companionStretchVel: Float = 0.0
    @ObservationIgnored private var companionStretchAngle: Float = 0.0
    @ObservationIgnored private var companionReveal: Float = 1.0
    @ObservationIgnored private var companionRevealVel: Float = 0.0
    @ObservationIgnored private var wasDropletsFused: Bool = true

    // Single-Axis Horizontal Dock Capsule Physics (Y Strictly Locked!)
    @ObservationIgnored private var dockThumbX: Float = 80.0
    @ObservationIgnored private var dockThumbVelX: Float = 0.0
    @ObservationIgnored private var dockThumbTargetX: Float = 80.0
    @ObservationIgnored private var isScrubbingDockInternal: Bool = false
    @ObservationIgnored private var dockThumbLift: Float = 0.0
    @ObservationIgnored private var dockThumbLiftVel: Float = 0.0
    @ObservationIgnored private var dockThumbStretch: Float = 1.0
    @ObservationIgnored private var dockThumbStretchVel: Float = 0.0

    // Card live centers (synced directly from card gestures without 120Hz SwiftUI loop)
    @ObservationIgnored private var musicLiveOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var controlLiveOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var weatherLiveOffset = SIMD2<Float>(0, 0)

    @ObservationIgnored private var labBarAlpha: Float = 1.0
    @ObservationIgnored private var musicAlpha: Float = 0.0
    @ObservationIgnored private var controlAlpha: Float = 0.0
    @ObservationIgnored private var weatherAlpha: Float = 0.0
    @ObservationIgnored private var drawerAlpha: Float = 0.0

    // Shockwave ripple & lighting
    @ObservationIgnored private var rippleCenter = SIMD2<Float>(196, 420)
    @ObservationIgnored private var rippleRadius: Float = 0.0
    @ObservationIgnored private var rippleStrength: Float = 0.0
    @ObservationIgnored private var totalRippleCount: Int = 0
    @ObservationIgnored private var spotlightAnim: Float = 0.0
    @ObservationIgnored private var currentLightDir = SIMD2<Float>(-0.58, -0.81)
    @ObservationIgnored private var touchLightPos: SIMD2<Float>?

    @ObservationIgnored private var startTime: CFTimeInterval = CACurrentMediaTime()
    @ObservationIgnored private var lastStepTime: CFTimeInterval = 0
    @ObservationIgnored private var fpsFrameCount: Int = 0
    @ObservationIgnored private var fpsAccumDuration: CFTimeInterval = 0
    @ObservationIgnored private var audioProgressAccum: Double = 0

    init() {
        let savedW = UserDefaults.standard.double(forKey: "lg.islandWidthPt")
        if savedW >= 60 && savedW <= 140 { islandWidthPt = savedW }
        let savedTop = UserDefaults.standard.double(forKey: "lg.islandTopMarginPt")
        if savedTop >= 4 && savedTop <= 30 { islandTopMarginPt = savedTop }

        motionManager.setEnabled(true)
        observeLiveActivityIntents()
    }

    // MARK: - Geometry & Coordinate Helpers

    var hardwareIslandCenter: CGPoint {
        CGPoint(
            x: viewportSize.width * 0.5,
            y: CGFloat(islandTopMarginPt + islandHeightPt * 0.5)
        )
    }

    func dockWidth(for screenWidth: CGFloat) -> CGFloat {
        min(screenWidth - 24.0, 362.0)
    }

    func dockCenterY(for screenHeight: CGFloat, safeBottom: CGFloat) -> CGFloat {
        screenHeight - safeBottom - 36.0
    }

    func dockSlotScreenX(index: Int, screenWidth: CGFloat) -> CGFloat {
        let dWidth = dockWidth(for: screenWidth)
        let innerLeft = (screenWidth - dWidth) * 0.5 + 6.0
        let slotW = (dWidth - 12.0) / CGFloat(DockTab.allCases.count)
        return innerLeft + slotW * (CGFloat(index) + 0.5)
    }

    func updateGeometry(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        guard size.width > 40, size.height > 40 else { return }
        viewportSize = size
        safeTopInset = safeTop
        safeBottomInset = safeBottom

        if !hasInitializedLayout {
            hasInitializedLayout = true
            heroPos = SIMD2<Float>(Float(size.width * 0.40), Float(size.height * 0.49))
            companionPos = SIMD2<Float>(Float(size.width * 0.65), Float(size.height * 0.56))

            let initX = Float(dockSlotScreenX(index: selectedTab.rawValue, screenWidth: size.width))
            dockThumbX = initX
            dockThumbTargetX = initX

            if liveActivityEnabled {
                syncLiveActivityNow()
            }
        }
    }

    // MARK: - InteractiveMTKView Direct Hit Testing (Zero SwiftUI Views Needed!)

    func hitTestHardwareIsland(at point: CGPoint) -> Bool {
        let c = hardwareIslandCenter
        let halfW = CGFloat(islandWidthPt * 0.5) + 16.0
        let halfH = CGFloat(islandHeightPt * 0.5) + 14.0
        return abs(point.x - c.x) <= halfW && abs(point.y - c.y) <= halfH
    }

    func hitTestHeroDroplet(at point: CGPoint) -> Bool {
        guard !isDropletSwallowedByIsland else { return false }
        let dx = abs(Float(point.x) - heroPos.x)
        let dy = abs(Float(point.y) - heroPos.y)
        let ext = animHalfSize * lensLiftScale + SIMD2<Float>(14, 14)
        return dx <= ext.x && dy <= ext.y
    }

    func hitTestCompanionDroplet(at point: CGPoint) -> Bool {
        guard dualDropletEnabled else { return false }
        let dist = hypot(Float(point.x) - companionPos.x, Float(point.y) - companionPos.y)
        return dist <= (54.0 * companionLiftScale + 14.0)
    }

    // MARK: - iPhone 18 Pro Pure-Black Cutout Swallow & Spit Physics

    func handleHardwareIslandTap() {
        if isDropletSwallowedByIsland {
            spitDropletFromIsland()
        } else {
            swallowDropletIntoIsland()
        }
    }

    func swallowDropletIntoIsland() {
        isDropletSwallowedByIsland = true
        let c = hardwareIslandCenter
        heroPos = SIMD2<Float>(Float(c.x), Float(c.y))
        heroVel = .zero
        HapticsManager.shared.playIslandSwallow()
    }

    func spitDropletFromIsland() {
        isDropletSwallowedByIsland = false
        let c = hardwareIslandCenter
        heroPos = SIMD2<Float>(Float(c.x), Float(c.y) + 54.0)
        heroVel = SIMD2<Float>(Float.random(in: -70...70), 540.0)
        lensStretchAngle = .pi * 0.5
        lensStretchVel += 3.6
        triggerRipple(at: CGPoint(x: c.x, y: c.y + 34.0), strength: 0.92)
        HapticsManager.shared.playLiquidSnap()
    }

    func updateIslandPullDown(translationY: CGFloat) {
        let pull = Float(max(0.0, min(68.0, translationY)))
        islandPullStretchPt = pull
        if pull >= 52.0 && !hasSpitDuringPull {
            hasSpitDuringPull = true
            islandPullStretchPt = 0.0
            spitDropletFromIsland()
        }
    }

    func endIslandPullDown() {
        islandPullStretchPt = 0.0
        hasSpitDuringPull = false
    }

    // MARK: - Global System Dynamic Island Live Activity (ActivityKit — Zero App Groups)

    private func handleLiveActivityToggle(enabled: Bool) {
        if enabled {
            syncLiveActivityNow()
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

    func syncLiveActivityNow() {
        guard liveActivityEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = LiquidGlassActivityAttributes.ContentState(
            engineName: engineMode.badgeLabel,
            wallpaperTitle: wallpaper.title,
            wallpaperIndex: wallpaper.rawValue,
            trackTitle: currentTrack.title,
            trackArtist: currentTrack.artist,
            isPlaying: isPlayingMusic,
            solarHour: Int(solarHour.rounded()) % 24,
            rippleCount: totalRippleCount
        )

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
                    self.triggerRipple(at: CGPoint(x: self.viewportSize.width * 0.5, y: 80), strength: 1.0)
                    HapticsManager.shared.playLiquidSnap()
                default:
                    break
                }
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "liquidglass" else { return }
        triggerRipple(at: CGPoint(x: viewportSize.width * 0.5, y: 90), strength: 0.92)
        HapticsManager.shared.tapMedium()
    }

    // MARK: - Strict Horizontal Single-Axis Dock Scrubbing

    func updateDockHorizontalScrub(clampedScreenX: CGFloat, velocityX: CGFloat, isDragging: Bool) {
        isScrubbingDockInternal = isDragging
        dockThumbTargetX = Float(clampedScreenX)
        let speedX = Float(abs(velocityX))
        let desiredStretch = 1.0 + min(0.30, speedX / 1500.0)
        if desiredStretch > dockThumbStretch {
            dockThumbStretch += (desiredStretch - dockThumbStretch) * 0.35
        }
    }

    func endDockHorizontalScrub() {
        isScrubbingDockInternal = false
        dockThumbTargetX = Float(dockSlotScreenX(index: selectedTab.rawValue, screenWidth: viewportSize.width))
        dockThumbStretchVel -= 1.8
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

    // MARK: - Droplet & Card Gesture Hooks (Pure Float Updates)

    func triggerRipple(at point: CGPoint, strength: Float = 0.80) {
        guard touchRipplesEnabled else { return }
        rippleCenter = SIMD2<Float>(Float(point.x), Float(point.y))
        rippleRadius = 8.0
        rippleStrength = min(1.0, max(0.25, strength))
        totalRippleCount += 1
        if liveActivityEnabled && totalRippleCount % 4 == 0 {
            syncLiveActivityNow()
        }
    }

    func triggerBeatPad(index: Int, screenPoint: CGPoint) {
        triggerRipple(at: screenPoint, strength: 0.92)
        lensLiftVel += 2.2
        companionLiftVel += 2.6
        HapticsManager.shared.playLiquidSnap()
    }

    func beginLensDrag() {
        isDropletSwallowedByIsland = false
        isDraggingLens = true
        lensDragStart = heroPos
        heroVel = .zero
        HapticsManager.shared.tapSoft(intensity: 0.55)
    }

    func updateLensDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if !isDraggingLens { beginLensDrag() }
        var targetX = lensDragStart.x + Float(translation.width)
        var targetY = lensDragStart.y + Float(translation.height)

        let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
        let distToIsland = simd_distance(SIMD2<Float>(targetX, targetY), isl)
        if distToIsland < 105.0 {
            let pullFactor = (1.0 - distToIsland / 105.0) * 0.44
            targetX += (isl.x - targetX) * pullFactor
            targetY += (isl.y - targetY) * pullFactor
        } else {
            let minX = animHalfSize.x * 0.85 + 8.0
            let maxX = Float(viewportSize.width) - animHalfSize.x * 0.85 - 8.0
            let maxY = Float(viewportSize.height - safeBottomInset) - 82.0 - animHalfSize.y * 0.85
            if targetX < minX { targetX = minX + (targetX - minX) * 0.32 }
            if targetX > maxX { targetX = maxX + (targetX - maxX) * 0.32 }
            if targetY > maxY { targetY = maxY + (targetY - maxY) * 0.32 }
        }

        heroPos = SIMD2<Float>(targetX, targetY)
        heroVel = heroVel * 0.35 + SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.65
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endLensDrag(velocity: CGSize) {
        isDraggingLens = false
        touchLightPos = nil
        let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
        if simd_distance(heroPos, isl) < 52.0 {
            swallowDropletIntoIsland()
            return
        }
        heroVel = clampVelocity(velocity, maxSpeed: 2600.0)
    }

    func beginCompanionDrag() {
        isDraggingCompanion = true
        companionDragStart = companionPos
        companionVel = .zero
        HapticsManager.shared.tapSoft(intensity: 0.50)
    }

    func updateCompanionDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if !isDraggingCompanion { beginCompanionDrag() }
        companionPos = companionDragStart + SIMD2<Float>(Float(translation.width), Float(translation.height))
        companionVel = companionVel * 0.35 + SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.65
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endCompanionDrag(velocity: CGSize) {
        isDraggingCompanion = false
        touchLightPos = nil
        companionVel = clampVelocity(velocity, maxSpeed: 2600.0)
    }

    private func clampVelocity(_ velocity: CGSize, maxSpeed: Float) -> SIMD2<Float> {
        var v = SIMD2<Float>(Float(velocity.width), Float(velocity.height))
        let speed = simd_length(v)
        if speed > maxSpeed { v = (v / speed) * maxSpeed }
        return v
    }

    func updateLensPinch(magnification: CGFloat) {
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
        lensShape = lensShape.next()
        lensLiftVel += 3.4
        lensStretchVel += 2.2
        triggerRipple(at: CGPoint(x: CGFloat(heroPos.x), y: CGFloat(heroPos.y)), strength: 0.72)
        HapticsManager.shared.playLiquidSnap()
    }

    func setCardLiveOffset(tab: DockTab, offset: CGSize) {
        let vec = SIMD2<Float>(Float(offset.width), Float(offset.height))
        switch tab {
        case .musicBeat: musicLiveOffset = vec
        case .controlHub: controlLiveOffset = vec
        case .weatherSolar: weatherLiveOffset = vec
        default: break
        }
    }

    func resetPlaygroundLayout() {
        isDropletSwallowedByIsland = false
        lensShape = .circle
        lensZoomScale = 1.0
        pinchStartScale = 1.0
        heroPos = SIMD2<Float>(Float(viewportSize.width * 0.40), Float(viewportSize.height * 0.49))
        companionPos = SIMD2<Float>(Float(viewportSize.width * 0.65), Float(viewportSize.height * 0.56))
        heroVel = SIMD2<Float>(-130, -170)
        companionVel = SIMD2<Float>(130, 130)
        musicLiveOffset = .zero
        controlLiveOffset = .zero
        weatherLiveOffset = .zero
        lensLiftVel += 3.0
        companionLiftVel += 3.0
        triggerRipple(at: CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.5), strength: 0.88)
        HapticsManager.shared.tapMedium()
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

    // MARK: - Pure 120Hz Lockstep Physics & Uniform Builder (Zero SwiftUI @State Writes!)

    func stepFrame(now: CFTimeInterval, drawablePointSize: CGSize) {
        if drawablePointSize.width > 40, drawablePointSize.height > 40 {
            viewportSize = drawablePointSize
        }

        let rawDt = (lastStepTime == 0) ? (1.0 / 120.0) : (now - lastStepTime)
        lastStepTime = now

        // Update FPS display at most every 0.5s and ONLY when integer changes
        if showFPS && rawDt > 0.0005 && rawDt < 0.5 {
            fpsFrameCount += 1
            fpsAccumDuration += rawDt
            if fpsAccumDuration >= 0.50 {
                let avgFps = Double(fpsFrameCount) / fpsAccumDuration
                let roundedFps = min(120, max(1, Int(avgFps.rounded())))
                let ms = (fpsAccumDuration / Double(fpsFrameCount)) * 1000.0
                if currentFPS != roundedFps {
                    currentFPS = roundedFps
                    currentFrameMs = ms
                }
                fpsFrameCount = 0
                fpsAccumDuration = 0
            }
        }

        let dt = Float(min(max(rawDt, 1.0 / 240.0), 1.0 / 28.0))
        let elapsed = Float(now - startTime)

        if isPlayingMusic && isMusicVisible {
            audioProgressAccum += Double(dt)
            if audioProgressAccum >= 0.50 {
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

        // Smooth internal float alphas for Metal UI cards (zero SwiftUI invalidation!)
        let fadeRate = min(1.0, dt * 15.0)
        labBarAlpha += ((isLensLabBarVisible ? 1.0 : 0.0) - labBarAlpha) * fadeRate
        musicAlpha += ((isMusicVisible ? 1.0 : 0.0) - musicAlpha) * fadeRate
        controlAlpha += ((isControlVisible ? 1.0 : 0.0) - controlAlpha) * fadeRate
        weatherAlpha += ((isWeatherVisible ? 1.0 : 0.0) - weatherAlpha) * fadeRate
        drawerAlpha += ((isStudioVisible ? 1.0 : 0.0) - drawerAlpha) * fadeRate

        stepSpring1D(pos: &companionReveal, vel: &companionRevealVel, target: (dualDropletEnabled && !isStudioVisible) ? 1.0 : 0.0, omega: 20.0, zeta: 0.72, dt: dt)
        companionReveal = min(1.0, max(0.0, companionReveal))

        stepSpring1D(pos: &heroVisibilityScale, vel: &heroVisibilityVel, target: isDropletSwallowedByIsland ? 0.0 : 1.0, omega: 24.0, zeta: 0.70, dt: dt)
        heroVisibilityScale = min(1.15, max(0.0, heroVisibilityScale))

        spotlightAnim += ((flashlightOn ? 1.0 : 0.0) - spotlightAnim) * min(1.0, dt * 14.0)

        stepDockHorizontalPhysics(dt: dt)
        stepDropletsPhysics(dt: dt)
        buildUniformBuffers(dt: dt, elapsed: elapsed)
    }

    private func stepDockHorizontalPhysics(dt: Float) {
        if !isScrubbingDockInternal {
            dockThumbTargetX = Float(dockSlotScreenX(index: selectedTab.rawValue, screenWidth: viewportSize.width))
        }

        // Strict X-only spring integration + strict Dock interior clamping
        let dW = Float(dockWidth(for: viewportSize.width))
        let dockLeft = (Float(viewportSize.width) - dW) * 0.5
        let slotW = (dW - 12.0) / Float(DockTab.allCases.count)
        let minCenterX = dockLeft + 6.0 + slotW * 0.5
        let maxCenterX = dockLeft + dW - 6.0 - slotW * 0.5

        let clampedTargetX = min(max(dockThumbTargetX, minCenterX), maxCenterX)
        stepSpring1D(
            pos: &dockThumbX,
            vel: &dockThumbVelX,
            target: clampedTargetX,
            omega: isScrubbingDockInternal ? 38.0 : 28.0,
            zeta: isScrubbingDockInternal ? 0.72 : 0.68,
            dt: dt
        )
        dockThumbX = min(max(dockThumbX, minCenterX), maxCenterX)

        stepSpring1D(pos: &dockThumbLift, vel: &dockThumbLiftVel, target: isScrubbingDockInternal ? 1.0 : 0.0, omega: 28.0, zeta: 0.64, dt: dt)
        let speedX = abs(dockThumbVelX)
        stepSpring1D(pos: &dockThumbStretch, vel: &dockThumbStretchVel, target: 1.0 + min(0.24, speedX / 1500.0), omega: 28.0, zeta: 0.46, dt: dt)
        dockThumbStretch = min(max(dockThumbStretch, 0.84), 1.32)
    }

    private func stepDropletsPhysics(dt: Float) {
        let targetHalf = lensShape.baseHalfSize * lensZoomScale
        let targetCorner = lensShape.baseCornerRadius * lensZoomScale
        stepSpring2D(pos: &animHalfSize, vel: &animHalfSizeVel, target: targetHalf, omega: 20.0, zeta: 0.68, dt: dt)
        stepSpring1D(pos: &animCornerRadius, vel: &animCornerVel, target: targetCorner, omega: 20.0, zeta: 0.68, dt: dt)

        stepSpring1D(pos: &lensLiftScale, vel: &lensLiftVel, target: isDraggingLens ? 1.06 : 1.0, omega: 24.0, zeta: 0.58, dt: dt)
        stepSpring1D(pos: &companionLiftScale, vel: &companionLiftVel, target: isDraggingCompanion ? 1.08 : 1.0, omega: 24.0, zeta: 0.58, dt: dt)

        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)
        let effectiveHalf = animHalfSize * max(0.2, lensLiftScale * max(0.2, heroVisibilityScale))
        let compRad = 52.0 * max(0.5, companionLiftScale)

        let gravityAccel = gravityModeEnabled ? (motionManager.screenGravity * 920.0) : SIMD2<Float>(0, 0)
        let dragRate: Float = gravityModeEnabled ? 0.85 : 2.05

        // Keep droplets above open Studio Drawer when Studio is visible so specimen stays in clear sight!
        let bottomWall = isStudioVisible
            ? (h - Float(safeBottomInset) - 446.0)
            : (h - Float(safeBottomInset) - 86.0)

        if !isDraggingLens && !isDropletSwallowedByIsland {
            heroVel += gravityAccel * dt
            heroPos += heroVel * dt
            heroVel *= exp(-dragRate * dt)

            let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
            if simd_distance(heroPos, isl) < 46.0 && heroVel.y < -35.0 {
                swallowDropletIntoIsland()
                return
            }

            let minX = effectiveHalf.x + 10.0
            let maxX = max(minX + 1.0, w - effectiveHalf.x - 10.0)
            let minY = Float(safeTopInset) + 48.0 + effectiveHalf.y
            let maxY = max(minY + 1.0, bottomWall - effectiveHalf.y)
            let rest: Float = 0.75

            if heroPos.x < minX {
                let spd = abs(heroVel.x); heroPos.x = minX
                if heroVel.x < 0 { heroVel.x = -heroVel.x * rest; injectLensSquish(angle: 0, speed: spd) }
            } else if heroPos.x > maxX {
                let spd = abs(heroVel.x); heroPos.x = maxX
                if heroVel.x > 0 { heroVel.x = -heroVel.x * rest; injectLensSquish(angle: 0, speed: spd) }
            }
            if heroPos.y < minY {
                let spd = abs(heroVel.y); heroPos.y = minY
                if heroVel.y < 0 { heroVel.y = -heroVel.y * rest; injectLensSquish(angle: .pi * 0.5, speed: spd) }
            } else if heroPos.y > maxY {
                let spd = abs(heroVel.y); heroPos.y = maxY
                if heroVel.y > 0 { heroVel.y = -heroVel.y * rest; injectLensSquish(angle: .pi * 0.5, speed: spd) }
            }

            if !gravityModeEnabled && simd_length(heroVel) < 2.0 { heroVel = .zero }
        }

        if companionReveal > 0.02 {
            if !isDraggingCompanion {
                companionVel += gravityAccel * dt

                if metaballFusionEnabled && !isDropletSwallowedByIsland {
                    let delta = heroPos - companionPos
                    let dist = simd_length(delta)
                    let mergeBand = max(effectiveHalf.x, effectiveHalf.y) + compRad + 32.0
                    if dist > 26.0 && dist < mergeBand {
                        companionVel += (delta / dist) * 165.0 * dt
                    }
                }

                companionPos += companionVel * dt
                companionVel *= exp(-dragRate * dt)

                let cMinX = compRad + 10.0
                let cMaxX = max(cMinX + 1.0, w - compRad - 10.0)
                let cMinY = Float(safeTopInset) + 48.0 + compRad
                let cMaxY = max(cMinY + 1.0, bottomWall - compRad)
                let rest: Float = 0.78

                if companionPos.x < cMinX {
                    let spd = abs(companionVel.x); companionPos.x = cMinX
                    if companionVel.x < 0 { companionVel.x = -companionVel.x * rest; injectCompanionSquish(angle: 0, speed: spd) }
                } else if companionPos.x > cMaxX {
                    let spd = abs(companionVel.x); companionPos.x = cMaxX
                    if companionVel.x > 0 { companionVel.x = -companionVel.x * rest; injectCompanionSquish(angle: 0, speed: spd) }
                }
                if companionPos.y < cMinY {
                    let spd = abs(companionVel.y); companionPos.y = cMinY
                    if companionVel.y < 0 { companionVel.y = -companionVel.y * rest; injectCompanionSquish(angle: .pi * 0.5, speed: spd) }
                } else if companionPos.y > cMaxY {
                    let spd = abs(companionVel.y); companionPos.y = cMaxY
                    if companionVel.y > 0 { companionVel.y = -companionVel.y * rest; injectCompanionSquish(angle: .pi * 0.5, speed: spd) }
                }

                if !gravityModeEnabled && simd_length(companionVel) < 2.0 { companionVel = .zero }
            }

            if metaballFusionEnabled && !isDropletSwallowedByIsland {
                let dist = simd_distance(heroPos, companionPos)
                let nowFused = dist < (min(effectiveHalf.x, effectiveHalf.y) + compRad + 22.0)
                if nowFused != wasDropletsFused {
                    wasDropletsFused = nowFused
                    let mid = (heroPos + companionPos) * 0.5
                    if nowFused {
                        HapticsManager.shared.tapSoft(intensity: 0.58)
                    } else {
                        lensStretchVel -= 2.0
                        companionStretchVel -= 2.4
                        triggerRipple(at: CGPoint(x: CGFloat(mid.x), y: CGFloat(mid.y)), strength: 0.76)
                        HapticsManager.shared.playLiquidSnap()
                    }
                }
            }
        }

        updateDropletStretch(vel: heroVel, angle: &lensStretchAngle, stretch: &lensStretchFactor, stretchVel: &lensStretchVel, dt: dt)
        updateDropletStretch(vel: companionVel, angle: &companionStretchAngle, stretch: &companionStretchFactor, stretchVel: &companionStretchVel, dt: dt)
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
        stepSpring1D(pos: &stretch, vel: &stretchVel, target: 1.0 + min(0.26, speed / 2450.0), omega: 26.0, zeta: 0.40, dt: dt)
        stretch = min(max(stretch, 0.74), 1.38)
    }

    private func injectLensSquish(angle: Float, speed: Float) {
        guard speed > 75.0 else { return }
        lensStretchAngle = angle
        lensStretchVel -= min(4.0, speed * 0.0036)
        HapticsManager.shared.wallBounce(speed: speed)
    }

    private func injectCompanionSquish(angle: Float, speed: Float) {
        guard speed > 75.0 else { return }
        companionStretchAngle = angle
        companionStretchVel -= min(4.0, speed * 0.0038)
        HapticsManager.shared.wallBounce(speed: speed)
    }

    private func buildUniformBuffers(dt: Float, elapsed: Float) {
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)

        var desiredLight = gyroEnabled
            ? motionManager.targetLightDir
            : SIMD2<Float>(cos(elapsed * 0.45) * 0.55 - 0.35, sin(elapsed * 0.38) * 0.45 - 0.68)

        if let touch = touchLightPos {
            let delta = touch - heroPos
            let len = simd_length(delta)
            if len > 8.0 { desiredLight = simd_normalize(desiredLight * 0.55 + (delta / len) * 0.45) }
        }

        currentLightDir += (desiredLight - currentLightDir) * min(1.0, dt * 14.0)
        let normLight = simd_length(currentLightDir) > 1e-3 ? simd_normalize(currentLightDir) : SIMD2<Float>(-0.58, -0.81)

        let cardW = min(w - 32.0, 346.0)
        let controlCenterPt = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 188.0) + controlLiveOffset
        let spotOrigin = (controlAlpha > 0.05)
            ? SIMD2<Float>(controlCenterPt.x - cardW * 0.32, controlCenterPt.y - 46.0)
            : SIMD2<Float>(w * 0.5, Float(safeTopInset) + 20.0)

        let textMix: Float = (wallpaper == .customPhoto) ? (showTypographyOnPhoto ? 0.72 : 0.0) : 1.0
        let solarWarmth: Float = weatherAlpha > 0.02
            ? (weatherAlpha * (-cos(Float((solarHour / 24.0) * 2.0 * .pi)) * 0.55 + sin(Float((solarHour / 24.0) * 4.0 * .pi)) * 0.25))
            : 0.0

        var count = 0

        // 1. Playground Droplets FIRST (so UI cards & Dock always sit cleanly on top of droplets without white circle bleed!)
        if heroVisibilityScale > 0.02 && count < 11 {
            let effHalf = animHalfSize * max(0.15, lensLiftScale * heroVisibilityScale)
            let effCorner = animCornerRadius * max(0.15, lensLiftScale * heroVisibilityScale)
            let fuseWithCompanion = metaballFusionEnabled && (companionReveal > 0.02)
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(heroPos.x, heroPos.y, effHalf.x, effHalf.y),
                shapeAndTransform: SIMD4<Float>(effCorner, lensStretchAngle, lensStretchFactor, isDraggingLens ? 1.32 : 1.18),
                styleParams: SIMD4<Float>(min(1.0, heroVisibilityScale), 1.04, 0.0, isDraggingLens ? 1.32 : 1.02),
                tintOverride: SIMD4<Float>(0.0, 0.0, 0.0, fuseWithCompanion ? -1.0 : -2.0)
            )
            count += 1
        }

        if companionReveal > 0.02 && count < 11 {
            let r = 52.0 * companionLiftScale * (0.35 + 0.65 * companionReveal)
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(companionPos.x, companionPos.y, r, r),
                shapeAndTransform: SIMD4<Float>(r, companionStretchAngle, companionStretchFactor, isDraggingCompanion ? 1.32 : 1.18),
                styleParams: SIMD4<Float>(companionReveal, 1.06, -0.25, isDraggingCompanion ? 1.28 : 1.0),
                tintOverride: SIMD4<Float>(0.35, 0.92, 1.0, 0.05)
            )
            count += 1
        }

        // 2. When in Custom Metal Optics mode, render UI Cards + Dock Track + Dock Selection Capsule in strict Z-Order!
        if !useNativeSystemGlass {
            if labBarAlpha > 0.01 && count < 11 {
                let pillHalfW = min(w - 32.0, 336.0) * 0.5
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, Float(safeTopInset) + 78.0, pillHalfW, 24.0),
                    shapeAndTransform: SIMD4<Float>(24.0, 0.0, 1.0, 1.08),
                    styleParams: SIMD4<Float>(labBarAlpha, 0.55, 0.55, 0.85),
                    tintOverride: SIMD4<Float>(0.25, 0.88, 1.0, gravityModeEnabled ? 0.14 : 0.04)
                )
                count += 1
            }

            if musicAlpha > 0.01 && count < 11 {
                let mCenter = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 152.0) + musicLiveOffset
                let trackTint = currentTrack.shaderTint
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(mCenter.x, mCenter.y, cardW * 0.5, 88.0),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, 1.10),
                    styleParams: SIMD4<Float>(musicAlpha, 0.58, 0.55, 0.96),
                    tintOverride: SIMD4<Float>(trackTint.x, trackTint.y, trackTint.z, isPlayingMusic ? 0.13 : 0.04)
                )
                count += 1
            }

            if controlAlpha > 0.01 && count < 11 {
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(controlCenterPt.x, controlCenterPt.y, cardW * 0.5, 126.0),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, flashlightOn ? 1.35 : 1.10),
                    styleParams: SIMD4<Float>(controlAlpha, 0.56, 0.65, 0.98),
                    tintOverride: SIMD4<Float>(0.96, 0.88, 0.58, flashlightOn ? 0.14 : 0.03)
                )
                count += 1
            }

            if weatherAlpha > 0.01 && count < 11 {
                let wCenter = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 168.0) + weatherLiveOffset
                let wTint = weatherCondition.shaderTint
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(wCenter.x, wCenter.y, cardW * 0.5, 98.0),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, 1.12),
                    styleParams: SIMD4<Float>(weatherAlpha, 0.56, 0.58, 0.98),
                    tintOverride: SIMD4<Float>(wTint.x, wTint.y, wTint.z, 0.14)
                )
                count += 1
            }

            if drawerAlpha > 0.01 && count < 10 {
                let drawerH: Float = 388.0
                let drawerHalfW = min(w - 24.0, 366.0) * 0.5
                let drawerBaseY = h - Float(safeBottomInset) - 80.0 - drawerH * 0.5
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, drawerBaseY, drawerHalfW, drawerH * 0.5),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, 1.12),
                    styleParams: SIMD4<Float>(drawerAlpha, 0.52, 0.95, 1.15),
                    tintOverride: SIMD4<Float>(0.07, 0.11, 0.20, tintMode == .light ? 0.0 : 0.22)
                )
                count += 1
            }

            // Dock Layer 1: Dock Frosted Base Plate (height 64 -> halfH 32)
            let dockW = Float(dockWidth(for: viewportSize.width))
            let dockY = Float(dockCenterY(for: viewportSize.height, safeBottom: safeBottomInset))
            if count < 11 {
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, dockY, dockW * 0.5, 32.0),
                    shapeAndTransform: SIMD4<Float>(32.0, 0.0, 1.0, 1.05),
                    styleParams: SIMD4<Float>(1.0, 0.50, 0.78, 0.92),
                    tintOverride: SIMD4<Float>(0.90, 0.96, 1.0, 0.04)
                )
                count += 1
            }

            // Dock Layer 2: Horizontal-Locked Refracting Selection Capsule (Strictly Above Dock Plate & Clamped Inside!)
            if count < 12 {
                let lift = min(1.0, max(0.0, dockThumbLift))
                let slotW = (dockW - 12.0) / Float(DockTab.allCases.count)
                let pillHalfW = (slotW * 0.47) * (1.0 + 0.05 * lift)
                let pillHalfH: Float = 26.0 // 52pt tall inside 64pt Dock -> 6pt crisp margin!
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(dockThumbX, dockY, pillHalfW, pillHalfH),
                    shapeAndTransform: SIMD4<Float>(pillHalfH, 0.0, dockThumbStretch, 1.18 + 0.35 * lift),
                    styleParams: SIMD4<Float>(0.78 + 0.20 * lift, 0.85 + 0.40 * lift, -3.8, 0.55 + 0.45 * lift),
                    tintOverride: SIMD4<Float>(0.32, 0.92, 1.0, 0.12)
                )
                count += 1
            }
        }

        let islCenter = hardwareIslandCenter
        sceneUniforms = SceneUniforms(
            viewportAndTime: SIMD4<Float>(w, h, elapsed, Float(wallpaper.rawValue)),
            opticalParams: SIMD4<Float>(Float(refraction), Float(bezel), Float(dispersion), Float(frost)),
            lightingParams: SIMD4<Float>(normLight.x, normLight.y, Float(tintMode.rawValue), Float(sceneBrightness)),
            spotlightParams: SIMD4<Float>(spotOrigin.x, spotOrigin.y, -normLight.x * 0.45, spotlightAnim),
            layerFlags: SIMD4<Float>(Float(count), hasCustomPhoto ? 1.0 : 0.0, customPhotoAspect, textMix),
            rippleParams: SIMD4<Float>(rippleCenter.x, rippleCenter.y, rippleRadius, rippleStrength),
            atmosphereParams: SIMD4<Float>(solarWarmth, prismRimBoostEnabled ? 1.35 : 1.0, 36.0, Float(islandHeightPt * 0.5)),
            islandParams: SIMD4<Float>(Float(islCenter.x), Float(islCenter.y), Float(islandWidthPt * 0.5), islandPullStretchPt)
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
