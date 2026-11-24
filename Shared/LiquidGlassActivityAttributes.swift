import Foundation
import ActivityKit

// MARK: - ActivityKit Attributes (Zero App Groups — Sideload Safe)

struct LiquidGlassActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var engineName: String
        var wallpaperTitle: String
        var wallpaperIndex: Int
        var trackTitle: String
        var trackArtist: String
        var isPlaying: Bool
        var solarHour: Int
        var rippleCount: Int
    }

    var sessionTitle: String
}

extension Notification.Name {
    static let liquidGlassIntentCommand = Notification.Name("com.custom.liquidglass.intentCommand")
}

enum LiquidGlassIntentCommandKey {
    static let lastAction = "liquidglass.lastIntentAction"
    static let lastWallpaperIndex = "liquidglass.lastWallpaperIndex"
    static let lastIsPlaying = "liquidglass.lastIsPlaying"
    static let lastRippleCount = "liquidglass.lastRippleCount"
}
