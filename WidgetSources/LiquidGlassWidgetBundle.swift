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
            LockScreenGlassBannerView(state: context.state)
                .activityBackgroundTint(Color(red: 0.05, green: 0.09, blue: 0.18).opacity(0.78))
                .activitySystemActionForegroundColor(Color.white)
                .widgetURL(URL(string: "liquidglass://island?source=banner"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.halffull")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text(context.state.engineName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 5) {
                        Image(systemName: context.state.solarHour < 6 || context.state.solarHour > 19 ? "moon.stars.fill" : "sun.max.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.30))
                        Text(String(format: "%02d:00", context.state.solarHour))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.88))
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("\(context.state.trackTitle) · \(context.state.wallpaperTitle)")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Text("\(context.state.trackArtist) · 水波 \(context.state.rippleCount)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Button(intent: CycleGlassWallpaperIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text(context.state.wallpaperTitle)
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(intent: ToggleGlassPlaybackIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                Text(context.state.isPlaying ? "暫停" : "播放")
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.cyan, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(intent: TriggerIslandRippleIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "water.waves")
                                Text("水波")
                            }
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text(context.state.wallpaperTitle)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
            } compactTrailing: {
                HStack(spacing: 4) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(context.state.isPlaying ? Color(red: 0.35, green: 0.96, blue: 0.72) : Color.white.opacity(0.75))
                    Text("\(context.state.rippleCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cyan)
                }
            } minimal: {
                Image(systemName: "drop.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color(red: 0.58, green: 0.44, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .widgetURL(URL(string: "liquidglass://island?source=dynamicIsland"))
            .keylineTint(Color.cyan)
        }
    }
}

private struct LockScreenGlassBannerView: View {
    let state: LiquidGlassActivityAttributes.ContentState

    var body: some View {
        let hourText = String(format: "%02d:00", state.solarHour)

        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.85), Color(red: 0.45, green: 0.36, blue: 0.98)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "drop.halffull")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("LiquidGlass")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                        Text(state.engineName)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.cyan, in: Capsule())
                    }
                    Text("\(state.trackTitle) · 桌布：\(state.wallpaperTitle) · \(hourText)")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button(intent: CycleGlassWallpaperIntent()) {
                    Label(state.wallpaperTitle, systemImage: "sparkles")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(intent: ToggleGlassPlaybackIntent()) {
                    Label(state.isPlaying ? "暫停波形" : "播放波形", systemImage: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.cyan, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(intent: TriggerIslandRippleIntent()) {
                    Label("水波 \(state.rippleCount)", systemImage: "water.waves")
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
