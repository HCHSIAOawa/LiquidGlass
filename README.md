# LiquidGlass — Native 120Hz ProMotion iOS Playground (SwiftUI + MetalKit)

將 Web 版 Liquid Glass Playground 完整重構為純 GPU 單通道渲染（Single-Pass `MTKView`）的 iOS 17+ 原生應用，專為 iPhone 120Hz ProMotion 螢幕最佳化。

## 核心亮點

- **120fps 單通道 MetalKit 管線 (`MTKView`)**：
  - 移除昂貴的 SwiftUI `TimelineView + .blur + .layerEffect` 離屏渲染。
  - 4 款程序化動態桌布（極光、稜鏡彩條、夕陽同心圓、極簡網格紙）直接在 Fragment Shader 即時運算，零離屏模糊開銷。
  - 捲動字體層預先光柵化為 2048×1024 無縫 Mipmap 紋理（`MTLTexture`），於 Shader 內進行 UV 滾動與硬體三線性模糊（Trilinear Mipmap Blur）。
  - 單一 Fragment Pass 同時解算最多 8 塊液態玻璃元件（主透鏡、音樂播放卡、迷你控制中心、光學工作坊面板、底部 Floating Dock）的雙區凸面折射、RGB 色散、磨砂、雙層菲涅耳高光與焦散陰影。
  - `project.yml` 寫入 `CADisableMinimumFrameDurationOnPhone: true` 完整解鎖 iPhone 120Hz 幀率，並內建即時 FPS / 幀時間監控膠囊。
- **液態物理、感測器與觸覺互動**：
  - 不可壓縮流體拉伸/壓扁（Velocity Squash & Stretch）、慣性滑行與螢幕邊界彈性撞擊形變。
  - 支援雙指捏合縮放鏡片、雙擊絲滑變形（圓形 ↔ 膠囊 ↔ 圓角方塊）。
  - `CoreMotion` 陀螺儀手腕傾斜即時驅動全場玻璃邊緣反光（Specular Rim）流動。
  - `PhotosPicker` 原生匯入相簿照片作為折射背景，搭配清透 / 淺霧 / 深邃 3 種玻璃材質色調與細膩 `UIImpactFeedbackGenerator` 觸覺回饋。

## 專案結構

- `project.yml`：XcodeGen 設定（自動產出含 `CADisableMinimumFrameDurationOnPhone: true` 的 `Info.plist`）
- `.github/workflows/build.yml`：GitHub Actions（`macos-15`）雲端自動編譯未簽章 `LiquidGlass.ipa`
- `Sources/LiquidGlassApp.swift`：App 進入點
- `Sources/PlaygroundModels.swift`：16-byte `SIMD4<Float>` 對齊的 Swift/Metal 共用 Uniform 結構與資料模型
- `Sources/Shaders.metal`：全螢幕三角形 Vertex Shader 與多元件光學折射 Fragment Shader
- `Sources/MetalRenderer.swift`：`MTKView` 120Hz 渲染器、無縫字體紋理與自訂相片 Mipmap 生成器
- `Sources/GlassSceneController.swift`：`@Observable` 120Hz 彈簧與碰撞物理引擎
- `Sources/HapticsAndMotion.swift`：`CoreMotion` 陀螺儀光影控制器與動態強度觸覺回饋引擎
- `Sources/GlassCardsView.swift`：動態音樂卡、迷你控制中心、光學面板、Floating Dock 與 120Hz HUD
- `Sources/ContentView.swift`：全畫面座標同步與多點手勢整合層
