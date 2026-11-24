import SwiftUI
import UIKit
import QuartzCore
import Observation
import simd

@Observable
final class GlassSceneController {
    // MARK: - User-Adjustable Optical & Wallpaper Settings

    var wallpaper: WallpaperPreset = .aurora
    var tintMode: GlassTintMode = .clear
    var lensShape: LensShapeMode = .circle

    var refraction: Double = 48.0
    var bezel: Double = 34.0
    var dispersion: Double = 0.13
    var frost: Double = 0.35

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

    // MARK: - Mini Control Center States

    var flashlightOn: Bool = false
    var sceneBrightness: Double = 1.0

    // MARK: - Dynamic Music Card States

    var isPlayingMusic: Bool = true
    var currentTrackIndex: Int = 0
    var trackProgress: Double = 0.28 // 0...1

    var currentTrack: MusicTrack {
        MusicTrack.catalog[currentTrackIndex % MusicTrack.catalog.count]
    }

    // MARK: - Collapsible Card Visibility & Spring Reveal Progress

    var showMusicCard: Bool = true
    var showControlCenter: Bool = false
    var showSettingsDrawer: Bool = false
    var showGestureHint: Bool = true

    private(set) var musicReveal: CGFloat = 1.0
    private(set) var controlReveal: CGFloat = 0.0
    private(set) var drawerReveal: CGFloat = 0.0

    // MARK: - Live Positioned Geometry (Synced 1:1 Between SwiftUI Overlays & Metal)

    private(set) var lensPosition: CGPoint = CGPoint(x: 196, y: 420)
    private(set) var lensHalfSize: CGSize = CGSize(width: 94, height: 94)
    private(set) var lensCornerRadius: CGFloat = 94

    private(set) var musicCardCenter: CGPoint = CGPoint(x: 196, y: 168)
    private(set) var controlCardCenter: CGPoint = CGPoint(x: 196, y: 318)

    // Live FPS readout (updated every 0.25s to avoid 120Hz text re-layout)
    private(set) var currentFPS: Int = 120
    private(set) var currentFrameMs: Double = 8.3

    var hasCustomPhoto: Bool = false

    // MARK: - Observation-Ignored 120Hz Physics & GPU Buffers

    @ObservationIgnored var sceneUniforms = SceneUniforms()
    @ObservationIgnored var elementUniforms = [GlassElementUniform](repeating: GlassElementUniform(), count: 8)

    @ObservationIgnored var customPhotoImage: UIImage?
    @ObservationIgnored var customPhotoRevision: Int = 0
    @ObservationIgnored var customPhotoAspect: Float = 0.75

    @ObservationIgnored private let motionManager = MotionManager()

    @ObservationIgnored private var hasInitializedLayout: Bool = false
    @ObservationIgnored private var safeTopInset: CGFloat = 59
    @ObservationIgnored private var safeBottomInset: CGFloat = 34
    @ObservationIgnored private var viewportSize: CGSize = CGSize(width: 393, height: 852)

    // Hero Lens physics state
    @ObservationIgnored private var isDraggingLens: Bool = false
    @ObservationIgnored private var lensDragStart: CGPoint = .zero
    @ObservationIgnored private var lensVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var lensZoomScale: Float = 1.0
    @ObservationIgnored private var pinchStartScale: Float = 1.0

    // Spring-interpolated lens shape & jelly deformation
    @ObservationIgnored private var animHalfSize = SIMD2<Float>(94, 94)
    @ObservationIgnored private var animHalfSizeVel = SIMD2<Float>(0, 0)
    @ObservationIgnored private var animCornerRadius: Float = 94
    @ObservationIgnored private var animCornerVel: Float = 0

    @ObservationIgnored private var lensLiftScale: Float = 1.0
    @ObservationIgnored private var lensLiftVel: Float = 0.0
    @ObservationIgnored private var lensStretchFactor: Float = 1.0
    @ObservationIgnored private var lensStretchVel: Float = 0.0
    @ObservationIgnored private var lensStretchAngle: Float = 0.0

