import SwiftUI
import simd

// MARK: - Velocity-Preserving 120Hz Spring Solvers (Fixed dt = 1/120s, Zero Gesture Discontinuity)

struct Spring1D: Sendable {
    var pos: Float
    var vel: Float

    init(pos: Float = 0.0, vel: Float = 0.0) {
        self.pos = pos
        self.vel = vel
    }

    mutating func step(target: Float, omega: Float, zeta: Float, dt: Float = 1.0 / 120.0) {
        let force = -omega * omega * (pos - target) - 2.0 * zeta * omega * vel
        vel += force * dt
        pos += vel * dt
    }

    mutating func reset(to value: Float, preserveVelocity: Bool = true) {
        pos = value
        if !preserveVelocity {
            vel = 0.0
        }
    }
}

struct Spring2D: Sendable {
    var pos: SIMD2<Float>
    var vel: SIMD2<Float>

    init(pos: SIMD2<Float> = .zero, vel: SIMD2<Float> = .zero) {
        self.pos = pos
        self.vel = vel
    }

    mutating func step(target: SIMD2<Float>, omega: Float, zeta: Float, dt: Float = 1.0 / 120.0) {
        let force = -omega * omega * (pos - target) - 2.0 * zeta * omega * vel
        vel += force * dt
        pos += vel * dt
    }

    mutating func reset(to value: SIMD2<Float>, preserveVelocity: Bool = true) {
        pos = value
        if !preserveVelocity {
            vel = .zero
        }
    }
}

// MARK: - Shared GPU Uniforms (100% 16-Byte SIMD4 Aligned & Sendable)

/// Global scene uniforms passed to `liquidGlassFragment` at `[[buffer(0)]]`.
/// 8 x SIMD4<Float> = 128 bytes exact layout matching `Shaders.metal`.
struct SceneUniforms: Sendable {
    /// x: viewportWidth (pt), y: viewportHeight (pt), z: elapsedTime (s), w: wallpaperMode (0..4)
    var viewportAndTime: SIMD4<Float> = .zero
    /// x: refraction (pt), y: bezel (pt), z: dispersion (0..0.3), w: frost (0..4.0)
    var opticalParams: SIMD4<Float> = .zero
    /// x: lightDir.x, y: lightDir.y, z: tintMode (0=Clear, 1=Light, 2=Dark), w: sceneBrightness
    var lightingParams: SIMD4<Float> = .zero
    /// x: spotlightOrigin.x, y: spotlightOrigin.y, z: spotlightDir.x, w: spotlightStrength (0..1)
    var spotlightParams: SIMD4<Float> = .zero
    /// x: elementCount, y: hasCustomPhoto (0/1), z: photoAspect (w/h), w: textOverlayMix (0..1)
    var layerFlags: SIMD4<Float> = .zero
    /// x: rippleCenter.x (pt), y: rippleCenter.y (pt), z: rippleRadius (pt), w: rippleStrength (0..1)
    var rippleParams: SIMD4<Float> = .zero
    /// x: atmosphereWarmth (-1..1), y: globalRimBoost (1..1.6), z: fusionSmoothness (pt), w: islandHalfHeight (pt)
    var atmosphereParams: SIMD4<Float> = .zero
    /// x: islandCenterX (pt), y: islandCenterY (pt), z: islandHalfWidth (pt), w: islandPullStretch (pt)
    var islandParams: SIMD4<Float> = .zero
}

/// Per-element liquid glass descriptor passed at `[[buffer(1)]]`.
/// 4 x SIMD4<Float> = 64 bytes exact layout matching `Shaders.metal`.
struct GlassElementUniform: Sendable {
    /// x: center.x (pt), y: center.y (pt), z: halfSize.x (pt), w: halfSize.y (pt)
    var centerAndHalfSize: SIMD4<Float> = .zero
    /// x: cornerRadius (pt), y: stretchAngle (rad), z: stretchFactor (>=1), w: rimBoost
    var shapeAndTransform: SIMD4<Float> = .zero
    /// x: opacity (0..1), y: refractionScale, z: frostBoost, w: shadowElevation
    var styleParams: SIMD4<Float> = .zero
    /// xyz: accentRGB, w: accentStrength (-1.0 = Dual-Droplet Fusion leader, -2.0 = Island-magnetic droplet)
    var tintOverride: SIMD4<Float> = .zero
}

