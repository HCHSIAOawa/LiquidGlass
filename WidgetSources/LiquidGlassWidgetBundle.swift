import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

@main
struct LiquidGlassWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiquidGlassLiveActivityWidget()
    }
}

struct LiquidGlassLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiquidGlassActivityAttributes.self) { context in
            LockScreenPomodoroBannerView(state: context.state)
                .activityBackgroundTint(Color(red: 0.04, green: 0.08, blue: 0.16).opacity(0.84))
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(URL(string: "liquidglass://pomodoro?source=banner"))
        } dynamicIsland: { context in
            let accent = Self.accentColor(isBreak: context.state.isBreakMode)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 7) {
                        MiniHourglassProgressRing(state: context.state, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.isBreakMode ? "晨曦休息" : "液態專注")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white)
                            Text(context.state.isRunning ? "計時進行中" : "已暫停")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    PomodoroCountdownTextView(
                        state: context.state,
                        fontSize: 22,
                        weight: .black,
                        color: accent
                    )
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.completedSessions > 0 {
                        Text("已完成 \(context.state.completedSessions) 個液態番茄鐘 · \(context.state.engineName)")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Button(intent: SwitchPomodoroModeIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: context.state.isBreakMode ? "hourglass" : "leaf.fill")
                                Text(context.state.isBreakMode ? "切至專注" : "切至休息")
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7.5)
                            .background(Color.white.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(intent: TogglePomodoroTimerIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: context.state.isRunning ? "pause.fill" : "play.fill")
                                Text(context.state.isRunning ? "暫停" : "繼續")
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.14))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7.5)
                            .background(accent, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(intent: ResetPomodoroTimerIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("重設")
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7.5)
                            .background(Color.white.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    MiniHourglassProgressRing(state: context.state, size: 20)
                    Text(context.state.modeTitle)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
            } compactTrailing: {
                PomodoroCountdownTextView(
                    state: context.state,
                    fontSize: 12.5,
                    weight: .bold,
                    color: accent
                )
                .frame(minWidth: 42, alignment: .trailing)
            } minimal: {
                MiniHourglassProgressRing(state: context.state, size: 20)
            }
            .widgetURL(URL(string: "liquidglass://pomodoro?source=dynamicIsland"))
            .keylineTint(accent)
        }
    }

    static func accentColor(isBreak: Bool) -> Color {
        isBreak
            ? Color(red: 0.204, green: 0.827, blue: 0.600) // #34D399 Emerald Dawn
            : Color(red: 0.220, green: 0.741, blue: 0.973) // #38BDF8 Sky Aurora
    }
}

// MARK: - Zero-Battery System Native Countdown Text (Uses Text(timerInterval:countsDown:))

private struct PomodoroCountdownTextView: View {
    let state: LiquidGlassActivityAttributes.ContentState
    let fontSize: CGFloat
    let weight: Font.Weight
    let color: Color

    var body: some View {
        if state.isRunning,
           let start = state.startDate,
           let end = state.endDate,
           end > start {
            Text(timerInterval: start...end, countsDown: true, showsHours: false)
                .font(.system(size: fontSize, weight: weight, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(color)
        } else {
            Text(Self.formatMMSS(state.remainingSeconds))
                .font(.system(size: fontSize, weight: weight, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(color.opacity(0.88))
        }
    }

    static func formatMMSS(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Mini Liquid Hourglass Progress Ring

private struct MiniHourglassProgressRing: View {
    let state: LiquidGlassActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        let accent = LiquidGlassLiveActivityWidget.accentColor(isBreak: state.isBreakMode)
        let total = Double(max(1, state.totalSeconds))
        let staticProgress = min(max(Double(state.remainingSeconds) / total, 0.0), 1.0)

        ZStack {
            if state.isRunning,
               let start = state.startDate,
               let end = state.endDate,
               end > start {
                ProgressView(timerInterval: start...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: state.isBreakMode ? "leaf.fill" : "hourglass")
                        .font(.system(size: size * 0.44, weight: .bold))
                        .foregroundStyle(accent)
                }
                .progressViewStyle(.circular)
                .tint(accent)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2.2)
                Circle()
                    .trim(from: 0.0, to: staticProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: state.isBreakMode ? "leaf.fill" : "hourglass")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Lock Screen Live Activity Pomodoro Banner

private struct LockScreenPomodoroBannerView: View {
    let state: LiquidGlassActivityAttributes.ContentState

    var body: some View {
        let accent = LiquidGlassLiveActivityWidget.accentColor(isBreak: state.isBreakMode)

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MiniHourglassProgressRing(state: state, size: 42)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(state.isBreakMode ? "晨曦休息沙漏" : "液態專注沙漏")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)

                        Text(state.engineName)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.14))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(accent, in: Capsule())
                    }

                    Text(state.isRunning ? "雙腔體流體滴落中 · 已完成 \(state.completedSessions) 回合" : "計時暫停 · 點擊下方按鈕繼續或切換")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer()

                PomodoroCountdownTextView(
                    state: state,
                    fontSize: 26,
                    weight: .black,
                    color: accent
                )
            }

            HStack(spacing: 8) {
                Button(intent: SwitchPomodoroModeIntent()) {
                    Label(state.isBreakMode ? "專注 25m" : "休息 5m", systemImage: state.isBreakMode ? "hourglass" : "leaf.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(intent: TogglePomodoroTimerIntent()) {
                    Label(state.isRunning ? "暫停沙漏" : "繼續計時", systemImage: state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.08, blue: 0.14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(intent: ResetPomodoroTimerIntent()) {
                    Label("重設", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}
