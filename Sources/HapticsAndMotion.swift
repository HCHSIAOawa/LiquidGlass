import UIKit
import CoreMotion
import QuartzCore
import simd

// MARK: - Tactile Haptics Engine

final class HapticsManager {
    static let shared = HapticsManager()

    var isEnabled: Bool = true

    private let lightGen = UIImpactFeedbackGenerator(style: .light)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let rigidGen = UIImpactFeedbackGenerator(style: .rigid)
    private let softGen = UIImpactFeedbackGenerator(style: .soft)
    private let selectionGen = UISelectionFeedbackGenerator()
    private let notificationGen = UINotificationFeedbackGenerator()

    private var lastBounceTimestamp: CFTimeInterval = 0

    private init() {
        prepareAll()
    }

    func prepareAll() {
        lightGen.prepare()
        mediumGen.prepare()
        rigidGen.prepare()
        softGen.prepare()
        selectionGen.prepare()
    }

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
        guard isEnabled else { return }
        rigidGen.impactOccurred(intensity: 0.92)
    }

    func selection() {
        guard isEnabled else { return }
        selectionGen.selectionChanged()
    }

    func success() {
        guard isEnabled else { return }
        notificationGen.notificationOccurred(.success)
    }

    func wallBounce(speed: Float) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        guard now - lastBounceTimestamp >= 0.048 else { return }
        lastBounceTimestamp = now

        let normalized = min(max((speed - 95.0) / 1200.0, 0.22), 1.0)
        rigidGen.impactOccurred(intensity: CGFloat(normalized))
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

final class MotionManager {
    private let manager = CMMotionManager()
    private(set) var isActive: Bool = false

    /// Target normalized 2D specular light vector in screen coordinates.
    private(set) var targetLightDir = SIMD2<Float>(-0.58, -0.81)

    /// Real-world gravity vector in UIKit/SwiftUI portrait coordinates (+Y points downward).
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
            guard let self = self, let motion = motion else { return }
            let gx = Float(motion.gravity.x)
            let gy = Float(-motion.gravity.y)
            let rotX = Float(motion.rotationRate.y) * 0.11
            let rotY = Float(motion.rotationRate.x) * 0.11

            self.screenGravity = SIMD2<Float>(gx, gy)

            var vec = SIMD2<Float>(
                gx * 1.35 + rotX - 0.18,
                gy * 1.15 + rotY - 0.45
            )
            let len = simd_length(vec)
            if len > 0.08 {
                vec /= len
            } else {
                vec = SIMD2<Float>(-0.58, -0.81)
            }
            self.targetLightDir = vec
        }
    }

    func stop() {
        guard isActive else { return }
        manager.stopDeviceMotionUpdates()
        isActive = false
        targetLightDir = SIMD2<Float>(-0.58, -0.81)
        screenGravity = SIMD2<Float>(0.0, 1.0)
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