    // Draggable cards physics state
    @ObservationIgnored private var musicOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var musicDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var musicVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var isDraggingMusic: Bool = false
    @ObservationIgnored private var musicRevealVel: Float = 0

    @ObservationIgnored private var controlOffset = SIMD2<Float>(0, 0)
    @ObservationIgnored private var controlDragStart = SIMD2<Float>(0, 0)
    @ObservationIgnored private var controlVelocity = SIMD2<Float>(0, 0)
    @ObservationIgnored private var isDraggingControl: Bool = false
    @ObservationIgnored private var controlRevealVel: Float = 0
    @ObservationIgnored private var controlAnchorY: Float = 310

    @ObservationIgnored private var drawerRevealVel: Float = 0
    @ObservationIgnored private var spotlightAnim: Float = 0

    // Smoothed specular light vector
    @ObservationIgnored private var currentLightDir = SIMD2<Float>(-0.58, -0.81)
    @ObservationIgnored private var touchLightPos: SIMD2<Float>?

    // Timing & FPS accumulator
    @ObservationIgnored private var startTime: CFTimeInterval = CACurrentMediaTime()
    @ObservationIgnored private var lastStepTime: CFTimeInterval = 0
    @ObservationIgnored private var fpsFrameCount: Int = 0
    @ObservationIgnored private var fpsAccumDuration: CFTimeInterval = 0
    @ObservationIgnored private var audioProgressAccum: Double = 0

    init() {
        motionManager.setEnabled(true)
    }

    // MARK: - Layout & Safe Area Sync

    func updateGeometry(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        guard size.width > 40, size.height > 40 else { return }
        viewportSize = size
        safeTopInset = safeTop
        safeBottomInset = safeBottom

        if !hasInitializedLayout {
            hasInitializedLayout = true
            lensPosition = CGPoint(x: size.width * 0.5, y: size.height * 0.53)
            let baseMusicY = safeTop + 112
            musicCardCenter = CGPoint(x: size.width * 0.5, y: baseMusicY)
            controlAnchorY = Float(safeTop + 266)
            controlCardCenter = CGPoint(x: size.width * 0.5, y: CGFloat(controlAnchorY))
        }
    }

    // MARK: - Hero Lens Gesture Handlers

    func beginLensDrag() {
        if !isDraggingLens {
            isDraggingLens = true
            lensDragStart = lensPosition
            lensVelocity = .zero
            showGestureHint = false
            HapticsManager.shared.tapSoft(intensity: 0.55)
        }
    }

    func updateLensDrag(translation: CGSize, velocity: CGSize, location: CGPoint) {
        if !isDraggingLens {
            beginLensDrag()
        }
        var targetX = lensDragStart.x + translation.width
        var targetY = lensDragStart.y + translation.height

        // Rubber-band softly near screen boundaries
        let minX = lensHalfSize.width * 0.85 + 8
        let maxX = viewportSize.width - lensHalfSize.width * 0.85 - 8
        let minY = safeTopInset + 48 + lensHalfSize.height * 0.85
        let maxY = viewportSize.height - safeBottomInset - 82 - lensHalfSize.height * 0.85

        if targetX < minX { targetX = minX + (targetX - minX) * 0.32 }
        if targetX > maxX { targetX = maxX + (targetX - maxX) * 0.32 }
        if targetY < minY { targetY = minY + (targetY - minY) * 0.32 }
        if targetY > maxY { targetY = maxY + (targetY - maxY) * 0.32 }

        lensPosition = CGPoint(x: targetX, y: targetY)

        let vx = Float(velocity.width)
        let vy = Float(velocity.height)
        lensVelocity = lensVelocity * 0.35 + SIMD2<Float>(vx, vy) * 0.65
        touchLightPos = SIMD2<Float>(Float(location.x), Float(location.y))
    }

    func endLensDrag(velocity: CGSize) {
        isDraggingLens = false
        touchLightPos = nil
        let maxSpeed: Float = 2600.0
        var v = SIMD2<Float>(Float(velocity.width), Float(velocity.height))
        let speed = simd_length(v)
        if speed > maxSpeed {
            v = (v / speed) * maxSpeed
        }
        lensVelocity = v
    }

