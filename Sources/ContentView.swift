import SwiftUI
import PhotosUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = GlassSceneController()
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        GeometryReader { safeGeo in
            let safeTop = max(safeGeo.safeAreaInsets.top, 20)
            let safeBottom = max(safeGeo.safeAreaInsets.bottom, 16)

            GeometryReader { fullGeo in
                let size = fullGeo.size
                let cardWidth = min(size.width - 32, 346)
                let labPillWidth = min(size.width - 32, 336)
                let drawerWidth = min(size.width - 24, 366)
                let dockCenterY = controller.dockCenterY(for: size.height, safeBottom: safeBottom)

                ZStack(alignment: .topLeading) {
                    // 1. Full-Screen 120Hz InteractiveMTKView (Pure GPU Rendering + Direct UIKit Droplet/Cutout Touches)
                    MetalLiquidGlassView(controller: controller)
                        .frame(width: size.width, height: size.height)

                    // 2. Zone 0: Dual-Droplet Fusion Lab Pill
                    if controller.isLensLabBarVisible {
                        LensFusionLabPillOverlay(controller: controller, pillWidth: labPillWidth)
                            .position(x: size.width * 0.5, y: safeTop + 78)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 3. Zone 1: Dynamic Music & Synth Beat Card
                    if controller.isMusicVisible {
                        MusicPlayerCardOverlay(
                            controller: controller,
                            cardWidth: cardWidth,
                            baseCenter: CGPoint(x: size.width * 0.5, y: safeTop + 152)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 4. Zone 2: Liquid Control Hub Card
                    if controller.isControlVisible {
                        MiniControlCenterOverlay(
                            controller: controller,
                            cardWidth: cardWidth,
                            baseCenter: CGPoint(x: size.width * 0.5, y: safeTop + 188)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 5. Zone 3: Spatial Weather & Solar Arc Card
                    if controller.isWeatherVisible {
                        WeatherSolarCardOverlay(
                            controller: controller,
                            cardWidth: cardWidth,
                            baseCenter: CGPoint(x: size.width * 0.5, y: safeTop + 168)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 6. Zone 4: Optical & Hardware Cutout Calibration Studio Drawer
                    if controller.isStudioVisible {
                        let drawerH: CGFloat = 388
                        let drawerBaseY = size.height - safeBottom - 80 - drawerH * 0.5

                        StudioDrawerOverlay(
                            controller: controller,
                            selectedPhotoItem: $selectedPhotoItem,
                            drawerWidth: drawerWidth
                        )
                        .position(x: size.width * 0.5, y: drawerBaseY)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // 7. Strict Single-Axis Horizontal Liquid Dock
                    NativeLiquidDockOverlay(
                        controller: controller,
                        screenWidth: size.width
                    )
                    .position(x: size.width * 0.5, y: dockCenterY)

                    // 8. Clean Top HUD Below Safe Area (Never Obstructs Time, Battery, or Hardware Cutout!)
                    TopStatusHUD(
                        controller: controller,
                        selectedPhotoItem: $selectedPhotoItem
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, safeTop + 6)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: controller.selectedTab)
                .frame(width: size.width, height: size.height)
                .onAppear {
                    controller.updateGeometry(size: size, safeTop: safeTop, safeBottom: safeBottom)
                }
                .onChange(of: size) { _, newSize in
                    controller.updateGeometry(size: newSize, safeTop: safeTop, safeBottom: safeBottom)
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                // Immediately push latest state to Global System Dynamic Island as user leaves app!
                controller.syncLiveActivityNow()
            }
        }
        .onOpenURL { url in
            controller.handleIncomingURL(url)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        controller.applyCustomPhotoData(data)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
    }
}