/// Dual-chamber Liquid Hourglass + Radial Optical Time Dial uniforms passed at `[[buffer(2)]]`.
/// 8 x SIMD4<Float> = 128 bytes exact layout matching `Shaders.metal`.
struct HourglassUniforms: Sendable {
    /// x: centerX (pt), y: centerY (pt), z: halfWidth (pt), w: halfHeight (pt)
    var centerAndSize: SIMD4<Float> = .zero
    /// x: visibility (0..1), y: flipAngleRad, z: upperFill (0..1), w: lowerFill (0..1)
    var morphAndFill: SIMD4<Float> = .zero
    /// x: pinchPhase (0..1), y: dropLocalY (pt), z: dropRadius (pt), w: filamentThickness (pt)
    var dropletParams: SIMD4<Float> = .zero
    /// x: impactWavePhase (0..1), y: impactStrength (0..1), z: causticBloom (0..1), w: modeBlend (0=Focus, 1=Rest)
    var impactAndAtmosphere: SIMD4<Float> = .zero
    /// x: dialVisibility (0..1), y: dialRadiusPt, z: progressAngleRad (0..2pi), w: dialDragGlow (0..1)
    var dialRingParams: SIMD4<Float> = .zero
    /// x: knobCenterX (pt), y: knobCenterY (pt), z: knobRadiusPt, w: knobTangentAngleRad
    var dialLensParams: SIMD4<Float> = .zero
    /// x: gravityTiltX (-1..1), y: gravityTiltY (-1..1), z: zenBreathGlow (0..1), w: knobStretch (0.8..1.4)
    var gravityAndZen: SIMD4<Float> = .zero
    /// x: streamActive (0..1), y: dropStretch (1..1.5), z: satelliteLocalY (pt), w: satelliteRadius (pt)
    var neckAndStream: SIMD4<Float> = .zero
}

// MARK: - Pomodoro Focus / Break Mode

enum PomodoroMode: Int, CaseIterable, Identifiable, Sendable {
    case focus = 0
    case rest = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .focus: return "專注模式"
        case .rest: return "晨曦休息"
        }
    }

    var shortTitle: String {
        switch self {
        case .focus: return "專注"
        case .rest: return "休息"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: return "深邃極光稜鏡"
        case .rest: return "晨曦暖金森綠"
        }
    }

    var icon: String {
        switch self {
        case .focus: return "hourglass"
        case .rest: return "leaf.fill"
        }
    }

    var defaultMinutes: Int {
        switch self {
        case .focus: return 25
        case .rest: return 5
        }
    }

    var accentColor: Color {
        switch self {
        case .focus: return Color(red: 0.220, green: 0.741, blue: 0.973) // #38BDF8 Sky Aurora
        case .rest: return Color(red: 0.204, green: 0.827, blue: 0.600)  // #34D399 Emerald Dawn
        }
    }

    var secondaryColor: Color {
        switch self {
        case .focus: return Color(red: 0.48, green: 0.52, blue: 1.0)
        case .rest: return Color(red: 0.98, green: 0.75, blue: 0.24)
        }
    }

    func toggled() -> PomodoroMode {
        self == .focus ? .rest : .focus
    }
}

// MARK: - Dual Rendering Engine Mode

enum GlassEngineMode: Int, CaseIterable, Identifiable, Sendable {
    case nativeAppleGlass = 0
    case customMetalOptics = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .nativeAppleGlass: return "iOS 原生玻璃"
        case .customMetalOptics: return "Metal 光學"
        }
    }

    var badgeLabel: String {
        switch self {
        case .nativeAppleGlass: return "iOS 27 原生"
        case .customMetalOptics: return "Metal 120Hz"
        }
    }

    var icon: String {
        switch self {
        case .nativeAppleGlass: return "apple.logo"
        case .customMetalOptics: return "sparkles.tv"
        }
    }

    func toggled() -> GlassEngineMode {
        self == .nativeAppleGlass ? .customMetalOptics : .nativeAppleGlass
    }
}

