# LiquidGlass 3.0 — iOS 27 Native Liquid Glass + Metal 120Hz Hybrid Engine & Dynamic Island

專為 **iPhone 18 Pro (iOS 27 / 120Hz ProMotion)** 打造的雙引擎液態玻璃互動實驗室，完整相容 GitHub Actions 雲端編譯未簽章 IPA 與免費 Apple ID 側載（Impactor，零 App Groups 依賴）。

## 核心特色

1. **雙引擎即時切換架構（`iOS 27 原生玻璃 ↔ Metal 120Hz 自訂光學`）**：
   - 原生模式採用 `GlassEffectContainer(spacing:)`、`.glassEffect(.clear/.regular.interactive())`、`glassEffectID(_:in:)`、`glassEffectUnion(id:namespace:)` 與 `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`，由 iOS 系統合成器即時折射底層 120fps Metal 極光、水波與相簿桌布。
   - 一鍵切換自訂 Metal 光學引擎，即時對比雙區凸透鏡折射、RGB 色散與磨砂參數。
2. **iPhone 18 Pro 動態島雙層互動**：
   - **App 前景硬體動態島融合**：將水滴拖近動態島即可觸發磁吸 Smooth-Min 拉絲吸入、從動態島向下拉出吐出水滴或液態卡片、點擊動態島一鍵液態收納/噴發所有視窗，並搭載 `CHHapticEngine` 專屬「吸入、拉絲斷裂、彈性撞牆」三種觸覺波形。
   - **系統級動態島即時動態 (`ActivityKit` + `LiveActivityIntent`)**：內建 `LiquidGlassWidget.appex` 支援 Compact / Minimal / Expanded / 鎖定畫面橫幅，即使滑回桌面也能直接在系統動態島切換桌布、控制播放與發射液態水波。
