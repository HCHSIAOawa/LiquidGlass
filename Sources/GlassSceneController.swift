import SwiftUI
import UIKit
import QuartzCore
import Observation
import ActivityKit
import simd

@MainActor
@Observable
final class GlassSceneController {
    // MARK: - Dual Engine Mode (Auto-Switches to Metal Optics when Optical Sliders Move)

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

    func activateMetalOpticsIfNeeded() {
        if engineMode != .customMetalOptics {
            engineMode = .customMetalOptics
        }
    }

    // MARK: - Active Bottom Tab (Default Tab 0 = Flagship Focus Liquid Hourglass!)

    var selectedTab: DockTab = .focusHourglass {
        didSet {
            guard selectedTab != oldValue else { return }
            if selectedTab != .focusHourglass && isZenMode {
                isZenMode = false
            }
            if selectedTab == .opticalStudio {
                // Keep Hero Specimen Lens visible above Studio Drawer for live optical preview
                let clearUpperY = Float(safeTopInset) + 148.0
                if heroSpring.pos.y > clearUpperY + 40.0 || isDropletSwallowedByIsland {
                    isDropletSwallowedByIsland = false
                    heroSpring.pos = SIMD2<Float>(Float(viewportSize.width) * 0.5, clearUpperY)
                    heroSpring.vel = SIMD2<Float>(0.0, -45.0)
                }
            }
            if selectedTab.isMainCapsuleTab {
                dockThumbTargetX = Float(dockMainSlotScreenX(index: selectedTab.rawValue, screenWidth: viewportSize.width))
            }
        }
    }

    var pinnedMusic: Bool = false
    var pinnedControl: Bool = false

    // MARK: - Flagship Liquid Hourglass Pomodoro States (Discrete UI State Only — Zero 120Hz Churn!)

    var pomodoroMode: PomodoroMode = .focus
    var targetMinutes: Int = 25
    var isPomodoroRunning: Bool = false
    var isZenMode: Bool = false
    var completedPomodoros: Int = 0

    /// Updated ONLY once per integer second change (<= 1Hz) — never per 120fps frame!
    private(set) var displayRemainingSeconds: Int = 25 * 60

    var dropletHapticsEnabled: Bool = true {
        didSet {
            HapticsManager.shared.dropletResonanceEnabled = dropletHapticsEnabled
            if dropletHapticsEnabled {
                HapticsManager.shared.playDropletResonance()
            }
        }
    }

    var flipToStartEnabled: Bool = true

    // MARK: - iPhone 18 Pro Compact Hardware Cutout Calibration (Default 88x32 @ Top 12pt, #000000)

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

    var wallpaper: WallpaperPreset = .aurora
    var tintMode: GlassTintMode = .clear
    var lensShape: LensShapeMode = .circle

    var refraction: Double = 56.0
    var bezel: Double = 36.0
    var dispersion: Double = 0.17
    var frost: Double = 0.22

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

    // MARK: - Control Hub & Music States

    var flashlightOn: Bool = false
    var sceneBrightness: Double = 1.0

    var isPlayingMusic: Bool = true
    var currentTrackIndex: Int = 0
    var trackProgress: Double = 0.28

    var currentTrack: MusicTrack {
        MusicTrack.catalog[currentTrackIndex % MusicTrack.catalog.count]
    }

    var isFocusTabActive: Bool { selectedTab == .focusHourglass }
    var isLensLabBarVisible: Bool { selectedTab == .lensLab && !isZenMode }
    var isMusicVisible: Bool { (selectedTab == .musicBeat || pinnedMusic) && !isZenMode }
    var isControlVisible: Bool { (selectedTab == .controlHub || pinnedControl) && !isZenMode }
    var isStudioVisible: Bool { selectedTab == .opticalStudio && !isZenMode }

    // Throttled FPS badge readout (updated at most 2x/sec ONLY when integer changes)
    private(set) var currentFPS: Int = 120
    private(set) var currentFrameMs: Double = 8.3

    var hasCustomPhoto: Bool = false

    // MARK: - Observation-Ignored Pure 120Hz GPU & Velocity-Preserving Physics State

    @ObservationIgnored var sceneUniforms = SceneUniforms()
    @ObservationIgnored var elementUniforms = [GlassElementUniform](repeating: GlassElementUniform(), count: 16)
    @ObservationIgnored var hourglassUniforms = HourglassUniforms()

    @ObservationIgnored var customPhotoImage: UIImage?
    @ObservationIgnored var customPhotoRevision: Int = 0
    @ObservationIgnored var customPhotoAspect: Float = 0.75

    @ObservationIgnored private let motionManager = MotionManager()
    @ObservationIgnored private var intentObserver: NSObjectProtocol?

    @ObservationIgnored private var hasInitializedLayout: Bool = false
    @ObservationIgnored private(set) var safeTopInset: CGFloat = 54
    @ObservationIgnored private(set) var safeBottomInset: CGFloat = 34
    @ObservationIgnored private(set) var viewportSize: CGSize = CGSize(width: 393, height: 852)

    // Fixed 120Hz physics substep accumulator (exact dt = 1/120s)
    @ObservationIgnored private let fixedDt: Float = 1.0 / 120.0
    @ObservationIgnored private var physicsAccumulator: Float = 0.0

    // Pomodoro high-precision continuous clock & fluid dynamics
    @ObservationIgnored private var pomodoroTotalSec: Double = 25.0 * 60.0
    @ObservationIgnored private var pomodoroRemainingSec: Double = 25.0 * 60.0
    @ObservationIgnored private var pomodoroEndTimestamp: Date? = nil

    @ObservationIgnored private var hourglassVisSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var flipAngleSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var upperFillSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var lowerFillSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var modeBlendSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var zenGlowSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var dockVisibilitySpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var liquidTiltSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var sloshImpulseTouchX: Float? = nil

    // Droplet Pinch-Off Cascade cycle
    @ObservationIgnored private var dropletCyclePhase: Float = 0.0
    @ObservationIgnored private var didTriggerImpactInCycle: Bool = false
    @ObservationIgnored private var impactWavePhase: Float = 0.0
    @ObservationIgnored private var impactStrength: Float = 0.0
    @ObservationIgnored private var causticBloom: Float = 0.15
    @ObservationIgnored private var streamActiveSpring = Spring1D(pos: 0.0)

    // Tactile Radial Optical Time Dial (5..60 min)
    @ObservationIgnored private var isDraggingDial: Bool = false
    @ObservationIgnored private var isDraggingDialToIsland: Bool = false
    @ObservationIgnored private var dialDetachedPos = Spring2D(pos: .zero)
    @ObservationIgnored private var dialMinutesSpring = Spring1D(pos: 25.0)
    @ObservationIgnored private var dialVisibilitySpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var dialDragGlowSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var dialKnobStretchSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var dialTangentAngle: Float = 0.0
    @ObservationIgnored private var lastDialRatchetMinute: Int = 25
    @ObservationIgnored private var lastDialTouchAngle: Float = 0.0

    // Hero Droplet & OLED Black-Hole Island Swallow state (Velocity-Preserving Spring2D!)
    @ObservationIgnored private(set) var isDropletSwallowedByIsland: Bool = false
    @ObservationIgnored private var isDraggingLens: Bool = false
    @ObservationIgnored private var lensDragAnchor = SIMD2<Float>(0, 0)
    @ObservationIgnored private var lensDragTarget = SIMD2<Float>(0, 0)
    @ObservationIgnored private var heroSpring = Spring2D(pos: SIMD2<Float>(162, 430))
    @ObservationIgnored private var lensZoomScale: Float = 1.0
    @ObservationIgnored private var pinchStartScale: Float = 1.0

    @ObservationIgnored private var animHalfSizeSpring = Spring2D(pos: SIMD2<Float>(84, 84))
    @ObservationIgnored private var animCornerSpring = Spring1D(pos: 84)
    @ObservationIgnored private var lensLiftSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var lensStretchSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var lensStretchAngle: Float = 0.0
    @ObservationIgnored private var heroVisibilitySpring = Spring1D(pos: 0.0)

    // Hardware Cutout Pull-Down state
    @ObservationIgnored private var islandPullStretchPt: Float = 0.0
    @ObservationIgnored private var hasTriggeredPullAction: Bool = false

    // Companion Droplet state (Velocity-Preserving Spring2D!)
    @ObservationIgnored private var isDraggingCompanion: Bool = false
    @ObservationIgnored private var companionDragAnchor = SIMD2<Float>(0, 0)
    @ObservationIgnored private var companionDragTarget = SIMD2<Float>(0, 0)
    @ObservationIgnored private var companionSpring = Spring2D(pos: SIMD2<Float>(258, 510))
    @ObservationIgnored private var companionLiftSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var companionStretchSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var companionStretchAngle: Float = 0.0
    @ObservationIgnored private var companionRevealSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var wasDropletsFused: Bool = true

    // Two-Part Single-Axis Horizontal Dock Physics (Y Strictly Locked!)
    @ObservationIgnored private var dockThumbSpring = Spring1D(pos: 80.0)
    @ObservationIgnored private var dockThumbTargetX: Float = 80.0
    @ObservationIgnored private var isScrubbingDockInternal: Bool = false
    @ObservationIgnored private var dockThumbLiftSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var dockThumbStretchSpring = Spring1D(pos: 1.0)
    @ObservationIgnored private var studioOrbScaleSpring = Spring1D(pos: 1.0)

