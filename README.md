# LiquidGlass 3.1 — 120fps ProMotion + iPhone 18 Pro OLED Black-Hole Island & Global Live Activity

專為 **iPhone 18 Pro（iOS 27 / 120Hz ProMotion / 窄版實體動態島挖孔）** 最佳化的液態玻璃實驗室，完整相容 GitHub Actions 雲端編譯與免費 Apple ID 側載（Impactor，零 App Groups 依賴）。

## 本次核心升級與修復

1. **iPhone 18 Pro 雙層動態島架構**：
   - **App 前景（OLED `#000000` 純黑硬體黑洞融合）**：移除所有假動態島彩框與遮擋文字，預設校準為 `88×32 pt`、距頂部 `12 pt`（工坊內附像素級微調滑桿），閒置時與實體挖孔完全隱形合一；水滴靠近時伸出純黑液態觸角吸入，點擊或向下輕拉即可吐出水滴並激發折射水波。
   - **離開 App（全局系統原生動態島 `ActivityKit`）**：滑回桌面、切換其他 App 或鎖定畫面時，自動接手系統動態島顯示即時狀態與 `LiveActivityIntent` 互動按鈕。
2. **底部導覽列鎖死水平單軸軌道 ＋ 修正 Z-Index 層級**：
   - 選取水滴膠囊鎖死於 Dock 垂直中心線（忽略垂直位移），並嚴格按 `Dock 玻璃底板` → `左右滑動折射水滴膠囊` → `導覽圖示與文字` 排列且裁切貼齊不溢出。
3. **強化稜鏡彩虹色散 ＋ 自動連動 Metal 光學引擎**：
   - 放大倒角區 R / G / B 三通道折射分離度並加入隨角度變化的光譜稜鏡邊緣光（`0.05 ~ 0.25` 區間銳利顯色）；拉動光學滑桿時自動切換至自訂 Metal 光學引擎並清除白球遮罩異常。
4. **零 SwiftUI 狀態干擾、鎖定 120fps（`< 8.33ms`）**：
   - 將水滴拖曳、雙指縮放與挖孔觸控移入原生 `InteractiveMTKView`，`MTKViewDelegate.draw(in:)` 每幀零 `@State` 寫入，並移除巢狀 `GlassEffectContainer` 頻寬衝突。
