import UIKit
import CoreMotion
import CoreHaptics
import QuartzCore
import simd

// MARK: - CoreHaptics + UIImpact Precision Liquid Tactile Engine

@MainActor
final class HapticsManager {
    static let shared = HapticsManager()

    var isEnabled: Bool = true
    var dropletResonanceEnabled: Bool = true

    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let notificationGen = UINotificationFeedbackGenerator()

    private var hapticEngine: CHHapticEngine?
    private var supportsCoreHaptics: Bool = false
    private var lastBounceTimestamp: CFTimeInterval = 0
    private var lastRatchetTimestamp: CFTimeInterval = 0

    private init() {
        prepareAll()
        setupCoreHaptics()
    }

    func prepareAll() {
        lightGen.prepare()
        mediumGen.prepare()
        rigidGen.prepare()
        softGen.prepare()
        selectionGen.prepare()
    }

    private func setupCoreHaptics() {
        let capabilities = CHHapticEngine.capabilitiesForHardware()
        guard capabilities.supportsHaptics else { return }
        supportsCoreHaptics = true

        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.hapticEngine?.start()
                }
            }
            try engine.start()
            hapticEngine = engine
        } catch {
            supportsCoreHaptics = false
        }
    }

    func ensureEngineRunning() {
        guard supportsCoreHaptics else { return }
        try? hapticEngine?.start()
    }

    // MARK: - Flagship Pomodoro Hourglass CoreHaptics Waveforms

    /// Waveform ①: 設定時間的「精密機械棘輪聲」(Precision Swiss-Watch Mechanical Ratchet Detent)
    func playPrecisionRatchetTick(angularSpeed: Float = 1.0) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastRatchetTimestamp >= 0.018 else { return }
        lastRatchetTimestamp = now

        let speedFactor = min(max(angularSpeed, 0.0), 3.0)
        let primaryIntensity = min(0.92, 0.56 + speedFactor * 0.12)

        guard supportsCoreHaptics, let engine = hapticEngine else {
            rigidGen.impactOccurred(intensity: CGFloat(primaryIntensity))
            return
        }

        do {
            try engine.start()
            // Primary ultra-crisp watch-bezel tooth click
            let toothClick = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: primaryIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.96)
                ],
                relativeTime: 0.0
            )
            // Micro-spring detent lock 11ms later
            let detentSettle = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: primaryIntensity * 0.34),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.78)
                ],
                relativeTime: 0.011
            )
            let pattern = try CHHapticPattern(events: [toothClick, detentSettle], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            rigidGen.impactOccurred(intensity: CGFloat(primaryIntensity))
        }
    }

    /// Waveform ②: 沙漏水滴落入下腔時的「極輕柔水珠共鳴（可於控制中心開關）」
    func playDropletResonance() {
        guard isEnabled && dropletResonanceEnabled else { return }
        guard supportsCoreHaptics, let engine = hapticEngine else {
            softGen.impactOccurred(intensity: 0.28)
            return
        }

        do {
            try engine.start()
            // Whisper-soft surface-tension kiss as teardrop enters lower pool
            let waterKiss = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.32),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12)
                ],
                relativeTime: 0.0
            )
            // Warm capillary ripple resonance decay
            let poolRipple = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.18),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08)
                ],
                relativeTime: 0.008,
                duration: 0.072
            )
            let decayCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.008, value: 0.20),
                    .init(relativeTime: 0.040, value: 0.09),
                    .init(relativeTime: 0.080, value: 0.01)
                ],
                relativeTime: 0.0
            )
            let pattern = try CHHapticPattern(events: [waterKiss, poolRipple], parameterCurves: [decayCurve])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            softGen.impactOccurred(intensity: 0.28)
        }
    }

    /// Waveform ③: 番茄鐘完成時的「三連音液態諧振波」(Ascending Triplet Liquid Harmonic Chime)
    func playPomodoroTripletResonance() {
        guard isEnabled else { return }
        guard supportsCoreHaptics, let engine = hapticEngine else {
            notificationGen.notificationOccurred(.success)
            return
        }

        do {
            try engine.start()
            let note1 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.68),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.24)
                ],
                relativeTime: 0.00
            )
            let note2 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.84),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.48)
                ],
                relativeTime: 0.16
            )
            let note3 = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.00),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.72)
                ],
                relativeTime: 0.33
            )
            let harmonicTail = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.56),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.32)
                ],
                relativeTime: 0.34,
                duration: 0.44
            )
            let tailCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.34, value: 0.58),
                    .init(relativeTime: 0.54, value: 0.28),
                    .init(relativeTime: 0.78, value: 0.02)
                ],
                relativeTime: 0.0
            )
            let pattern = try CHHapticPattern(
                events: [note1, note2, note3, harmonicTail],
                parameterCurves: [tailCurve]
            )
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            notificationGen.notificationOccurred(.success)
        }
    }

    // MARK: - Spatial Liquid Interaction Waveforms

    /// 「水滴吸入動態島」(Accelerating liquid suction ramp + deep resonant gulp)
    func playIslandSwallow() {
        guard isEnabled else { return }
        guard supportsCoreHaptics, let engine = hapticEngine else {
            rigidGen.impactOccurred(intensity: 0.95)
            return
        }

        do {
            try engine.start()
            let suctionRamp = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
                ],
                relativeTime: 0.0,
                duration: 0.20
            )
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0.0, value: 0.30),
                    .init(relativeTime: 0.18, value: 0.95),
                    .init(relativeTime: 0.20, value: 0.20)
                ],
                relativeTime: 0.0
            )
            let sharpnessCurve = CHHapticParameterCurve(
                parameterID: .hapticSharpnessControl,
                controlPoints: [
                    .init(relativeTime: 0.0, value: 0.20),
                    .init(relativeTime: 0.18, value: 0.72)
                ],
                relativeTime: 0.0
            )
            let deepGulp = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.16)
                ],
                relativeTime: 0.21
            )
            let pattern = try CHHapticPattern(
                events: [suctionRamp, deepGulp],
                parameterCurves: [intensityCurve, sharpnessCurve]
            )
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            rigidGen.impactOccurred(intensity: 0.95)
        }
    }

    /// 「拉絲斷裂」(Surface-tension stretch build + crisp capillary snap + micro droplet echo)
    func playLiquidSnap() {
        guard isEnabled else { return }
        guard supportsCoreHaptics, let engine = hapticEngine else {
            rigidGen.impactOccurred(intensity: 0.92)
            return
        }

        do {
            try engine.start()
            let stretchTension = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.48),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.78)
                ],
                relativeTime: 0.0,
                duration: 0.075
            )
            let snapPop = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.98),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.94)
                ],
                relativeTime: 0.08
            )
            let recoilEcho = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.44),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.58)
                ],
                relativeTime: 0.135
            )
            let pattern = try CHHapticPattern(events: [stretchTension, snapPop, recoilEcho], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            rigidGen.impactOccurred(intensity: 0.92)
        }
    }

    /// 「彈性撞牆」(Velocity-scaled jelly compression thud + elastic rebound)
    func wallBounce(speed: Float) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastBounceTimestamp >= 0.052 else { return }
        lastBounceTimestamp = now

        let norm = min(max((speed - 95.0) / 1200.0, 0.22), 1.0)
        guard supportsCoreHaptics, let engine = hapticEngine else {
            rigidGen.impactOccurred(intensity: CGFloat(norm))
            return
        }

        do {
            try engine.start()
            let compressHit = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: norm),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.30 + norm * 0.35)
                ],
                relativeTime: 0.0
            )
            let jellyRebound = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: norm * 0.52),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.62)
                ],
                relativeTime: 0.046
            )
            let pattern = try CHHapticPattern(events: [compressHit, jellyRebound], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            rigidGen.impactOccurred(intensity: CGFloat(norm))
        }
    }

    // MARK: - Standard Tactile Feedbacks

    func tapLight(intensity: CGFloat = 0.75) {
        guard isEnabled else { return }
        lightGen.impactOccurred(intensity: intensity)
    }

    func tapMedium(intensity: CGFloat = 0.85) {
        guard isEnabled else { return }
        mediumGen.impactOccurred(intensity: intensity)
    }

    func tapSoft(intensity: CGFloat = 0.70) {
        guard isEnabled else { return }
        softGen.impactOccurred(intensity: intensity)
    }

    func selection() {
        guard isEnabled else { return }
        selectionGen.selectionChanged()
    }

    func success() {
        guard isEnabled else { return }
        notificationGen.notificationOccurred(.success)
    }

    func sliderTick(normalized: Double, buckets: Int = 18, lastBucket: inout Int) {
        let bucket = min(buckets, max(0, Int((normalized * Double(buckets)).rounded())))
        if lastBucket != -1 && bucket != lastBucket {
            if isEnabled {
                lightGen.impactOccurred(intensity: 0.36)
            }
        }
        lastBucket = bucket
    }
}

