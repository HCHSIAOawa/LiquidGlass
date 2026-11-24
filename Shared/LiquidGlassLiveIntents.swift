import Foundation
import AppIntents
import ActivityKit

// MARK: - Interactive Dynamic Island Intents (Executed in Main App Process Without App Groups)

struct ToggleGlassPlaybackIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切換液態音樂播放"
    static var description = IntentDescription("在系統動態島直接播放或暫停音樂波形。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        var nextPlaying = true
        for activity in Activity<LiquidGlassActivityAttributes>.activities {
            var updated = activity.content.state
            updated.isPlaying.toggle()
            nextPlaying = updated.isPlaying
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }

        UserDefaults.standard.set(nextPlaying, forKey: LiquidGlassIntentCommandKey.lastIsPlaying)
        NotificationCenter.default.post(
            name: .liquidGlassIntentCommand,
            object: nil,
            userInfo: ["action": "togglePlay", "isPlaying": nextPlaying]
        )
        return .result()
    }
}

struct CycleGlassWallpaperIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切換液態桌布風格"
    static var description = IntentDescription("在系統動態島一鍵切換極光、彩條、夕陽與格線桌布。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let titles = ["極光", "彩條", "夕陽", "格線紙"]
        var nextIdx = 0

        for activity in Activity<LiquidGlassActivityAttributes>.activities {
            var updated = activity.content.state
            nextIdx = (updated.wallpaperIndex + 1) % titles.count
            updated.wallpaperIndex = nextIdx
            updated.wallpaperTitle = titles[nextIdx]
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }

        UserDefaults.standard.set(nextIdx, forKey: LiquidGlassIntentCommandKey.lastWallpaperIndex)
        NotificationCenter.default.post(
            name: .liquidGlassIntentCommand,
            object: nil,
            userInfo: ["action": "cycleWallpaper", "wallpaperIndex": nextIdx]
        )
        return .result()
    }
}

struct TriggerIslandRippleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "激發動態島液態水波"
    static var description = IntentDescription("從系統動態島發射一次液態玻璃水波脈衝。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        var count = 1
        for activity in Activity<LiquidGlassActivityAttributes>.activities {
            var updated = activity.content.state
            updated.rippleCount += 1
            count = updated.rippleCount
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }

        UserDefaults.standard.set(count, forKey: LiquidGlassIntentCommandKey.lastRippleCount)
        NotificationCenter.default.post(
            name: .liquidGlassIntentCommand,
            object: nil,
            userInfo: ["action": "triggerRipple", "rippleCount": count]
        )
        return .result()
    }
}
