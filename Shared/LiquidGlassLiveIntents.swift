import Foundation
import AppIntents
import ActivityKit

// MARK: - Interactive Pomodoro Dynamic Island Intents (Zero App Groups — Sideload Safe)

struct TogglePomodoroTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "暫停或繼續液態沙漏"
    static let description = IntentDescription("直接從系統動態島暫停或繼續番茄鐘倒數計時。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date()
        var nextRunning = false
        var snapshotRemaining = 1500
        var snapshotTotal = 1500

        for activity in Activity<LiquidGlassActivityAttributes>.activities {
            var updated = activity.content.state
            snapshotTotal = max(60, updated.totalSeconds)

            if updated.isRunning {
                // Pause and freeze exact remaining seconds
                let leftSec: Int
                if let end = updated.endDate {
                    leftSec = max(0, Int(end.timeIntervalSince(now).rounded()))
                } else {
                    leftSec = max(0, updated.remainingSeconds)
                }
                updated.isRunning = false
                updated.remainingSeconds = leftSec > 0 ? leftSec : snapshotTotal
                updated.startDate = nil
                updated.endDate = nil
            } else {
                // Resume countdown using native system timerInterval range
                let resumeSec = updated.remainingSeconds > 0 ? updated.remainingSeconds : snapshotTotal
                let end = now.addingTimeInterval(Double(resumeSec))
                let start = end.addingTimeInterval(-Double(max(resumeSec, snapshotTotal)))
                updated.isRunning = true
                updated.remainingSeconds = resumeSec
                updated.startDate = start
                updated.endDate = end
            }

            nextRunning = updated.isRunning
            snapshotRemaining = updated.remainingSeconds
            await activity.update(ActivityContent(state: updated, staleDate: updated.endDate))
        }

        UserDefaults.standard.set("togglePomodoro", forKey: LiquidGlassIntentCommandKey.lastAction)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: LiquidGlassIntentCommandKey.lastActionTimestamp)
        UserDefaults.standard.set(nextRunning, forKey: LiquidGlassIntentCommandKey.lastIsRunning)
        UserDefaults.standard.set(snapshotRemaining, forKey: LiquidGlassIntentCommandKey.lastRemainingSeconds)

        NotificationCenter.default.post(
            name: .liquidGlassIntentCommand,
            object: nil,
            userInfo: [
                "action": "togglePomodoro",
                "isRunning": nextRunning,
                "remainingSeconds": snapshotRemaining
            ]
        )
        return .result()
    }
}

struct ResetPomodoroTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "重設液態沙漏番茄鐘"
    static let description = IntentDescription("將系統動態島的番茄鐘重設回完整時間。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date()
        var resetSeconds = 1500

        for activity in Activity<LiquidGlassActivityAttributes>.activities {
            var updated = activity.content.state
            let fullSec = max(60, updated.totalSeconds)
            updated.isRunning = false
            updated.remainingSeconds = fullSec
            updated.startDate = nil
            updated.endDate = nil
            resetSeconds = fullSec
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }

        UserDefaults.standard.set("resetPomodoro", forKey: LiquidGlassIntentCommandKey.lastAction)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: LiquidGlassIntentCommandKey.lastActionTimestamp)
        UserDefaults.standard.set(false, forKey: LiquidGlassIntentCommandKey.lastIsRunning)
        UserDefaults.standard.set(resetSeconds, forKey: LiquidGlassIntentCommandKey.lastRemainingSeconds)

        NotificationCenter.default.post(
            name: .liquidGlassIntentCommand,
            object: nil,
            userInfo: ["action": "resetPomodoro"]
        )
        return .result()
    }
}

struct SwitchPomodoroModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "切換專注或休息模式"
    static let description = IntentDescription("在動態島直接切換 25 分鐘專注與 5 分鐘休息模式。")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date()
        var nextBreak = false
        var nextTotal = 1500

        for activity in Activity<LiquidGlassActivityAttributes>.activities {
            var updated = activity.content.state
            updated.isBreakMode.toggle()
            updated.modeTitle = updated.isBreakMode ? "休息" : "專注"
            updated.totalSeconds = updated.isBreakMode ? (5 * 60) : (25 * 60)
            updated.remainingSeconds = updated.totalSeconds
            updated.isRunning = false
            updated.startDate = nil
            updated.endDate = nil
            nextBreak = updated.isBreakMode
            nextTotal = updated.totalSeconds
            await activity.update(ActivityContent(state: updated, staleDate: nil))
        }

        UserDefaults.standard.set("switchPomodoroMode", forKey: LiquidGlassIntentCommandKey.lastAction)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: LiquidGlassIntentCommandKey.lastActionTimestamp)
        UserDefaults.standard.set(nextBreak, forKey: LiquidGlassIntentCommandKey.lastIsBreakMode)
        UserDefaults.standard.set(false, forKey: LiquidGlassIntentCommandKey.lastIsRunning)
        UserDefaults.standard.set(nextTotal, forKey: LiquidGlassIntentCommandKey.lastTotalSeconds)
        UserDefaults.standard.set(nextTotal, forKey: LiquidGlassIntentCommandKey.lastRemainingSeconds)

        NotificationCenter.default.post(
            name: .liquidGlassIntentCommand,
            object: nil,
            userInfo: [
                "action": "switchPomodoroMode",
                "isBreakMode": nextBreak
            ]
        )
        return .result()
    }
}
