import Foundation
import ActivityKit

// MARK: - ActivityKit Attributes (Zero App Groups — Free Apple ID / Impactor Sideload Safe)

struct LiquidGlassActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        var modeTitle: String
        var isBreakMode: Bool
        var isRunning: Bool
        var totalSeconds: Int
        var remainingSeconds: Int
        var startDate: Date?
        var endDate: Date?
        var engineName: String
        var completedSessions: Int
    }

    var sessionTitle: String
}

extension Notification.Name {
    static let liquidGlassIntentCommand = Notification.Name("com.custom.liquidglass.intentCommand")
}

enum LiquidGlassIntentCommandKey {
    static let lastAction = "liquidglass.lastIntentAction"
    static let lastActionTimestamp = "liquidglass.lastIntentTimestamp"
    static let lastIsRunning = "liquidglass.lastIsRunning"
    static let lastIsBreakMode = "liquidglass.lastIsBreakMode"
    static let lastRemainingSeconds = "liquidglass.lastRemainingSeconds"
    static let lastTotalSeconds = "liquidglass.lastTotalSeconds"
}
