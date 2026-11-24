import UIKit
import CoreMotion
import CoreHaptics
import QuartzCore
import simd

// MARK: - CoreHaptics + UIImpact Liquid Tactile Engine

@MainActor
final class HapticsManager {
    static let shared = HapticsManager()

    var isEnabled: Bool = true

    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let notificationGen = UINotificationFeedbackGenerator()

    private var hapticEngine: CHHapticEngine?
    private var supportsCoreHaptics: Bool = false
    private var lastBounceTimestamp: CFTimeInterval = 0

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

    // MARK: - Custom CoreHaptics Liquid Waveforms

    /// Waveform 1: 「水滴吸入動態島」(Accelerating liquid suction ramp + deep resonant gulp)
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

    /// Waveform 2: 「拉絲斷裂」(Surface-tension stretch build + crisp capillary snap + micro droplet echo)
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

    /// Waveform 3: 「彈性撞牆」(Velocity-scaled jelly compression thud + elastic rebound)
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

    func morphImpact() {
        playLiquidSnap()
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

// MARK: - CoreMotion Gyroscope Specular & Accelerometer Gravity Controller

@MainActor
final class MotionManager {
    private let manager = CMMotionManager()
    private(set) var isActive: Bool = false

    private(set) var targetLightDir = SIMD2<Float>(-0.58, -0.81)
    private(set) var screenGravity = SIMD2<Float>(0.0, 1.0)

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
            return
        }

        isActive = true
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion = motion else { return }
            let gx = Float(motion.gravity.x)
            let gy = Float(-motion.gravity.y)
            let rotX = Float(motion.rotationRate.y) * 0.11
            let rotY = Float(motion.rotationRate.x) * 0.11

            var vec = SIMD2<Float>(
                gx * 1.35 + rotX - 0.18,
                gy * 1.15 + rotY - 0.45
            )
            let len = simd_length(vec)
            let normalizedVec = len > 0.08 ? (vec / len) : SIMD2<Float>(-0.58, -0.81)

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.screenGravity = SIMD2<Float>(gx, gy)
                self.targetLightDir = normalizedVec
            }
        }
    }

    func stop() {
        guard isActive else { return }
        manager.stopDeviceMotionUpdates()
        isActive = false
        targetLightDir = SIMD2<Float>(-0.58, -0.81)
        screenGravity = SIMD2<Float>(0.0, 1.0)
    }
}