// MARK: - 120Hz CoreMotion Gyroscope Specular, Fluid Slosh & Physical Phone Flip Detector

@MainActor
final class MotionManager {
    private enum DevicePosture {
        case upright
        case inverted
        case faceDown
    }

    private let manager = CMMotionManager()
    private(set) var isActive: Bool = false

    private(set) var targetLightDir = SIMD2<Float>(-0.58, -0.81)
    private(set) var screenGravity = SIMD2<Float>(0.0, 1.0)
    private(set) var inPlaneRotationRate: Float = 0.0

    var onPhoneFlipDetected: (() -> Void)?

    private var posture: DevicePosture = .upright
    private var lastFlipTimestamp: CFTimeInterval = 0

    func setEnabled(_ enabled: Bool) {
        if enabled {
            startIfNeeded()
        } else {
            stop()
        }
    }

    private func startIfNeeded() {
        guard !isActive else { return }
        guard manager.isDeviceMotionAvailable else {
            targetLightDir = SIMD2<Float>(-0.58, -0.81)
            screenGravity = SIMD2<Float>(0.0, 1.0)
            inPlaneRotationRate = 0.0
            return
        }

        isActive = true
        manager.deviceMotionUpdateInterval = 1.0 / 120.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            let gx = Float(motion.gravity.x)
            let gyScreen = Float(-motion.gravity.y) // +1 when phone held upright in portrait
            let rawGy = Float(motion.gravity.y)     // -1 upright, +1 upside-down inverted
            let rawGz = Float(motion.gravity.z)     // -1 face-up, +1 face-down
            let rotX = Float(motion.rotationRate.y) * 0.11
            let rotY = Float(motion.rotationRate.x) * 0.11
            let rotZ = Float(motion.rotationRate.z)

            let vec = SIMD2<Float>(
                gx * 1.35 + rotX - 0.18,
                gyScreen * 1.15 + rotY - 0.45
            )
            let len = simd_length(vec)
            let normalizedVec = len > 0.08 ? (vec / len) : SIMD2<Float>(-0.58, -0.81)

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.screenGravity = SIMD2<Float>(gx, gyScreen)
                self.targetLightDir = normalizedVec
                self.inPlaneRotationRate = rotZ
                self.evaluatePhysicalHourglassFlip(rawGy: rawGy, rawGz: rawGz)
            }
        }
    }

    private func evaluatePhysicalHourglassFlip(rawGy: Float, rawGz: Float) {
        let now = CACurrentMediaTime()

        // Re-arm when phone returns to normal upright or face-up comfortable viewing zone
        if rawGy < -0.22 && rawGz < 0.26 {
            posture = .upright
            return
        }

        guard now - lastFlipTimestamp > 1.25 else { return }

        // Trigger 1: Phone turned upside-down like a real glass hourglass (top pointing down)
        if posture != .inverted && rawGy > 0.56 {
            posture = .inverted
            lastFlipTimestamp = now
            onPhoneFlipDetected?()
            return
        }

        // Trigger 2: Phone flipped face-down onto desk / palm
        if posture != .faceDown && rawGz > 0.72 {
            posture = .faceDown
            lastFlipTimestamp = now
            onPhoneFlipDetected?()
        }
    }

    func stop() {
        guard isActive else { return }
        manager.stopDeviceMotionUpdates()
        isActive = false
        targetLightDir = SIMD2<Float>(-0.58, -0.81)
        screenGravity = SIMD2<Float>(0.0, 1.0)
        inPlaneRotationRate = 0.0
    }
}