// MARK: - Apple Native Two-Part Bottom Liquid Glass Dock Tabs
// Left Main Capsule (78% width): 專注, 探索, 音樂, 控制 + 10pt gap + Right Independent Glass Orb: 工坊

enum DockTab: Int, CaseIterable, Identifiable, Sendable {
    case focusHourglass = 0
    case lensLab = 1
    case musicBeat = 2
    case controlHub = 3
    case opticalStudio = 4

    var id: Int { rawValue }

    static var mainCapsuleTabs: [DockTab] {
        [.focusHourglass, .lensLab, .musicBeat, .controlHub]
    }

    var isMainCapsuleTab: Bool {
        self != .opticalStudio
    }

    var title: String {
        switch self {
        case .focusHourglass: return "專注"
        case .lensLab: return "探索"
        case .musicBeat: return "音樂"
        case .controlHub: return "控制"
        case .opticalStudio: return "工坊"
        }
    }

    var icon: String {
        switch self {
        case .focusHourglass: return "hourglass"
        case .lensLab: return "drop.halffull"
        case .musicBeat: return "waveform"
        case .controlHub: return "switch.2"
        case .opticalStudio: return "slider.horizontal.3"
        }
    }

    /// Signature #38BDF8 Bright Sky Blue selected tint at rest
    static let skyBlueAccent = Color(red: 0.2196, green: 0.7412, blue: 0.9725)
}

// MARK: - Presets & Domain Models

enum WallpaperPreset: Int, CaseIterable, Identifiable, Sendable {
    case aurora = 0
    case rainbowStripes = 1
    case sunsetRings = 2
    case minimalGrid = 3
    case customPhoto = 4

    var id: Int { rawValue }

    static var builtInPresets: [WallpaperPreset] {
        [.aurora, .rainbowStripes, .sunsetRings, .minimalGrid]
    }

    var title: String {
        switch self {
        case .aurora: return "極光"
        case .rainbowStripes: return "彩條"
        case .sunsetRings: return "夕陽"
        case .minimalGrid: return "格線紙"
        case .customPhoto: return "相簿"
        }
    }

    var icon: String {
        switch self {
        case .aurora: return "sparkles"
        case .rainbowStripes: return "swatchpalette.fill"
        case .sunsetRings: return "sun.horizon.fill"
        case .minimalGrid: return "squareshape.split.3x3"
        case .customPhoto: return "photo.fill"
        }
    }

    var isBrightBackground: Bool {
        self == .minimalGrid
    }
}

enum GlassTintMode: Int, CaseIterable, Identifiable, Sendable {
    case clear = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .clear: return "清透 Clear"
        case .light: return "淺霧 Light"
        case .dark: return "深邃 Dark"
        }
    }

    var shortTitle: String {
        switch self {
        case .clear: return "清透"
        case .light: return "淺霧"
        case .dark: return "深邃"
        }
    }

    func primaryTextColor(over wallpaper: WallpaperPreset) -> Color {
        switch self {
        case .light:
            return Color(red: 0.08, green: 0.11, blue: 0.18)
        case .clear:
            return wallpaper.isBrightBackground
                ? Color(red: 0.10, green: 0.13, blue: 0.22)
                : Color.white
        case .dark:
            return Color.white
        }
    }

    func secondaryTextColor(over wallpaper: WallpaperPreset) -> Color {
        primaryTextColor(over: wallpaper).opacity(0.68)
    }

    func subtleFillColor(over wallpaper: WallpaperPreset) -> Color {
        switch self {
        case .light:
            return Color.black.opacity(0.09)
        case .clear:
            return wallpaper.isBrightBackground ? Color.black.opacity(0.08) : Color.white.opacity(0.16)
        case .dark:
            return Color.white.opacity(0.14)
        }
    }

    func prominentFillColor(over wallpaper: WallpaperPreset) -> Color {
        switch self {
        case .light:
            return Color.black.opacity(0.16)
        case .clear:
            return wallpaper.isBrightBackground ? Color.black.opacity(0.15) : Color.white.opacity(0.26)
        case .dark:
            return Color.white.opacity(0.24)
        }
    }

    var nativeTintOverlay: Color? {
        switch self {
        case .clear: return nil
        case .light: return Color.white.opacity(0.22)
        case .dark: return Color(red: 0.04, green: 0.07, blue: 0.15).opacity(0.45)
        }
    }
}