    // Velocity-preserving Card springs for Metal backing plates
    @ObservationIgnored private var musicOffsetSpring = Spring2D(pos: .zero)
    @ObservationIgnored private var musicTargetOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var controlOffsetSpring = Spring2D(pos: .zero)
    @ObservationIgnored private var controlTargetOffset = SIMD2<Float>(0, 0)

    @ObservationIgnored private var labBarAlphaSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var musicAlphaSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var controlAlphaSpring = Spring1D(pos: 0.0)
    @ObservationIgnored private var drawerAlphaSpring = Spring1D(pos: 0.0)

    // Shockwave ripple & lighting
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
        let savedW = UserDefaults.standard.double(forKey: "lg.islandWidthPt")
        if savedW >= 60 && savedW <= 140 { islandWidthPt = savedW }
        let savedH = UserDefaults.standard.double(forKey: "lg.islandHeightPt")
        if savedH >= 20 && savedH <= 46 { islandHeightPt = savedH }
        let savedTop = UserDefaults.standard.double(forKey: "lg.islandTopMarginPt")
        if savedTop >= 4 && savedTop <= 30 { islandTopMarginPt = savedTop }

        motionManager.onPhoneFlipDetected = { [weak self] in
            guard let self = self, self.flipToStartEnabled else { return }
            self.handlePhysicalPhoneFlip()
        }
        motionManager.setEnabled(true)
        observeLiveActivityIntents()
    }

    // MARK: - Geometry & Two-Part Apple Native Dock Layout Helpers

    var hardwareIslandCenter: CGPoint {
        CGPoint(
            x: viewportSize.width * 0.5,
            y: CGFloat(islandTopMarginPt + islandHeightPt * 0.5)
        )
    }

    var hourglassCenter: CGPoint {
        let baseY = viewportSize.height * 0.455
        let zenShift: CGFloat = isZenMode ? 18.0 : 0.0
        return CGPoint(x: viewportSize.width * 0.5, y: baseY + zenShift)
    }

    var radialDialRadiusPt: CGFloat {
        min(viewportSize.width * 0.375, 148.0)
    }

    let dockHeight: CGFloat = 62.0
    let dockSplitGap: CGFloat = 10.0
    let dockStudioOrbDiameter: CGFloat = 62.0

    /// Total reference width used to compute the 78% Left Main Capsule + 10pt Gap + Right Studio Orb.
    func dockMainCapsuleWidth(for screenWidth: CGFloat) -> CGFloat {
        let avail = min(screenWidth - 24.0, 368.0)
        return floor(avail * 0.78)
    }

    func dockTotalAssemblyWidth(for screenWidth: CGFloat) -> CGFloat {
        dockMainCapsuleWidth(for: screenWidth) + dockSplitGap + dockStudioOrbDiameter
    }

    func dockAssemblyLeft(for screenWidth: CGFloat) -> CGFloat {
        (screenWidth - dockTotalAssemblyWidth(for: screenWidth)) * 0.5
    }

    func dockMainCapsuleCenterX(for screenWidth: CGFloat) -> CGFloat {
        let mainW = dockMainCapsuleWidth(for: screenWidth)
        return dockAssemblyLeft(for: screenWidth) + mainW * 0.5
    }

    func dockStudioOrbCenterX(for screenWidth: CGFloat) -> CGFloat {
        let mainW = dockMainCapsuleWidth(for: screenWidth)
        return dockAssemblyLeft(for: screenWidth) + mainW + dockSplitGap + dockStudioOrbDiameter * 0.5
    }

    func dockCenterY(for screenHeight: CGFloat, safeBottom: CGFloat) -> CGFloat {
        screenHeight - safeBottom - 35.0
    }

    func dockMainSlotScreenX(index: Int, screenWidth: CGFloat) -> CGFloat {
        let clampedIdx = min(max(index, 0), DockTab.mainCapsuleTabs.count - 1)
        let mainW = dockMainCapsuleWidth(for: screenWidth)
        let innerPad: CGFloat = 5.0
        let slotW = (mainW - innerPad * 2.0) / CGFloat(DockTab.mainCapsuleTabs.count)
        return dockAssemblyLeft(for: screenWidth) + innerPad + slotW * (CGFloat(clampedIdx) + 0.5)
    }

    func updateGeometry(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        guard size.width > 40, size.height > 40 else { return }
        viewportSize = size
        safeTopInset = safeTop
        safeBottomInset = safeBottom

        if !hasInitializedLayout {
            hasInitializedLayout = true
            heroSpring.pos = SIMD2<Float>(Float(size.width * 0.40), Float(size.height * 0.49))
            companionSpring.pos = SIMD2<Float>(Float(size.width * 0.65), Float(size.height * 0.56))

            let initX = Float(dockMainSlotScreenX(index: 0, screenWidth: size.width))
            dockThumbSpring.pos = initX
            dockThumbTargetX = initX

            if liveActivityEnabled {
                syncLiveActivityNow()
            }
        }
    }

    // MARK: - Pomodoro Controls, Flip Physics & Tactile Radial Time Dial

    func togglePomodoroStartPause() {
        if isPomodoroRunning {
            pausePomodoro()
        } else {
            startPomodoro()
        }
    }

    func startPomodoro() {
        if pomodoroRemainingSec <= 0.8 {
            pomodoroTotalSec = Double(targetMinutes * 60)
            pomodoroRemainingSec = pomodoroTotalSec
            displayRemainingSeconds = Int(pomodoroRemainingSec.rounded())
        }
        let now = Date()
        pomodoroEndTimestamp = now.addingTimeInterval(pomodoroRemainingSec)
        isPomodoroRunning = true
        dropletCyclePhase = 0.04
        didTriggerImpactInCycle = false
        HapticsManager.shared.tapMedium(intensity: 0.86)
        triggerRipple(at: hourglassCenter, strength: 0.72)
        syncLiveActivityNow()
    }

    func pausePomodoro() {
        if let end = pomodoroEndTimestamp {
            pomodoroRemainingSec = max(0.0, end.timeIntervalSinceNow)
        }
        pomodoroEndTimestamp = nil
        isPomodoroRunning = false
        if isZenMode { isZenMode = false }
        displayRemainingSeconds = max(0, Int(pomodoroRemainingSec.rounded()))
        HapticsManager.shared.tapLight(intensity: 0.68)
        syncLiveActivityNow()
    }

    func flipAndResetPomodoro(autoStart: Bool = false) {
        // Rotate 180° from -pi -> 0 smoothly using 120Hz velocity-preserving spring!
        flipAngleSpring.pos = -.pi
        flipAngleSpring.vel = 3.8

        pomodoroTotalSec = Double(targetMinutes * 60)
        pomodoroRemainingSec = pomodoroTotalSec
        displayRemainingSeconds = targetMinutes * 60
        dropletCyclePhase = 0.0
        didTriggerImpactInCycle = false

        if autoStart {
            pomodoroEndTimestamp = Date().addingTimeInterval(pomodoroTotalSec)
            isPomodoroRunning = true
        } else {
            pomodoroEndTimestamp = nil
            isPomodoroRunning = false
        }

        triggerRipple(at: hourglassCenter, strength: 0.90)
        HapticsManager.shared.playLiquidSnap()
        syncLiveActivityNow()
    }

    func switchPomodoroMode(to newMode: PomodoroMode? = nil) {
        let next = newMode ?? pomodoroMode.toggled()
        pomodoroMode = next
        targetMinutes = next.defaultMinutes
        lastDialRatchetMinute = targetMinutes
        pomodoroTotalSec = Double(targetMinutes * 60)
        pomodoroRemainingSec = pomodoroTotalSec
        pomodoroEndTimestamp = nil
        isPomodoroRunning = false
        displayRemainingSeconds = targetMinutes * 60

        // Gentle physical hourglass flip transition when switching Focus <-> Rest
        flipAngleSpring.pos = -.pi
        flipAngleSpring.vel = 3.2

        triggerRipple(at: hourglassCenter, strength: 0.82)
        HapticsManager.shared.playLiquidSnap()
        syncLiveActivityNow()
    }

    func handlePhysicalPhoneFlip() {
        // Physical iPhone inversion / face-down flip starts or resets-and-restarts the hourglass!
        if selectedTab != .focusHourglass {
            selectedTab = .focusHourglass
        }
        let shouldStart = !isPomodoroRunning || pomodoroRemainingSec < pomodoroTotalSec - 2.0
        flipAndResetPomodoro(autoStart: shouldStart)
    }

    func handleHourglassDoubleTap() {
        if pomodoroRemainingSec <= 0.8 {
            flipAndResetPomodoro(autoStart: true)
        } else {
            togglePomodoroStartPause()
        }
    }

    func toggleZenMode() {
        setZenMode(!isZenMode)
    }

    func setZenMode(_ enabled: Bool) {
        guard isZenMode != enabled else { return }
        isZenMode = enabled
        triggerRipple(at: hourglassCenter, strength: 0.65)
        HapticsManager.shared.tapSoft(intensity: 0.62)
    }

    // MARK: - Radial Optical Time Dial Hit-Test & Velocity-Preserving Scrub (5..60 min)

    private func dialKnobScreenPosition() -> SIMD2<Float> {
        if isDraggingDialToIsland {
            return dialDetachedPos.pos
        }
        let c = SIMD2<Float>(Float(hourglassCenter.x), Float(hourglassCenter.y))
        let r = Float(radialDialRadiusPt)
        let norm = min(max((dialMinutesSpring.pos - 5.0) / 55.0, 0.0), 1.0)
        let cwAngle = norm * 2.0 * Float.pi
        return c + SIMD2<Float>(sin(cwAngle) * r, -cos(cwAngle) * r)
    }

    func hitTestRadialTimeDial(at point: CGPoint) -> Bool {
        guard selectedTab == .focusHourglass && !isPomodoroRunning && !isZenMode else { return false }
        let p = SIMD2<Float>(Float(point.x), Float(point.y))
        let knob = dialKnobScreenPosition()
        if simd_distance(p, knob) <= 38.0 {
            return true
        }
        let c = SIMD2<Float>(Float(hourglassCenter.x), Float(hourglassCenter.y))
        let dist = simd_distance(p, c)
        let r = Float(radialDialRadiusPt)
        return abs(dist - r) <= 28.0
    }

    func hitTestHourglassBody(at point: CGPoint) -> Bool {
        guard selectedTab == .focusHourglass else { return false }
        let c = hourglassCenter
        return abs(point.x - c.x) <= 72.0 && abs(point.y - c.y) <= 126.0
    }

    func beginDialScrub(at location: CGPoint) {
        isDraggingDial = true
        isDraggingDialToIsland = false
        lastDialRatchetMinute = targetMinutes
        let c = hourglassCenter
        let rawAng = Float(atan2(location.x - c.x, -(location.y - c.y)))
        lastDialTouchAngle = rawAng < 0 ? (rawAng + 2.0 * .pi) : rawAng
        updateDialMinutesFromPoint(location, angularSpeed: 0.5)
        HapticsManager.shared.tapSoft(intensity: 0.55)
    }

    func updateDialScrub(at location: CGPoint, velocity: CGSize) {
        if !isDraggingDial { beginDialScrub(at: location) }

        let p = SIMD2<Float>(Float(location.x), Float(location.y))
        let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
        let distToIsland = simd_distance(p, isl)

        // Allow dragging the Focus Dial Droplet right into the iPhone 18 Pro OLED Cutout!
        if location.y < 145.0 && distToIsland < 102.0 {
            if !isDraggingDialToIsland {
                isDraggingDialToIsland = true
                dialDetachedPos.pos = dialKnobScreenPosition()
            }
            let pull = (1.0 - distToIsland / 102.0) * 0.45
            let pulledTarget = p + (isl - p) * pull
            dialDetachedPos.pos = pulledTarget
            dialTangentAngle = atan2(Float(velocity.height), Float(velocity.width))
            return
        } else {
            isDraggingDialToIsland = false
        }

        let speed = Float(hypot(velocity.width, velocity.height))
        let angSpeed = speed / max(80.0, Float(radialDialRadiusPt))
        updateDialMinutesFromPoint(location, angularSpeed: angSpeed)
    }

    private func updateDialMinutesFromPoint(_ location: CGPoint, angularSpeed: Float) {
        let c = hourglassCenter
        let dx = Float(location.x - c.x)
        let dy = Float(location.y - c.y)
        guard hypot(dx, dy) > 18.0 else { return }

        let rawAng = atan2(dx, -dy)
        let cwAngle = rawAng < 0 ? (rawAng + 2.0 * Float.pi) : rawAng

        // Prevent accidental wraparound jump across 12 o'clock (5m <-> 60m boundary)
        let currentNorm = (dialMinutesSpring.pos - 5.0) / 55.0
        var proposedNorm = cwAngle / (2.0 * Float.pi)
        if currentNorm > 0.86 && proposedNorm < 0.16 {
            proposedNorm = 1.0
        } else if currentNorm < 0.14 && proposedNorm > 0.84 {
            proposedNorm = 0.0
        }

        let rawMinutes = min(max(5.0 + proposedNorm * 55.0, 5.0), 60.0)
        // Drive spring target continuously while preserving velocity!
        dialMinutesSpring.pos += (rawMinutes - dialMinutesSpring.pos) * 0.55
        dialTangentAngle = cwAngle // Tangent along ring is (cos(cwAngle), sin(cwAngle)) -> angle = cwAngle!

        let snappedMin = min(60, max(5, Int(rawMinutes.rounded())))
        if snappedMin != lastDialRatchetMinute {
            lastDialRatchetMinute = snappedMin
            targetMinutes = snappedMin
            pomodoroTotalSec = Double(snappedMin * 60)
            pomodoroRemainingSec = pomodoroTotalSec
            displayRemainingSeconds = snappedMin * 60
            HapticsManager.shared.playPrecisionRatchetTick(angularSpeed: angularSpeed)
        }
    }

    func endDialScrub(at location: CGPoint, velocity: CGSize) {
        isDraggingDial = false
        let p = SIMD2<Float>(Float(location.x), Float(location.y))
        let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))

        if isDraggingDialToIsland && simd_distance(p, isl) < 56.0 {
            isDraggingDialToIsland = false
            HapticsManager.shared.playIslandSwallow()
            startPomodoro()
            setZenMode(true)
            return
        }

        isDraggingDialToIsland = false
        // Inject tangential release velocity so spring settles with authentic damped feel onto integer minute!
        let c = hourglassCenter
        let rx = Float(location.x - c.x)
        let ry = Float(location.y - c.y)
        let rLen = max(40.0, hypot(rx, ry))
        let tangDir = SIMD2<Float>(ry / rLen, -rx / rLen) // Clockwise unit tangent
        let tangVelPt = simd_dot(SIMD2<Float>(Float(velocity.width), Float(velocity.height)), -tangDir)
        let minutesPerPt = 55.0 / (2.0 * Float.pi * Float(radialDialRadiusPt))
        dialMinutesSpring.vel = min(max(tangVelPt * minutesPerPt * 0.35, -45.0), 45.0)
        dialKnobStretchSpring.vel -= 1.6
        syncLiveActivityNow()
    }

    func beginHourglassSloshTouch(at location: CGPoint) {
        let relX = Float(location.x - hourglassCenter.x) / 90.0
        sloshImpulseTouchX = min(max(relX, -0.65), 0.65)
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func updateHourglassSloshTouch(at location: CGPoint, velocity: CGSize) {
        let relX = Float(location.x - hourglassCenter.x) / 90.0 + Float(velocity.width) / 2600.0
        sloshImpulseTouchX = min(max(relX, -0.70), 0.70)
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endHourglassSloshTouch(velocity: CGSize) {
        sloshImpulseTouchX = nil
        touchLightPos = nil
        // Vertical flick across the hourglass flips & starts/resets it!
        if abs(velocity.height) > 1050.0 {
            flipAndResetPomodoro(autoStart: true)
        }
    }

    // MARK: - InteractiveMTKView Direct Hit Testing

    func hitTestHardwareIsland(at point: CGPoint) -> Bool {
        let c = hardwareIslandCenter
        let halfW = CGFloat(islandWidthPt * 0.5) + 18.0
        let halfH = CGFloat(islandHeightPt * 0.5) + 15.0
        return abs(point.x - c.x) <= halfW && abs(point.y - c.y) <= halfH
    }

    func hitTestHeroDroplet(at point: CGPoint) -> Bool {
        guard (selectedTab == .lensLab || selectedTab == .opticalStudio), !isDropletSwallowedByIsland else {
            return false
        }
        let dx = abs(Float(point.x) - heroSpring.pos.x)
        let dy = abs(Float(point.y) - heroSpring.pos.y)
        let ext = animHalfSizeSpring.pos * lensLiftSpring.pos + SIMD2<Float>(14, 14)
        return dx <= ext.x && dy <= ext.y
    }

    func hitTestCompanionDroplet(at point: CGPoint) -> Bool {
        guard selectedTab == .lensLab && dualDropletEnabled else { return false }
        let dist = hypot(Float(point.x) - companionSpring.pos.x, Float(point.y) - companionSpring.pos.y)
        return dist <= (54.0 * companionLiftSpring.pos + 14.0)
    }

    // MARK: - iPhone 18 Pro Pure-Black Cutout Swallow, Spit & Zen Pull-Down

    func handleHardwareIslandTap() {
        if selectedTab == .focusHourglass {
            toggleZenMode()
        } else if isDropletSwallowedByIsland {
            spitDropletFromIsland()
        } else {
            swallowDropletIntoIsland()
        }
    }

    func handleCanvasSingleTap(at loc: CGPoint) {
        triggerRipple(at: loc, strength: 0.74)
        HapticsManager.shared.tapSoft(intensity: 0.36)

        if isZenMode {
            setZenMode(false)
            return
        }
        if selectedTab == .focusHourglass && isPomodoroRunning {
            // Clicking empty canvas while Pomodoro is running smoothly enters Zen minimalist mode!
            if !hitTestHourglassBody(at: loc) && loc.y > safeTopInset + 72 && loc.y < viewportSize.height - safeBottomInset - 150 {
                setZenMode(true)
            }
        } else if selectedTab == .opticalStudio {
            selectedTab = .focusHourglass
        }
    }

    func swallowDropletIntoIsland() {
        isDropletSwallowedByIsland = true
        let c = hardwareIslandCenter
        heroSpring.pos = SIMD2<Float>(Float(c.x), Float(c.y))
        heroSpring.vel = .zero
        HapticsManager.shared.playIslandSwallow()
    }

    func spitDropletFromIsland() {
        isDropletSwallowedByIsland = false
        let c = hardwareIslandCenter
        heroSpring.pos = SIMD2<Float>(Float(c.x), Float(c.y) + 54.0)
        heroSpring.vel = SIMD2<Float>(Float.random(in: -70...70), 540.0)
        lensStretchAngle = .pi * 0.5
        lensStretchSpring.vel += 3.6
        triggerRipple(at: CGPoint(x: c.x, y: c.y + 34.0), strength: 0.92)
        HapticsManager.shared.playLiquidSnap()
    }

    func updateIslandPullDown(translationY: CGFloat) {
        let pull = Float(max(0.0, min(68.0, translationY)))
        islandPullStretchPt = pull
        if pull >= 48.0 && !hasTriggeredPullAction {
            hasTriggeredPullAction = true
            islandPullStretchPt = 0.0
            if selectedTab == .lensLab && isDropletSwallowedByIsland {
                spitDropletFromIsland()
            } else {
                // Pulling down from Dynamic Island toggles Zen Minimalist Mode!
                if selectedTab != .focusHourglass {
                    selectedTab = .focusHourglass
                }
                toggleZenMode()
                HapticsManager.shared.playLiquidSnap()
            }
        }
    }

    func endIslandPullDown() {
        islandPullStretchPt = 0.0
        hasTriggeredPullAction = false
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

        let totalSec = max(60, Int(pomodoroTotalSec.rounded()))
        let remSec: Int
        let startD: Date?
        let endD: Date?

        if isPomodoroRunning, let end = pomodoroEndTimestamp {
            remSec = max(0, Int(end.timeIntervalSinceNow.rounded()))
            endD = end
            startD = end.addingTimeInterval(-Double(max(remSec, totalSec)))
        } else {
            remSec = max(0, Int(pomodoroRemainingSec.rounded()))
            startD = nil
            endD = nil
        }

        let state = LiquidGlassActivityAttributes.ContentState(
            modeTitle: pomodoroMode.shortTitle,
            isBreakMode: pomodoroMode == .rest,
            isRunning: isPomodoroRunning,
            totalSeconds: totalSec,
            remainingSeconds: remSec,
            startDate: startD,
            endDate: endD,
            engineName: engineMode.badgeLabel,
            completedSessions: completedPomodoros
        )

        Task { @MainActor in
            let existing = Activity<LiquidGlassActivityAttributes>.activities
            if existing.isEmpty {
                let attrs = LiquidGlassActivityAttributes(sessionTitle: "Liquid Hourglass Pomodoro")
                _ = try? Activity.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: endD),
                    pushType: nil
                )
            } else {
                for activity in existing {
                    await activity.update(ActivityContent(state: state, staleDate: endD))
                }
            }
        }
    }

    func reconcileFromLiveActivityOnForeground() {
        guard let active = Activity<LiquidGlassActivityAttributes>.activities.first else { return }
        let st = active.content.state
        let shouldBeRest = st.isBreakMode
        if (pomodoroMode == .rest) != shouldBeRest {
            pomodoroMode = shouldBeRest ? .rest : .focus
        }
        let mins = max(5, min(60, st.totalSeconds / 60))
        targetMinutes = mins
        pomodoroTotalSec = Double(st.totalSeconds)

        if st.isRunning, let end = st.endDate {
            let left = end.timeIntervalSinceNow
            if left > 0.5 {
                pomodoroRemainingSec = left
                pomodoroEndTimestamp = end
                isPomodoroRunning = true
                displayRemainingSeconds = Int(left.rounded())
            } else {
                pomodoroRemainingSec = 0
                pomodoroEndTimestamp = nil
                isPomodoroRunning = false
                displayRemainingSeconds = 0
            }
        } else {
            isPomodoroRunning = false
            pomodoroEndTimestamp = nil
            pomodoroRemainingSec = Double(max(0, st.remainingSeconds))
            displayRemainingSeconds = max(0, st.remainingSeconds)
        }
    }

    private func observeLiveActivityIntents() {
        intentObserver = NotificationCenter.default.addObserver(
            forName: .liquidGlassIntentCommand,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let action = note.userInfo?["action"] as? String
            let desiredRunning = note.userInfo?["isRunning"] as? Bool
            let desiredBreak = note.userInfo?["isBreakMode"] as? Bool
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch action {
                case "togglePomodoro":
                    if let desiredRunning {
                        if desiredRunning != self.isPomodoroRunning {
                            self.togglePomodoroStartPause()
                        }
                    } else {
                        self.togglePomodoroStartPause()
                    }
                case "resetPomodoro":
                    self.flipAndResetPomodoro(autoStart: false)
                case "switchPomodoroMode":
                    if let desiredBreak {
                        let nextMode: PomodoroMode = desiredBreak ? .rest : .focus
                        if self.pomodoroMode != nextMode {
                            self.switchPomodoroMode(to: nextMode)
                        }
                    } else {
                        self.switchPomodoroMode()
                    }
                default:
                    break
                }
            }
        }
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme == "liquidglass" else { return }
        selectedTab = .focusHourglass
        triggerRipple(at: hourglassCenter, strength: 0.92)
        HapticsManager.shared.tapMedium()
    }

    // MARK: - Strict Single-Axis Two-Part Dock Scrubbing (Velocity-Preserving!)

    /// Returns the instantaneous live X coordinate of the Dock lens so grabbing mid-flight has ZERO jump!
    var liveDockThumbLocalX: CGFloat {
        CGFloat(dockThumbSpring.pos) - dockAssemblyLeft(for: viewportSize.width)
    }

    func updateDockHorizontalScrub(clampedScreenX: CGFloat, velocityX: CGFloat, isDragging: Bool) {
        isScrubbingDockInternal = isDragging
        dockThumbTargetX = Float(clampedScreenX)
        let speedX = Float(abs(velocityX))
        let desiredStretch = 1.0 + min(0.28, speedX / 1450.0)
        if desiredStretch > dockThumbStretchSpring.pos {
            dockThumbStretchSpring.pos += (desiredStretch - dockThumbStretchSpring.pos) * 0.38
        }
    }

    func endDockHorizontalScrub(releaseVelocityX: CGFloat) {
        isScrubbingDockInternal = false
        if selectedTab.isMainCapsuleTab {
            dockThumbTargetX = Float(dockMainSlotScreenX(index: selectedTab.rawValue, screenWidth: viewportSize.width))
        }
        // Inject release velocity for authentic Apple overshoot & settle!
        dockThumbSpring.vel = min(max(Float(releaseVelocityX) * 0.42, -950.0), 950.0)
        dockThumbStretchSpring.vel -= 1.8
    }

    func triggerStudioOrbPulse() {
        studioOrbScaleSpring.vel += 3.2
    }

    func togglePin(for tab: DockTab) {
        switch tab {
        case .musicBeat:
            pinnedMusic.toggle()
            HapticsManager.shared.playLiquidSnap()
        case .controlHub:
            pinnedControl.toggle()
            HapticsManager.shared.playLiquidSnap()
        default:
            break
        }
    }

    // MARK: - Velocity-Preserving Droplet & Card Gesture Hooks

    func triggerRipple(at point: CGPoint, strength: Float = 0.80) {
        guard touchRipplesEnabled else { return }
        rippleCenter = SIMD2<Float>(Float(point.x), Float(point.y))
        rippleRadius = 8.0
        rippleStrength = min(1.0, max(0.25, strength))
    }

    func triggerBeatPad(index: Int, screenPoint: CGPoint) {
        triggerRipple(at: screenPoint, strength: 0.92)
        lensLiftSpring.vel += 2.2
        companionLiftSpring.vel += 2.6
        HapticsManager.shared.playLiquidSnap()
    }

    func beginLensDrag() {
        isDropletSwallowedByIsland = false
        isDraggingLens = true
        // Anchor directly to instantaneous spring position AND preserve heroSpring.vel (Zero Discontinuity!)
        lensDragAnchor = heroSpring.pos
        lensDragTarget = heroSpring.pos
        HapticsManager.shared.tapSoft(intensity: 0.55)
    }

    func updateLensDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if !isDraggingLens { beginLensDrag() }
        var targetX = lensDragAnchor.x + Float(translation.width)
        var targetY = lensDragAnchor.y + Float(translation.height)

        let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
        let distToIsland = simd_distance(SIMD2<Float>(targetX, targetY), isl)
        if distToIsland < 105.0 {
            let pullFactor = (1.0 - distToIsland / 105.0) * 0.45
            targetX += (isl.x - targetX) * pullFactor
            targetY += (isl.y - targetY) * pullFactor
        } else {
            let minX = animHalfSizeSpring.pos.x * 0.85 + 8.0
            let maxX = Float(viewportSize.width) - animHalfSizeSpring.pos.x * 0.85 - 8.0
            let maxY = Float(viewportSize.height - safeBottomInset) - 82.0 - animHalfSizeSpring.pos.y * 0.85
            if targetX < minX { targetX = minX + (targetX - minX) * 0.32 }
            if targetX > maxX { targetX = maxX + (targetX - maxX) * 0.32 }
            if targetY > maxY { targetY = maxY + (targetY - maxY) * 0.32 }
        }

        lensDragTarget = SIMD2<Float>(targetX, targetY)
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endLensDrag(velocity: CGSize) {
        isDraggingLens = false
        touchLightPos = nil
        let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
        if simd_distance(heroSpring.pos, isl) < 52.0 {
            swallowDropletIntoIsland()
            return
        }
        // Blend gesture release velocity seamlessly with current spring velocity
        let gestureVel = clampVelocity(velocity, maxSpeed: 2600.0)
        heroSpring.vel = heroSpring.vel * 0.25 + gestureVel * 0.75
    }

    func beginCompanionDrag() {
        isDraggingCompanion = true
        // Preserve instantaneous position & velocity!
        companionDragAnchor = companionSpring.pos
        companionDragTarget = companionSpring.pos
        HapticsManager.shared.tapSoft(intensity: 0.50)
    }

    func updateCompanionDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if !isDraggingCompanion { beginCompanionDrag() }
        companionDragTarget = companionDragAnchor + SIMD2<Float>(Float(translation.width), Float(translation.height))
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endCompanionDrag(velocity: CGSize) {
        isDraggingCompanion = false
        touchLightPos = nil
        let gestureVel = clampVelocity(velocity, maxSpeed: 2600.0)
        companionSpring.vel = companionSpring.vel * 0.25 + gestureVel * 0.75
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
        lensLiftSpring.vel += 3.4
        lensStretchSpring.vel += 2.2
        triggerRipple(at: CGPoint(x: CGFloat(heroSpring.pos.x), y: CGFloat(heroSpring.pos.y)), strength: 0.72)
        HapticsManager.shared.playLiquidSnap()
    }

    func setCardSpringTarget(tab: DockTab, offset: CGSize, releaseVelocity: CGSize? = nil) {
        let vec = SIMD2<Float>(Float(offset.width), Float(offset.height))
        switch tab {
        case .musicBeat:
            musicTargetOffset = vec
            if let rv = releaseVelocity {
                musicOffsetSpring.vel += SIMD2<Float>(Float(rv.width), Float(rv.height)) * 0.18
            }
        case .controlHub:
            controlTargetOffset = vec
            if let rv = releaseVelocity {
                controlOffsetSpring.vel += SIMD2<Float>(Float(rv.width), Float(rv.height)) * 0.18
            }
        default:
            break
        }
    }

    func resetPlaygroundLayout() {
        if selectedTab == .focusHourglass {
            isZenMode = false
            flipAndResetPomodoro(autoStart: false)
            return
        }
        isDropletSwallowedByIsland = false
        lensShape = .circle
        lensZoomScale = 1.0
        pinchStartScale = 1.0
        heroSpring.pos = SIMD2<Float>(Float(viewportSize.width * 0.40), Float(viewportSize.height * 0.49))
        companionSpring.pos = SIMD2<Float>(Float(viewportSize.width * 0.65), Float(viewportSize.height * 0.56))
        heroSpring.vel = SIMD2<Float>(-130, -170)
        companionSpring.vel = SIMD2<Float>(130, 130)
        musicTargetOffset = .zero
        controlTargetOffset = .zero
        lensLiftSpring.vel += 3.0
        companionLiftSpring.vel += 3.0
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

    // MARK: - Pure 120Hz Fixed-Timestep Physics & Uniform Builder (Zero Per-Frame SwiftUI @State Writes!)

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

        let clampedFrameDt = Float(min(max(rawDt, 1.0 / 240.0), 1.0 / 24.0))
        let elapsed = Float(now - startTime)

        // Advance Pomodoro wall-clock countdown (updates displayRemainingSeconds ONLY on integer second change!)
        stepPomodoroClock(dt: clampedFrameDt)

        if isPlayingMusic && isMusicVisible {
            audioProgressAccum += Double(clampedFrameDt)
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

        // Fixed 120Hz (dt = 1/120s) symplectic spring & fluid integration loop
        physicsAccumulator = min(physicsAccumulator + clampedFrameDt, fixedDt * 4.0)
        while physicsAccumulator >= fixedDt * 0.999 {
            stepFixed120HzPhysics(dt: fixedDt)
            physicsAccumulator -= fixedDt
        }

        buildUniformBuffers(dt: clampedFrameDt, elapsed: elapsed)
    }

    private func stepPomodoroClock(dt: Float) {
        guard isPomodoroRunning else { return }

        if let end = pomodoroEndTimestamp {
            pomodoroRemainingSec = max(0.0, end.timeIntervalSinceNow)
        } else {
            pomodoroRemainingSec = max(0.0, pomodoroRemainingSec - Double(dt))
        }

        let newDisplaySec = max(0, Int(ceil(pomodoroRemainingSec)))
        if newDisplaySec != displayRemainingSeconds {
            displayRemainingSeconds = newDisplaySec
        }

        if pomodoroRemainingSec <= 0.001 {
            pomodoroRemainingSec = 0.0
            pomodoroEndTimestamp = nil
            isPomodoroRunning = false
            displayRemainingSeconds = 0
            if pomodoroMode == .focus {
                completedPomodoros += 1
            }
            if isZenMode { isZenMode = false }
            triggerRipple(at: hourglassCenter, strength: 1.0)
            HapticsManager.shared.playPomodoroTripletResonance()
            syncLiveActivityNow()
        }
    }

    private func stepFixed120HzPhysics(dt: Float) {
        if rippleStrength > 0.003 {
            rippleRadius += 530.0 * dt
            rippleStrength *= exp(-2.65 * dt)
            if rippleStrength < 0.004 { rippleStrength = 0.0 }
        }

        // 1. Velocity-preserving UI & Mode springs
        let onFocus = (selectedTab == .focusHourglass)
        hourglassVisSpring.step(target: onFocus ? 1.0 : 0.0, omega: 24.0, zeta: 0.76, dt: dt)
        flipAngleSpring.step(target: 0.0, omega: 14.5, zeta: 0.74, dt: dt)
        modeBlendSpring.step(target: pomodoroMode == .rest ? 1.0 : 0.0, omega: 12.0, zeta: 0.80, dt: dt)
        zenGlowSpring.step(target: isZenMode ? 1.0 : 0.0, omega: 16.0, zeta: 0.78, dt: dt)
        dockVisibilitySpring.step(target: isZenMode ? 0.0 : 1.0, omega: 22.0, zeta: 0.76, dt: dt)

        labBarAlphaSpring.step(target: isLensLabBarVisible ? 1.0 : 0.0, omega: 24.0, zeta: 0.82, dt: dt)
        musicAlphaSpring.step(target: isMusicVisible ? 1.0 : 0.0, omega: 24.0, zeta: 0.82, dt: dt)
        controlAlphaSpring.step(target: isControlVisible ? 1.0 : 0.0, omega: 24.0, zeta: 0.82, dt: dt)
        drawerAlphaSpring.step(target: isStudioVisible ? 1.0 : 0.0, omega: 24.0, zeta: 0.82, dt: dt)

        musicOffsetSpring.step(target: musicTargetOffset, omega: 32.0, zeta: 0.74, dt: dt)
        controlOffsetSpring.step(target: controlTargetOffset, omega: 32.0, zeta: 0.74, dt: dt)

        spotlightAnim += ((flashlightOn ? 1.0 : 0.0) - spotlightAnim) * min(1.0, dt * 14.0)

        // 2. Hourglass Fluid Fill, Gravity Tilt Slosh, Droplet Pinch-Off & Radial Dial
        let totalS = max(1.0, Float(pomodoroTotalSec))
        let remRatio = min(max(Float(pomodoroRemainingSec) / totalS, 0.0), 1.0)
        upperFillSpring.step(target: remRatio, omega: 18.0, zeta: 0.82, dt: dt)
        lowerFillSpring.step(target: 1.0 - remRatio, omega: 18.0, zeta: 0.82, dt: dt)

        let gyroSlosh = gyroEnabled
            ? (motionManager.screenGravity.x * 0.72 - motionManager.inPlaneRotationRate * 0.14)
            : 0.0
        let desiredTilt = sloshImpulseTouchX ?? gyroSlosh
        liquidTiltSpring.step(target: min(max(desiredTilt, -0.75), 0.75), omega: 18.0, zeta: 0.52, dt: dt)

        streamActiveSpring.step(target: (isPomodoroRunning && remRatio > 0.005) ? 1.0 : 0.0, omega: 20.0, zeta: 0.78, dt: dt)

        if isPomodoroRunning && remRatio > 0.004 && abs(flipAngleSpring.pos) < 0.55 {
            // 1.65-second realistic pendant droplet condensation -> pinch-off -> free-fall -> impact ripple!
            dropletCyclePhase += dt / 1.65
            if dropletCyclePhase >= 1.0 {
                dropletCyclePhase -= 1.0
                didTriggerImpactInCycle = false
            }
            if dropletCyclePhase >= 0.78 && !didTriggerImpactInCycle {
                didTriggerImpactInCycle = true
                impactWavePhase = 0.0
                impactStrength = 1.0
                causticBloom = 1.0
                HapticsManager.shared.playDropletResonance()
            }
        } else {
            dropletCyclePhase = 0.0
            didTriggerImpactInCycle = false
        }

        if impactStrength > 0.004 {
            impactWavePhase = min(1.5, impactWavePhase + dt * 1.45)
            impactStrength *= exp(-2.9 * dt)
            if impactStrength < 0.005 { impactStrength = 0.0 }
        }
        let baseCaustic: Float = isPomodoroRunning ? 0.34 : 0.16
        causticBloom += (baseCaustic - causticBloom) * min(1.0, dt * 3.8)

        // Radial Time Dial physics (snaps precisely to integer targetMinutes when released!)
        let showDial = onFocus && !isPomodoroRunning && !isZenMode
        dialVisibilitySpring.step(target: showDial ? 1.0 : 0.0, omega: 24.0, zeta: 0.76, dt: dt)
        dialDragGlowSpring.step(target: isDraggingDial ? 1.0 : 0.0, omega: 28.0, zeta: 0.70, dt: dt)
        if !isDraggingDial {
            dialMinutesSpring.step(target: Float(targetMinutes), omega: 30.0, zeta: 0.72, dt: dt)
            dialMinutesSpring.pos = min(max(dialMinutesSpring.pos, 5.0), 60.0)
        }
        let dialSpeed = abs(dialMinutesSpring.vel)
        let desiredKnobStretch = 1.0 + min(0.32, dialSpeed / 36.0) + (isDraggingDial ? 0.06 : 0.0)
        dialKnobStretchSpring.step(target: desiredKnobStretch, omega: 28.0, zeta: 0.48, dt: dt)

        // 3. Playground Droplets (Active in LensLab & Studio)
        let showPlaygroundDroplets = (selectedTab == .lensLab || selectedTab == .opticalStudio)
        let heroTargetVis: Float = (showPlaygroundDroplets && !isDropletSwallowedByIsland) ? 1.0 : 0.0
        heroVisibilitySpring.step(target: heroTargetVis, omega: 24.0, zeta: 0.72, dt: dt)

        let compTargetVis: Float = (selectedTab == .lensLab && dualDropletEnabled) ? 1.0 : 0.0
        companionRevealSpring.step(target: compTargetVis, omega: 22.0, zeta: 0.74, dt: dt)

        stepDockHorizontalPhysics(dt: dt)
        if heroVisibilitySpring.pos > 0.01 || companionRevealSpring.pos > 0.01 {
            stepDropletsPhysics(dt: dt)
        }
    }

    private func stepDockHorizontalPhysics(dt: Float) {
        if !isScrubbingDockInternal && selectedTab.isMainCapsuleTab {
            dockThumbTargetX = Float(dockMainSlotScreenX(index: selectedTab.rawValue, screenWidth: viewportSize.width))
        }

        let mainW = Float(dockMainCapsuleWidth(for: viewportSize.width))
        let left = Float(dockAssemblyLeft(for: viewportSize.width))
        let innerPad: Float = 5.0
        let slotW = (mainW - innerPad * 2.0) / Float(DockTab.mainCapsuleTabs.count)
        let minCenterX = left + innerPad + slotW * 0.5
        let maxCenterX = left + mainW - innerPad - slotW * 0.5

        let clampedTargetX = min(max(dockThumbTargetX, minCenterX), maxCenterX)
        dockThumbSpring.step(
            target: clampedTargetX,
            omega: isScrubbingDockInternal ? 42.0 : 28.0,
            zeta: isScrubbingDockInternal ? 0.78 : 0.62, // 0.62 gives crisp Apple Overshoot & Settle!
            dt: dt
        )
        dockThumbSpring.pos = min(max(dockThumbSpring.pos, minCenterX - 6.0), maxCenterX + 6.0)

        dockThumbLiftSpring.step(target: isScrubbingDockInternal ? 1.0 : 0.0, omega: 28.0, zeta: 0.66, dt: dt)
        let speedX = abs(dockThumbSpring.vel)
        dockThumbStretchSpring.step(target: 1.0 + min(0.24, speedX / 1450.0), omega: 28.0, zeta: 0.46, dt: dt)
        dockThumbStretchSpring.pos = min(max(dockThumbStretchSpring.pos, 0.84), 1.32)

        let orbTarget: Float = (selectedTab == .opticalStudio) ? 1.05 : 1.0
        studioOrbScaleSpring.step(target: orbTarget, omega: 28.0, zeta: 0.58, dt: dt)
    }

    private func stepDropletsPhysics(dt: Float) {
        let targetHalf = lensShape.baseHalfSize * lensZoomScale
        let targetCorner = lensShape.baseCornerRadius * lensZoomScale
        animHalfSizeSpring.step(target: targetHalf, omega: 22.0, zeta: 0.68, dt: dt)
        animCornerSpring.step(target: targetCorner, omega: 22.0, zeta: 0.68, dt: dt)

        lensLiftSpring.step(target: isDraggingLens ? 1.07 : 1.0, omega: 24.0, zeta: 0.58, dt: dt)
        companionLiftSpring.step(target: isDraggingCompanion ? 1.08 : 1.0, omega: 24.0, zeta: 0.58, dt: dt)

        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)
        let effectiveHalf = animHalfSizeSpring.pos * max(0.2, lensLiftSpring.pos * max(0.2, heroVisibilitySpring.pos))
        let compRad = 52.0 * max(0.5, companionLiftSpring.pos)

        let gravityAccel = gravityModeEnabled ? (motionManager.screenGravity * 920.0) : SIMD2<Float>(0, 0)
        let dragRate: Float = gravityModeEnabled ? 0.85 : 2.05

        let bottomWall = isStudioVisible
            ? (h - Float(safeBottomInset) - 446.0)
            : (h - Float(safeBottomInset) - 86.0)

        if isDraggingLens {
            // Velocity-preserving high-stiffness spring tracking finger (ZERO teleport!)
            heroSpring.step(target: lensDragTarget, omega: 50.0, zeta: 0.85, dt: dt)
        } else if !isDropletSwallowedByIsland {
            heroSpring.vel += gravityAccel * dt
            heroSpring.pos += heroSpring.vel * dt
            heroSpring.vel *= exp(-dragRate * dt)

            let isl = SIMD2<Float>(Float(hardwareIslandCenter.x), Float(hardwareIslandCenter.y))
            if simd_distance(heroSpring.pos, isl) < 46.0 && heroSpring.vel.y < -35.0 {
                swallowDropletIntoIsland()
                return
            }

            let minX = effectiveHalf.x + 10.0
            let maxX = max(minX + 1.0, w - effectiveHalf.x - 10.0)
            let minY = Float(safeTopInset) + 48.0 + effectiveHalf.y
            let maxY = max(minY + 1.0, bottomWall - effectiveHalf.y)
            let rest: Float = 0.76

            if heroSpring.pos.x < minX {
                let spd = abs(heroSpring.vel.x); heroSpring.pos.x = minX
                if heroSpring.vel.x < 0 { heroSpring.vel.x = -heroSpring.vel.x * rest; injectLensSquish(angle: 0, speed: spd) }
            } else if heroSpring.pos.x > maxX {
                let spd = abs(heroSpring.vel.x); heroSpring.pos.x = maxX
                if heroSpring.vel.x > 0 { heroSpring.vel.x = -heroSpring.vel.x * rest; injectLensSquish(angle: 0, speed: spd) }
            }
            if heroSpring.pos.y < minY {
                let spd = abs(heroSpring.vel.y); heroSpring.pos.y = minY
                if heroSpring.vel.y < 0 { heroSpring.vel.y = -heroSpring.vel.y * rest; injectLensSquish(angle: .pi * 0.5, speed: spd) }
            } else if heroSpring.pos.y > maxY {
                let spd = abs(heroSpring.vel.y); heroSpring.pos.y = maxY
                if heroSpring.vel.y > 0 { heroSpring.vel.y = -heroSpring.vel.y * rest; injectLensSquish(angle: .pi * 0.5, speed: spd) }
            }

            if !gravityModeEnabled && simd_length(heroSpring.vel) < 2.0 { heroSpring.vel = .zero }
        }

        if companionRevealSpring.pos > 0.02 {
            if isDraggingCompanion {
                companionSpring.step(target: companionDragTarget, omega: 50.0, zeta: 0.85, dt: dt)
            } else {
                companionSpring.vel += gravityAccel * dt

                if metaballFusionEnabled && !isDropletSwallowedByIsland {
                    let delta = heroSpring.pos - companionSpring.pos
                    let dist = simd_length(delta)
                    let mergeBand = max(effectiveHalf.x, effectiveHalf.y) + compRad + 32.0
                    if dist > 26.0 && dist < mergeBand {
                        companionSpring.vel += (delta / dist) * 165.0 * dt
                    }
                }

                companionSpring.pos += companionSpring.vel * dt
                companionSpring.vel *= exp(-dragRate * dt)

                let cMinX = compRad + 10.0
                let cMaxX = max(cMinX + 1.0, w - compRad - 10.0)
                let cMinY = Float(safeTopInset) + 48.0 + compRad
                let cMaxY = max(cMinY + 1.0, bottomWall - compRad)
                let rest: Float = 0.78

                if companionSpring.pos.x < cMinX {
                    let spd = abs(companionSpring.vel.x); companionSpring.pos.x = cMinX
                    if companionSpring.vel.x < 0 { companionSpring.vel.x = -companionSpring.vel.x * rest; injectCompanionSquish(angle: 0, speed: spd) }
                } else if companionSpring.pos.x > cMaxX {
                    let spd = abs(companionSpring.vel.x); companionSpring.pos.x = cMaxX
                    if companionSpring.vel.x > 0 { companionSpring.vel.x = -companionSpring.vel.x * rest; injectCompanionSquish(angle: 0, speed: spd) }
                }
                if companionSpring.pos.y < cMinY {
                    let spd = abs(companionSpring.vel.y); companionSpring.pos.y = cMinY
                    if companionSpring.vel.y < 0 { companionSpring.vel.y = -companionSpring.vel.y * rest; injectCompanionSquish(angle: .pi * 0.5, speed: spd) }
                } else if companionSpring.pos.y > cMaxY {
                    let spd = abs(companionSpring.vel.y); companionSpring.pos.y = cMaxY
                    if companionSpring.vel.y > 0 { companionSpring.vel.y = -companionSpring.vel.y * rest; injectCompanionSquish(angle: .pi * 0.5, speed: spd) }
                }

                if !gravityModeEnabled && simd_length(companionSpring.vel) < 2.0 { companionSpring.vel = .zero }
            }

            if metaballFusionEnabled && !isDropletSwallowedByIsland {
                let dist = simd_distance(heroSpring.pos, companionSpring.pos)
                let nowFused = dist < (min(effectiveHalf.x, effectiveHalf.y) + compRad + 22.0)
                if nowFused != wasDropletsFused {
                    wasDropletsFused = nowFused
                    let mid = (heroSpring.pos + companionSpring.pos) * 0.5
                    if nowFused {
                        HapticsManager.shared.tapSoft(intensity: 0.58)
                    } else {
                        lensStretchSpring.vel -= 2.0
                        companionStretchSpring.vel -= 2.4
                        triggerRipple(at: CGPoint(x: CGFloat(mid.x), y: CGFloat(mid.y)), strength: 0.76)
                        HapticsManager.shared.playLiquidSnap()
                    }
                }
            }
        }

        updateDropletStretch(vel: heroSpring.vel, angle: &lensStretchAngle, stretchSpring: &lensStretchSpring, dt: dt)
        updateDropletStretch(vel: companionSpring.vel, angle: &companionStretchAngle, stretchSpring: &companionStretchSpring, dt: dt)
    }

    private func updateDropletStretch(vel: SIMD2<Float>, angle: inout Float, stretchSpring: inout Spring1D, dt: Float) {
        let speed = simd_length(vel)
        if speed > 28.0 {
            let targetAngle = atan2(vel.y, vel.x)
            var delta = targetAngle - angle
            while delta > .pi { delta -= 2.0 * .pi }
            while delta < -.pi { delta += 2.0 * .pi }
            angle += delta * min(1.0, dt * 18.0)
        }
        stretchSpring.step(target: 1.0 + min(0.26, speed / 2450.0), omega: 26.0, zeta: 0.40, dt: dt)
        stretchSpring.pos = min(max(stretchSpring.pos, 0.74), 1.38)
    }

    private func injectLensSquish(angle: Float, speed: Float) {
        guard speed > 75.0 else { return }
        lensStretchAngle = angle
        lensStretchSpring.vel -= min(4.0, speed * 0.0036)
        HapticsManager.shared.wallBounce(speed: speed)
    }

    private func injectCompanionSquish(angle: Float, speed: Float) {
        guard speed > 75.0 else { return }
        companionStretchAngle = angle
        companionStretchSpring.vel -= min(4.0, speed * 0.0038)
        HapticsManager.shared.wallBounce(speed: speed)
    }

    // MARK: - Build 16-Byte Aligned Metal Uniform Buffers

    private func buildUniformBuffers(dt: Float, elapsed: Float) {
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)

        var desiredLight = gyroEnabled
            ? motionManager.targetLightDir
            : SIMD2<Float>(cos(elapsed * 0.45) * 0.55 - 0.35, sin(elapsed * 0.38) * 0.45 - 0.68)

        if let touch = touchLightPos {
            let refCenter = selectedTab == .focusHourglass
                ? SIMD2<Float>(Float(hourglassCenter.x), Float(hourglassCenter.y))
                : heroSpring.pos
            let delta = touch - refCenter
            let len = simd_length(delta)
            if len > 8.0 { desiredLight = simd_normalize(desiredLight * 0.55 + (delta / len) * 0.45) }
        }

        currentLightDir += (desiredLight - currentLightDir) * min(1.0, dt * 14.0)
        let normLight = simd_length(currentLightDir) > 1e-3 ? simd_normalize(currentLightDir) : SIMD2<Float>(-0.58, -0.81)

        // 1. Build HourglassUniforms (buffer(2))
        let hgC = hourglassCenter
        let hgVis = min(max(hourglassVisSpring.pos, 0.0), 1.0)
        let uFill = min(max(upperFillSpring.pos, 0.0), 1.0)
        let lFill = min(max(lowerFillSpring.pos, 0.0), 1.0)
        let lowerSurfY: Float = 110.0 - pow(lFill, 0.82) * 96.0

        var dropLocalY: Float = 0.0
        var dropR: Float = 0.0
        var filamentW: Float = 0.0
        var dropStretch: Float = 1.0
        var satY: Float = 0.0
        var satR: Float = 0.0

        if isPomodoroRunning && uFill > 0.004 && abs(flipAngleSpring.pos) < 0.55 {
            let ph = dropletCyclePhase
            if ph < 0.42 {
                // Surface-tension condensation & capillary neck stretching
                let t = ph / 0.42
                dropR = 3.6 + 3.8 * sqrt(t)
                dropLocalY = 2.0 + 18.5 * (t * t)
                filamentW = 4.0 * (1.0 - t * 0.90)
                dropStretch = 1.0 + 0.28 * t
            } else if ph < 0.80 {
                // Pinch-off snap + parabolic gravitational acceleration to lower pool!
                let u = (ph - 0.42) / 0.38
                dropR = 7.2
                dropLocalY = 20.5 + max(4.0, lowerSurfY - 20.5) * (u * u)
                filamentW = 0.0
                dropStretch = 1.16 + 0.30 * u
                // Trailing Plateau-Rayleigh satellite micro-droplet
                if u < 0.68 {
                    let su = u / 0.68
                    satR = 2.6 * (1.0 - su)
                    satY = 7.5 + 24.0 * (su * su)
                }
            } else {
                // Smooth coalescence into lower pool
                let m = (ph - 0.80) / 0.20
                dropR = 7.2 * (1.0 - m)
                dropLocalY = lowerSurfY + 3.0 * m
                dropStretch = max(0.85, 1.15 - 0.30 * m)
            }
        }

        let dialVis = min(max(dialVisibilitySpring.pos, 0.0), 1.0)
        let dragGlow = min(max(dialDragGlowSpring.pos, 0.0), 1.0)
        let knobPos = dialKnobScreenPosition()
        let knobRadius: Float = 15.5 + 13.5 * dragGlow
        let progAngle = min(max((dialMinutesSpring.pos - 5.0) / 55.0, 0.0), 1.0) * 2.0 * Float.pi

        hourglassUniforms = HourglassUniforms(
            centerAndSize: SIMD4<Float>(Float(hgC.x), Float(hgC.y), 74.0, 124.0),
            morphAndFill: SIMD4<Float>(hgVis, flipAngleSpring.pos, uFill, lFill),
            dropletParams: SIMD4<Float>(dropletCyclePhase, dropLocalY, dropR, filamentW),
            impactAndAtmosphere: SIMD4<Float>(impactWavePhase, impactStrength, causticBloom, min(max(modeBlendSpring.pos, 0.0), 1.0)),
            dialRingParams: SIMD4<Float>(dialVis, Float(radialDialRadiusPt), progAngle, dragGlow),
            dialLensParams: SIMD4<Float>(knobPos.x, knobPos.y, knobRadius, dialTangentAngle),
            gravityAndZen: SIMD4<Float>(liquidTiltSpring.pos, motionManager.screenGravity.y, min(max(zenGlowSpring.pos, 0.0), 1.0), min(max(dialKnobStretchSpring.pos, 0.82), 1.42)),
            neckAndStream: SIMD4<Float>(min(max(streamActiveSpring.pos, 0.0), 1.0), dropStretch, satY, satR)
        )

        // 2. Build GlassElementUniforms (buffer(1)) in strict Z-Order
        let cardW = min(w - 32.0, 346.0)
        let controlCenterPt = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 188.0) + controlOffsetSpring.pos
        let spotOrigin = (controlAlphaSpring.pos > 0.05)
            ? SIMD2<Float>(controlCenterPt.x - cardW * 0.32, controlCenterPt.y - 46.0)
            : SIMD2<Float>(w * 0.5, Float(safeTopInset) + 20.0)

        let textMix: Float = (wallpaper == .customPhoto) ? (showTypographyOnPhoto ? 0.72 : 0.0) : 1.0
        let modeWarmth = min(max(modeBlendSpring.pos, 0.0), 1.0) * 0.36

        var count = 0

        let heroVis = min(max(heroVisibilitySpring.pos, 0.0), 1.15)
        let compVis = min(max(companionRevealSpring.pos, 0.0), 1.0)

        if heroVis > 0.02 && count < 15 {
            let effHalf = animHalfSizeSpring.pos * max(0.15, lensLiftSpring.pos * heroVis)
            let effCorner = animCornerSpring.pos * max(0.15, lensLiftSpring.pos * heroVis)
            let fuseWithCompanion = metaballFusionEnabled && (compVis > 0.02)
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(heroSpring.pos.x, heroSpring.pos.y, effHalf.x, effHalf.y),
                shapeAndTransform: SIMD4<Float>(effCorner, lensStretchAngle, lensStretchSpring.pos, isDraggingLens ? 1.32 : 1.18),
                styleParams: SIMD4<Float>(min(1.0, heroVis), 1.04, 0.0, isDraggingLens ? 1.32 : 1.02),
                tintOverride: SIMD4<Float>(0.0, 0.0, 0.0, fuseWithCompanion ? -1.0 : -2.0)
            )
            count += 1
        }

        if compVis > 0.02 && count < 15 {
            let r = 52.0 * companionLiftSpring.pos * (0.35 + 0.65 * compVis)
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(companionSpring.pos.x, companionSpring.pos.y, r, r),
                shapeAndTransform: SIMD4<Float>(r, companionStretchAngle, companionStretchSpring.pos, isDraggingCompanion ? 1.32 : 1.18),
                styleParams: SIMD4<Float>(compVis, 1.06, -0.25, isDraggingCompanion ? 1.28 : 1.0),
                tintOverride: SIMD4<Float>(0.35, 0.92, 1.0, 0.05)
            )
            count += 1
        }

        if !useNativeSystemGlass {
            let labAlpha = min(max(labBarAlphaSpring.pos, 0.0), 1.0)
            if labAlpha > 0.01 && count < 15 {
                let pillHalfW = min(w - 32.0, 336.0) * 0.5
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, Float(safeTopInset) + 76.0, pillHalfW, 24.0),
                    shapeAndTransform: SIMD4<Float>(24.0, 0.0, 1.0, 1.08),
                    styleParams: SIMD4<Float>(labAlpha, 0.55, 0.55, 0.85),
                    tintOverride: SIMD4<Float>(0.22, 0.74, 0.98, gravityModeEnabled ? 0.14 : 0.04)
                )
                count += 1
            }

            let mAlpha = min(max(musicAlphaSpring.pos, 0.0), 1.0)
            if mAlpha > 0.01 && count < 15 {
                let mCenter = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 150.0) + musicOffsetSpring.pos
                let trackTint = currentTrack.shaderTint
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(mCenter.x, mCenter.y, cardW * 0.5, 88.0),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, 1.10),
                    styleParams: SIMD4<Float>(mAlpha, 0.58, 0.55, 0.96),
                    tintOverride: SIMD4<Float>(trackTint.x, trackTint.y, trackTint.z, isPlayingMusic ? 0.13 : 0.04)
                )
                count += 1
            }

            let cAlpha = min(max(controlAlphaSpring.pos, 0.0), 1.0)
            if cAlpha > 0.01 && count < 15 {
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(controlCenterPt.x, controlCenterPt.y, cardW * 0.5, 134.0),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, flashlightOn ? 1.35 : 1.10),
                    styleParams: SIMD4<Float>(cAlpha, 0.56, 0.65, 0.98),
                    tintOverride: SIMD4<Float>(0.96, 0.88, 0.58, flashlightOn ? 0.14 : 0.03)
                )
                count += 1
            }

            let dAlpha = min(max(drawerAlphaSpring.pos, 0.0), 1.0)
            if dAlpha > 0.01 && count < 15 {
                let drawerH: Float = 388.0
                let drawerHalfW = min(w - 24.0, 366.0) * 0.5
                let drawerBaseY = h - Float(safeBottomInset) - 80.0 - drawerH * 0.5
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, drawerBaseY, drawerHalfW, drawerH * 0.5),
                    shapeAndTransform: SIMD4<Float>(30.0, 0.0, 1.0, 1.12),
                    styleParams: SIMD4<Float>(dAlpha, 0.52, 0.95, 1.15),
                    tintOverride: SIMD4<Float>(0.07, 0.11, 0.20, tintMode == .light ? 0.0 : 0.22)
                )
                count += 1
            }

            // Focus Bottom Control Pill Glass Plate (visible on Focus tab when not in Zen mode)
            let focusPillAlpha = hgVis * min(max(dockVisibilitySpring.pos, 0.0), 1.0)
            if focusPillAlpha > 0.02 && count < 14 {
                let pillY = h - Float(safeBottomInset) - 116.0
                elementUniforms[count] = GlassElementUniform(
                    centerAndHalfSize: SIMD4<Float>(w * 0.5, pillY, min(w - 44.0, 316.0) * 0.5 * (0.92 + 0.08 * focusPillAlpha), 27.0),
                    shapeAndTransform: SIMD4<Float>(27.0, 0.0, 1.0, 1.08),
                    styleParams: SIMD4<Float>(focusPillAlpha, 0.56, 0.62, 0.88),
                    tintOverride: SIMD4<Float>(0.22, 0.74, 0.97, 0.05)
                )
                count += 1
            }

            // Two-Part Apple Native Bottom Dock (Smoothly scales & fades out in Zen Mode!)
            let dockVis = min(max(dockVisibilitySpring.pos, 0.0), 1.0)
            if dockVis > 0.01 {
                let lift = min(1.0, max(0.0, dockThumbLiftSpring.pos))
                let dockY = Float(dockCenterY(for: viewportSize.height, safeBottom: safeBottomInset)) + (1.0 - dockVis) * 28.0
                let mainW = Float(dockMainCapsuleWidth(for: viewportSize.width)) * (0.90 + 0.10 * dockVis)
                let mainCenterX = Float(dockMainCapsuleCenterX(for: viewportSize.width))
                let halfDockH = Float(dockHeight * 0.5) * (0.90 + 0.10 * dockVis)

                // Part 1A: Left Main Capsule Base Plate (78% width — becomes crystal-transparent when sliding!)
                if count < 14 {
                    elementUniforms[count] = GlassElementUniform(
                        centerAndHalfSize: SIMD4<Float>(mainCenterX, dockY, mainW * 0.5, halfDockH),
                        shapeAndTransform: SIMD4<Float>(halfDockH, 0.0, 1.0, 1.05),
                        styleParams: SIMD4<Float>(dockVis * (1.0 - 0.24 * lift), 0.52 + 0.18 * lift, 0.78 - 1.35 * lift, 0.92),
                        tintOverride: SIMD4<Float>(0.90, 0.96, 1.0, 0.04 * (1.0 - lift))
                    )
                    count += 1
                }

                // Part 1B: Sliding Selection Inset / High-Refraction Convex Magnifier Droplet (Y Locked!)
                if selectedTab.isMainCapsuleTab || isScrubbingDockInternal, count < 15 {
                    let slotW = (Float(dockMainCapsuleWidth(for: viewportSize.width)) - 10.0) / Float(DockTab.mainCapsuleTabs.count)
                    let pillHalfW = (slotW * 0.46) * (1.0 + 0.18 * lift)
                    let pillHalfH = (24.0 + 6.5 * lift) * (0.90 + 0.10 * dockVis)
                    elementUniforms[count] = GlassElementUniform(
                        centerAndHalfSize: SIMD4<Float>(dockThumbSpring.pos, dockY, pillHalfW, pillHalfH),
                        shapeAndTransform: SIMD4<Float>(pillHalfH, 0.0, dockThumbStretchSpring.pos, 1.12 + 0.48 * lift),
                        styleParams: SIMD4<Float>(dockVis * (0.52 + 0.46 * lift), 0.58 + 0.90 * lift, -3.8, 0.40 + 0.65 * lift),
                        tintOverride: SIMD4<Float>(0.22, 0.74, 0.97, 0.14 * (1.0 - 0.75 * lift))
                    )
                    count += 1
                }

                // Part 2: Right Independent Circular Glass Sphere (10pt Gap — 工坊 Optical Studio!)
                if count < 16 {
                    let orbCenterX = Float(dockStudioOrbCenterX(for: viewportSize.width))
                    let orbActive: Float = (selectedTab == .opticalStudio) ? 1.0 : 0.0
                    let orbR = Float(dockStudioOrbDiameter * 0.5) * studioOrbScaleSpring.pos * (0.90 + 0.10 * dockVis)
                    elementUniforms[count] = GlassElementUniform(
                        centerAndHalfSize: SIMD4<Float>(orbCenterX, dockY, orbR, orbR),
                        shapeAndTransform: SIMD4<Float>(orbR, 0.0, 1.0, 1.14 + 0.30 * orbActive),
                        styleParams: SIMD4<Float>(dockVis, 0.82 + 0.35 * orbActive, orbActive > 0.5 ? -2.8 : 0.55, 0.95 + 0.25 * orbActive),
                        tintOverride: SIMD4<Float>(0.22, 0.74, 0.97, 0.05 + 0.14 * orbActive)
                    )
                    count += 1
                }
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
            atmosphereParams: SIMD4<Float>(modeWarmth, prismRimBoostEnabled ? 1.35 : 1.0, 36.0, Float(islandHeightPt * 0.5)),
            islandParams: SIMD4<Float>(Float(islCenter.x), Float(islCenter.y), Float(islandWidthPt * 0.5), islandPullStretchPt)
        )
    }
}
