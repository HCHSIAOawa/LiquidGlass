import SwiftUI
import simd

// MARK: - Shared GPU Uniforms (100% 16-Byte SIMD4 Aligned with Shaders.metal)

/// Global scene uniforms passed to `liquidGlassFragment` at `[[buffer(0)]]`.
/// Uses exclusively `SIMD4<Float>` (`float4` in Metal) to guarantee identical 80-byte ABI layout.
struct SceneUniforms {
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
}

/// Per-element liquid glass descriptor passed at `[[buffer(1)]]`.
/// Uses exclusively `SIMD4<Float>` (`float4` in Metal) to guarantee identical 64-byte stride.
struct GlassElementUniform {
    /// x: center.x (pt), y: center.y (pt), z: halfSize.x (pt), w: halfSize.y (pt)
    var centerAndHalfSize: SIMD4<Float> = .zero
    /// x: cornerRadius (pt), y: stretchAngle (rad), z: stretchFactor (>=1), w: rimBoost
    var shapeAndTransform: SIMD4<Float> = .zero
    /// x: opacity (0..1), y: refractionScale, z: frostBoost, w: shadowElevation
    var styleParams: SIMD4<Float> = .zero
    /// xyz: accentRGB, w: accentStrength (0..1)
    var tintOverride: SIMD4<Float> = .zero
}

// MARK: - Presets & Domain Models

enum WallpaperPreset: Int, CaseIterable, Identifiable {
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

enum GlassTintMode: Int, CaseIterable, Identifiable {
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

    /// Adaptive high-contrast foreground color for text and SF Symbols over glass cards.
    func primaryTextColor(over wallpaper: WallpaperPreset) -> Color {
        switch self {
        case .light:
            return wallpaper.isBrightBackground
                ? Color(red: 0.08, green: 0.11, blue: 0.18)
                : Color(red: 0.09, green: 0.12, blue: 0.20)
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
}

enum LensShapeMode: Int, CaseIterable, Identifiable {
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
        case .circle: return SIMD2<Float>(94.0, 94.0)
        case .pill: return SIMD2<Float>(144.0, 64.0)
        case .squircle: return SIMD2<Float>(104.0, 104.0)
        }
    }

    var baseCornerRadius: Float {
        switch self {
        case .circle: return 94.0
        case .pill: return 64.0
        case .squircle: return 32.0
        }
    }

    func next() -> LensShapeMode {
        let all = Self.allCases
        let idx = (rawValue + 1) % all.count
        return all[idx]
    }
}

struct MusicTrack: Identifiable {
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