    func updateLensPinch(magnification: CGFloat) {
        showGestureHint = false
        let raw = pinchStartScale * Float(magnification)
        lensZoomScale = min(max(raw, 0.58), 1.82)
    }

    func endLensPinch() {
        pinchStartScale = lensZoomScale
        HapticsManager.shared.tapLight(intensity: 0.45)
    }

    func cycleLensShape() {
        showGestureHint = false
        lensShape = lensShape.next()
        // Inject elastic jelly pop impulse
        lensLiftVel += 3.4
        lensStretchVel += 2.2
        HapticsManager.shared.morphImpact()
    }

    func resetPlaygroundLayout() {
        lensShape = .circle
        lensZoomScale = 1.0
        pinchStartScale = 1.0
        lensVelocity = SIMD2<Float>(0, -180)
        lensPosition = CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.53)
        musicOffset = .zero
        musicVelocity = .zero
        controlOffset = .zero
        controlVelocity = .zero
        lensLiftVel += 3.0
        HapticsManager.shared.tapMedium()
    }

    // MARK: - Draggable Card Gesture Handlers

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
        musicVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.45
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
        controlVelocity = SIMD2<Float>(Float(velocity.width), Float(velocity.height)) * 0.45
    }

    // MARK: - Music Controls & Custom Photo Import

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

    // MARK: - 120Hz Lockstep Physics & Uniform Builder (Called per MTKView Draw)

    func stepFrame(now: CFTimeInterval, drawablePointSize: CGSize) {
        if drawablePointSize.width > 40, drawablePointSize.height > 40 {
            viewportSize = drawablePointSize
        }

        let rawDt: Double
        if lastStepTime == 0 {
            rawDt = 1.0 / 120.0
        } else {
            rawDt = now - lastStepTime
        }
        lastStepTime = now

        // Measure real ProMotion FPS (rolling 0.25s window)
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

        // Advance simulated music playback smoothly without extra Timers
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

        stepSpringReveals(dt: dt)
        stepHeroLensPhysics(dt: dt)
        stepDraggableCardsPhysics(dt: dt)
        stepLightingAndBuildUniforms(dt: dt, elapsed: elapsed)
    }

    private func stepSpringReveals(dt: Float) {
        // Second-order critically/under-damped springs for card open/close animations
        var mPos = Float(musicReveal)
        stepSpring1D(pos: &mPos, vel: &musicRevealVel, target: showMusicCard ? 1.0 : 0.0, omega: 22.0, zeta: 0.76, dt: dt)
        if abs(CGFloat(mPos) - musicReveal) > 0.0008 {
            musicReveal = CGFloat(max(0.0, mPos))
        } else if !showMusicCard && mPos < 0.002 && musicReveal != 0 {
            musicReveal = 0
        } else if showMusicCard && abs(mPos - 1.0) < 0.002 && musicReveal != 1.0 {
            musicReveal = 1.0
        }

        var cPos = Float(controlReveal)
        stepSpring1D(pos: &cPos, vel: &controlRevealVel, target: showControlCenter ? 1.0 : 0.0, omega: 22.0, zeta: 0.76, dt: dt)
        if abs(CGFloat(cPos) - controlReveal) > 0.0008 {
            controlReveal = CGFloat(max(0.0, cPos))
        } else if !showControlCenter && cPos < 0.002 && controlReveal != 0 {
            controlReveal = 0
        } else if showControlCenter && abs(cPos - 1.0) < 0.002 && controlReveal != 1.0 {
            controlReveal = 1.0
        }

        var dPos = Float(drawerReveal)
        stepSpring1D(pos: &dPos, vel: &drawerRevealVel, target: showSettingsDrawer ? 1.0 : 0.0, omega: 24.0, zeta: 0.82, dt: dt)
        if abs(CGFloat(dPos) - drawerReveal) > 0.0008 {
            drawerReveal = CGFloat(max(0.0, dPos))
        } else if !showSettingsDrawer && dPos < 0.002 && drawerReveal != 0 {
            drawerReveal = 0
        } else if showSettingsDrawer && abs(dPos - 1.0) < 0.002 && drawerReveal != 1.0 {
            drawerReveal = 1.0
        }

        let spotTarget: Float = flashlightOn ? 1.0 : 0.0
        spotlightAnim += (spotTarget - spotlightAnim) * min(1.0, dt * 14.0)
    }

    private func stepHeroLensPhysics(dt: Float) {
        // 1. Morph base shape + zoom scale smoothly via spring
        let targetHalf = lensShape.baseHalfSize * lensZoomScale
        let targetCorner = lensShape.baseCornerRadius * lensZoomScale

        stepSpring2D(pos: &animHalfSize, vel: &animHalfSizeVel, target: targetHalf, omega: 20.0, zeta: 0.66, dt: dt)
        stepSpring1D(pos: &animCornerRadius, vel: &animCornerVel, target: targetCorner, omega: 20.0, zeta: 0.66, dt: dt)

        let targetLift: Float = isDraggingLens ? 1.06 : 1.0
        stepSpring1D(pos: &lensLiftScale, vel: &lensLiftVel, target: targetLift, omega: 24.0, zeta: 0.56, dt: dt)

        let effectiveHalf = animHalfSize * max(0.5, lensLiftScale)
        let effectiveCorner = animCornerRadius * max(0.5, lensLiftScale)

        if abs(CGFloat(effectiveHalf.x) - lensHalfSize.width) > 0.08 ||
           abs(CGFloat(effectiveHalf.y) - lensHalfSize.height) > 0.08 {
            lensHalfSize = CGSize(width: CGFloat(effectiveHalf.x), height: CGFloat(effectiveHalf.y))
        }
        if abs(CGFloat(effectiveCorner) - lensCornerRadius) > 0.08 {
            lensCornerRadius = CGFloat(effectiveCorner)
        }

        // 2. Inertial glide & wall restitution bounce when finger is released
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)
        let minX = effectiveHalf.x + 10.0
        let maxX = max(minX + 1.0, w - effectiveHalf.x - 10.0)
        let minY = Float(safeTopInset) + 52.0 + effectiveHalf.y
        let maxY = max(minY + 1.0, h - Float(safeBottomInset) - 86.0 - effectiveHalf.y)

        if !isDraggingLens {
            var pos = SIMD2<Float>(Float(lensPosition.x), Float(lensPosition.y))
            pos += lensVelocity * dt

            // Fluid viscous damping
            lensVelocity *= exp(-2.05 * dt)

            let restitution: Float = 0.74
            if pos.x < minX {
                let impactSpeed = abs(lensVelocity.x)
                pos.x = minX
                if lensVelocity.x < 0 {
                    lensVelocity.x = -lensVelocity.x * restitution
                    injectWallSquish(normalAngle: 0.0, impactSpeed: impactSpeed)
                }
            } else if pos.x > maxX {
                let impactSpeed = abs(lensVelocity.x)
                pos.x = maxX
                if lensVelocity.x > 0 {
                    lensVelocity.x = -lensVelocity.x * restitution
                    injectWallSquish(normalAngle: 0.0, impactSpeed: impactSpeed)
                }
            }

            if pos.y < minY {
                let impactSpeed = abs(lensVelocity.y)
                pos.y = minY
                if lensVelocity.y < 0 {
                    lensVelocity.y = -lensVelocity.y * restitution
                    injectWallSquish(normalAngle: .pi * 0.5, impactSpeed: impactSpeed)
                }
            } else if pos.y > maxY {
                let impactSpeed = abs(lensVelocity.y)
                pos.y = maxY
                if lensVelocity.y > 0 {
                    lensVelocity.y = -lensVelocity.y * restitution
                    injectWallSquish(normalAngle: .pi * 0.5, impactSpeed: impactSpeed)
                }
            }

            if simd_length(lensVelocity) < 2.0 {
                lensVelocity = .zero
            }

            let newPoint = CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.y))
            if hypot(newPoint.x - lensPosition.x, newPoint.y - lensPosition.y) > 0.04 {
                lensPosition = newPoint
            }
        }

        // 3. Velocity-aligned liquid squash & stretch spring
        let speed = simd_length(lensVelocity)
        if speed > 28.0 {
            let targetAngle = atan2(lensVelocity.y, lensVelocity.x)
            // Shortest angular interpolation
            var deltaAngle = targetAngle - lensStretchAngle
            while deltaAngle > .pi { deltaAngle -= 2.0 * .pi }
            while deltaAngle < -.pi { deltaAngle += 2.0 * .pi }
            lensStretchAngle += deltaAngle * min(1.0, dt * 18.0)
        }

        let targetStretch = 1.0 + min(0.27, speed / 2500.0)
        stepSpring1D(pos: &lensStretchFactor, vel: &lensStretchVel, target: targetStretch, omega: 26.0, zeta: 0.38, dt: dt)
        lensStretchFactor = min(max(lensStretchFactor, 0.72), 1.38)
    }

    private func injectWallSquish(normalAngle: Float, impactSpeed: Float) {
        guard impactSpeed > 75.0 else { return }
        lensStretchAngle = normalAngle
        // Negative stretch impulse along wall normal compresses droplet flat against the wall!
        let impulse = min(4.2, impactSpeed * 0.0038)
        lensStretchVel -= impulse
        HapticsManager.shared.wallBounce(speed: impactSpeed)
    }

    private func stepDraggableCardsPhysics(dt: Float) {
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)

        // Music Card inertial glide + soft boundary clamp
        let baseMusicPos = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 112.0)
        if !isDraggingMusic {
            musicOffset += musicVelocity * dt
            musicVelocity *= exp(-6.5 * dt)
            if simd_length(musicVelocity) < 1.5 { musicVelocity = .zero }

            let cardPos = baseMusicPos + musicOffset
            let boundMinX: Float = 176.0
            let boundMaxX = max(boundMinX, w - 176.0)
            let boundMinY = Float(safeTopInset) + 98.0
            let boundMaxY = max(boundMinY, h - Float(safeBottomInset) - 140.0)

            var clamped = cardPos
            clamped.x = min(max(clamped.x, boundMinX), boundMaxX)
            clamped.y = min(max(clamped.y, boundMinY), boundMaxY)
            musicOffset += (clamped - cardPos) * min(1.0, dt * 14.0)
        }
        let finalMusic = baseMusicPos + musicOffset
        if hypot(CGFloat(finalMusic.x) - musicCardCenter.x, CGFloat(finalMusic.y) - musicCardCenter.y) > 0.06 {
            musicCardCenter = CGPoint(x: CGFloat(finalMusic.x), y: CGFloat(finalMusic.y))
        }

        // Control Center Card smooth anchor + inertial glide
        let desiredAnchorY = Float(safeTopInset) + (showMusicCard ? 268.0 : 142.0)
        controlAnchorY += (desiredAnchorY - controlAnchorY) * min(1.0, dt * 12.0)
        let baseControlPos = SIMD2<Float>(w * 0.5, controlAnchorY)

        if !isDraggingControl {
            controlOffset += controlVelocity * dt
            controlVelocity *= exp(-6.5 * dt)
            if simd_length(controlVelocity) < 1.5 { controlVelocity = .zero }

            let cardPos = baseControlPos + controlOffset
            let boundMinX: Float = 176.0
            let boundMaxX = max(boundMinX, w - 176.0)
            let boundMinY = Float(safeTopInset) + 124.0
            let boundMaxY = max(boundMinY, h - Float(safeBottomInset) - 165.0)

            var clamped = cardPos
            clamped.x = min(max(clamped.x, boundMinX), boundMaxX)
            clamped.y = min(max(clamped.y, boundMinY), boundMaxY)
            controlOffset += (clamped - cardPos) * min(1.0, dt * 14.0)
        }
        let finalControl = baseControlPos + controlOffset
        if hypot(CGFloat(finalControl.x) - controlCardCenter.x, CGFloat(finalControl.y) - controlCardCenter.y) > 0.06 {
            controlCardCenter = CGPoint(x: CGFloat(finalControl.x), y: CGFloat(finalControl.y))
        }
    }

    private func stepLightingAndBuildUniforms(dt: Float, elapsed: Float) {
        let w = Float(viewportSize.width)
        let h = Float(viewportSize.height)

        // Blend gyro tilt vector with active finger touch direction when dragging
        var desiredLight: SIMD2<Float>
        if gyroEnabled {
            desiredLight = motionManager.targetLightDir
        } else {
            desiredLight = SIMD2<Float>(
                cos(elapsed * 0.45) * 0.55 - 0.35,
                sin(elapsed * 0.38) * 0.45 - 0.68
            )
        }

        if let touch = touchLightPos {
            let lensC = SIMD2<Float>(Float(lensPosition.x), Float(lensPosition.y))
            let delta = touch - lensC
            let len = simd_length(delta)
            if len > 8.0 {
                desiredLight = simd_normalize(desiredLight * 0.55 + (delta / len) * 0.45)
            }
        }

        currentLightDir += (desiredLight - currentLightDir) * min(1.0, dt * 14.0)
        let normLight = simd_length(currentLightDir) > 1e-3 ? simd_normalize(currentLightDir) : SIMD2<Float>(-0.58, -0.81)

        // Spotlight origin tracks Mini Control Center flashlight tile when visible, else top-center
        let cardW = min(w - 32.0, 344.0)
        let spotOrigin: SIMD2<Float>
        if controlReveal > 0.05 {
            spotOrigin = SIMD2<Float>(
                Float(controlCardCenter.x) - cardW * 0.25,
                Float(controlCardCenter.y) - 32.0
            )
        } else {
            spotOrigin = SIMD2<Float>(w * 0.5, Float(safeTopInset) + 20.0)
        }

        let textMix: Float
        if wallpaper == .customPhoto {
            textMix = showTypographyOnPhoto ? 0.72 : 0.0
        } else {
            textMix = 1.0
        }

        // Populate Glass Elements array (z-order back-to-front)
        var count = 0

        // [0] Floating Liquid Dock
        let dockHalfW = min(w - 32.0, 348.0) * 0.5
        let dockY = h - Float(safeBottomInset) - 36.0
        elementUniforms[count] = GlassElementUniform(
            centerAndHalfSize: SIMD4<Float>(w * 0.5, dockY, dockHalfW, 34.0),
            shapeAndTransform: SIMD4<Float>(34.0, 0.0, 1.0, 1.05),
            styleParams: SIMD4<Float>(1.0, 0.55, 0.55, 0.90),
            tintOverride: SIMD4<Float>(0.90, 0.96, 1.0, 0.04)
        )
        count += 1

        // [1] Dynamic Music Player Card
        if musicReveal > 0.005 {
            let mScale = Float(0.84 + 0.16 * musicReveal)
            let mHalfW = (min(w - 32.0, 344.0) * 0.5) * mScale
            let mHalfH: Float = 57.0 * mScale
            let mSpeed = simd_length(musicVelocity)
            let mAngle = mSpeed > 20.0 ? atan2(musicVelocity.y, musicVelocity.x) : 0.0
            let mStretch = 1.0 + min(0.08, mSpeed / 3600.0)
            let trackTint = currentTrack.shaderTint
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(Float(musicCardCenter.x), Float(musicCardCenter.y), mHalfW, mHalfH),
                shapeAndTransform: SIMD4<Float>(28.0 * mScale, mAngle, mStretch, 1.08),
                styleParams: SIMD4<Float>(Float(min(1.0, musicReveal)), 0.58, 0.52, isDraggingMusic ? 1.25 : 0.95),
                tintOverride: SIMD4<Float>(trackTint.x, trackTint.y, trackTint.z, isPlayingMusic ? 0.13 : 0.04)
            )
            count += 1
        }

        // [2] Mini Control Center Card
        if controlReveal > 0.005 {
            let cScale = Float(0.84 + 0.16 * controlReveal)
            let cHalfW = (min(w - 32.0, 344.0) * 0.5) * cScale
            let cHalfH: Float = 84.0 * cScale
            let cSpeed = simd_length(controlVelocity)
            let cAngle = cSpeed > 20.0 ? atan2(controlVelocity.y, controlVelocity.x) : 0.0
            let cStretch = 1.0 + min(0.08, cSpeed / 3600.0)
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(Float(controlCardCenter.x), Float(controlCardCenter.y), cHalfW, cHalfH),
                shapeAndTransform: SIMD4<Float>(30.0 * cScale, cAngle, cStretch, flashlightOn ? 1.32 : 1.08),
                styleParams: SIMD4<Float>(Float(min(1.0, controlReveal)), 0.56, 0.58, isDraggingControl ? 1.25 : 0.98),
                tintOverride: SIMD4<Float>(0.96, 0.88, 0.58, flashlightOn ? 0.14 : 0.03)
            )
            count += 1
        }

        // [3] Main Hero Liquid Lens
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
                isDraggingLens ? 1.28 : 1.15
            ),
            styleParams: SIMD4<Float>(1.0, 1.0, 0.0, isDraggingLens ? 1.32 : 1.02),
            tintOverride: SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
        )
        count += 1

        // [4] Studio Settings Drawer (slides up cleanly above Dock when open)
        if drawerReveal > 0.005 {
            let dScale = Float(0.92 + 0.08 * drawerReveal)
            let drawerH: Float = 352.0
            let drawerHalfW = (min(w - 24.0, 366.0) * 0.5) * dScale
            let drawerHalfH = (drawerH * 0.5) * dScale
            let drawerBaseY = h - Float(safeBottomInset) - 82.0 - drawerH * 0.5
            let slideOffset = (1.0 - Float(min(1.0, drawerReveal))) * 44.0
            elementUniforms[count] = GlassElementUniform(
                centerAndHalfSize: SIMD4<Float>(w * 0.5, drawerBaseY + slideOffset, drawerHalfW, drawerHalfH),
                shapeAndTransform: SIMD4<Float>(32.0 * dScale, 0.0, 1.0, 1.12),
                styleParams: SIMD4<Float>(Float(min(1.0, drawerReveal)), 0.48, 0.95, 1.18),
                tintOverride: SIMD4<Float>(0.08, 0.12, 0.22, tintMode == .light ? 0.0 : 0.18)
            )
            count += 1
        }

        sceneUniforms = SceneUniforms(
            viewportAndTime: SIMD4<Float>(w, h, elapsed, Float(wallpaper.rawValue)),
            opticalParams: SIMD4<Float>(Float(refraction), Float(bezel), Float(dispersion), Float(frost)),
            lightingParams: SIMD4<Float>(normLight.x, normLight.y, Float(tintMode.rawValue), Float(sceneBrightness)),
            spotlightParams: SIMD4<Float>(spotOrigin.x, spotOrigin.y, -normLight.x * 0.45, spotlightAnim),
            layerFlags: SIMD4<Float>(Float(count), hasCustomPhoto ? 1.0 : 0.0, customPhotoAspect, textMix)
        )
    }

    // MARK: - Damped Harmonic Spring Integrators

    private func stepSpring1D(
        pos: inout Float,
        vel: inout Float,
        target: Float,
        omega: Float,
        zeta: Float,
        dt: Float
    ) {
        let force = -omega * omega * (pos - target) - 2.0 * zeta * omega * vel
        vel += force * dt
        pos += vel * dt
    }

    private func stepSpring2D(
        pos: inout SIMD2<Float>,
        vel: inout SIMD2<Float>,
        target: SIMD2<Float>,
        omega: Float,
        zeta: Float,
        dt: Float
    ) {
        let force = -omega * omega * (pos - target) - 2.0 * zeta * omega * vel
        vel += force * dt
        pos += vel * dt
    }
}