enum LensShapeMode: Int, CaseIterable, Identifiable, Sendable {
    case circle = 0
    case pill = 1
    case squircle = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .circle: return "圓形透鏡"
        case .pill: return "膠囊透鏡"
        case .squircle: return "圓角方塊"
        }
    }

    var shortTitle: String {
        switch self {
        case .circle: return "圓形"
        case .pill: return "膠囊"
        case .squircle: return "方塊"
        }
    }

    var icon: String {
        switch self {
        case .circle: return "circle.fill"
        case .pill: return "capsule.fill"
        case .squircle: return "app.fill"
        }
    }

    var baseHalfSize: SIMD2<Float> {
        switch self {
        case .circle: return SIMD2<Float>(84.0, 84.0)
        case .pill: return SIMD2<Float>(132.0, 58.0)
        case .squircle: return SIMD2<Float>(92.0, 92.0)
        }
    }

    var baseCornerRadius: Float {
        switch self {
        case .circle: return 84.0
        case .pill: return 58.0
        case .squircle: return 28.0
        }
    }

    func next() -> LensShapeMode {
        let all = Self.allCases
        let idx = (rawValue + 1) % all.count
        return all[idx]
    }
}

struct BeatPadItem: Identifiable, Sendable {
    let id: Int
    let name: String
    let icon: String
    let color: Color

    static let pads: [BeatPadItem] = [
        BeatPadItem(id: 0, name: "Sub Wave", icon: "dot.radiowaves.left.and.right", color: Color(red: 0.22, green: 0.88, blue: 1.0)),
        BeatPadItem(id: 1, name: "Prism Arp", icon: "sparkles", color: Color(red: 1.0, green: 0.36, blue: 0.66)),
        BeatPadItem(id: 2, name: "Glass Bell", icon: "bell.and.waves.left.and.right.fill", color: Color(red: 0.56, green: 0.44, blue: 1.0)),
        BeatPadItem(id: 3, name: "Solar Kick", icon: "waveform.path.ecg", color: Color(red: 1.0, green: 0.68, blue: 0.24))
    ]
}

struct MusicTrack: Identifiable, Sendable {
    let id: Int
    let title: String
    let artist: String
    let duration: Double
    let accentPrimary: Color
    let accentSecondary: Color
    let shaderTint: SIMD3<Float>

    static let catalog: [MusicTrack] = [
        MusicTrack(
            id: 0,
            title: "Prism Refraction",
            artist: "Chromatic Glass · Spatial",
            duration: 214,
            accentPrimary: Color(red: 0.28, green: 0.86, blue: 1.0),
            accentSecondary: Color(red: 0.56, green: 0.36, blue: 1.0),
            shaderTint: SIMD3<Float>(0.24, 0.78, 1.0)
        ),
        MusicTrack(
            id: 1,
            title: "Aurora Velocity",
            artist: "ProMotion 120Hz Sessions",
            duration: 188,
            accentPrimary: Color(red: 1.0, green: 0.30, blue: 0.58),
            accentSecondary: Color(red: 0.35, green: 0.28, blue: 0.96),
            shaderTint: SIMD3<Float>(1.0, 0.32, 0.62)
        ),
        MusicTrack(
            id: 2,
            title: "Solar Meniscus",
            artist: "Horizon Optics",
            duration: 242,
            accentPrimary: Color(red: 1.0, green: 0.62, blue: 0.22),
            accentSecondary: Color(red: 0.96, green: 0.24, blue: 0.44),
            shaderTint: SIMD3<Float>(1.0, 0.58, 0.24)
        ),
        MusicTrack(
            id: 3,
            title: "Quartz Resonance",
            artist: "Minimal Lab · Lossless",
            duration: 196,
            accentPrimary: Color(red: 0.20, green: 0.92, blue: 0.72),
            accentSecondary: Color(red: 0.14, green: 0.56, blue: 0.95),
            shaderTint: SIMD3<Float>(0.20, 0.88, 0.70)
        )
    ]
}
