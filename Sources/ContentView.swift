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
                    // 1. Full-Screen 120Hz InteractiveMTKView (Pure GPU Hourglass, Droplets & Cutout Fusion)
                    MetalLiquidGlassView(controller: controller)
                        .frame(width: size.width, height: size.height)

                    // 2. Flagship Tab 0: Liquid Hourglass Pomodoro HUD & Zen Minimalist Controls
                    if controller.isFocusTabActive {
                        FocusHourglassOverlay(
                            controller: controller,
                            size: size,
                            safeTop: safeTop,
                            safeBottom: safeBottom
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }

                    // 3. Tab 1: Dual-Droplet Fusion Lab Pill
                    if controller.isLensLabBarVisible {
                        LensFusionLabPillOverlay(controller: controller, pillWidth: labPillWidth)
                            .position(x: size.width * 0.5, y: safeTop + 76)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 4. Tab 2: Dynamic Music & Synth Beat Card
                    if controller.isMusicVisible {
                        MusicPlayerCardOverlay(
                            controller: controller,
                            cardWidth: cardWidth,
                            baseCenter: CGPoint(x: size.width * 0.5, y: safeTop + 150)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 5. Tab 3: Liquid Control Hub Card
                    if controller.isControlVisible {
                        MiniControlCenterOverlay(
                            controller: controller,
                            cardWidth: cardWidth,
                            baseCenter: CGPoint(x: size.width * 0.5, y: safeTop + 188)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    // 6. Tab 4: Optical & Hardware Cutout Calibration Studio Drawer
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

                    // 7. Apple Native Two-Part Single-Axis Bottom Liquid Dock (Fluidly Retreats in Zen Mode!)
                    if !controller.isZenMode {
                        NativeLiquidDockOverlay(
                            controller: controller,
                            screenWidth: size.width
                        )
                        .position(x: size.width * 0.5, y: dockCenterY)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.88).combined(with: .opacity),
                                removal: .scale(scale: 0.86).combined(with: .opacity)
                            )
                        )
                    }

                    // 8. Clean Top Status HUD (Smoothly Retreats in Zen Mode; Never Obstructs Cutout!)
                    if !controller.isZenMode {
                        TopStatusHUD(
                            controller: controller,
                            selectedPhotoItem: $selectedPhotoItem
                        )
                        .padding(.horizontal, 14)
                        .padding(.top, safeTop + 6)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.76), value: controller.selectedTab)
                .animation(.spring(response: 0.42, dampingFraction: 0.78), value: controller.isZenMode)
                .animation(.spring(response: 0.36, dampingFraction: 0.80), value: controller.pomodoroMode)
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
            switch newPhase {
            case .inactive, .background:
                // Immediately hand off accurate countdown timer to System Native Dynamic Island!
                controller.syncLiveActivityNow()
            case .active:
                controller.reconcileFromLiveActivityOnForeground()
            @unknown default:
                break
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
