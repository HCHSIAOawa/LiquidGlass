import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var controller = GlassSceneController()
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        GeometryReader { safeGeo in
            let safeTop = max(safeGeo.safeAreaInsets.top, 20)
            let safeBottom = max(safeGeo.safeAreaInsets.bottom, 16)

            GeometryReader { fullGeo in
                let size = fullGeo.size
                let cardWidth = min(size.width - 32, 344)
                let dockWidth = min(size.width - 32, 348)
                let drawerWidth = min(size.width - 24, 366)

                ZStack(alignment: .topLeading) {
                    // 1. Single-Pass 120Hz Pure Metal GPU Pipeline (Wallpapers + Multi-Glass Optics)
                    MetalLiquidGlassView(controller: controller)
                        .frame(width: size.width, height: size.height)

                    // 2. Two-Finger Pinch Gesture Canvas Layer (Allows effortless pinch anywhere)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if controller.showSettingsDrawer {
                                HapticsManager.shared.tapLight()
                                controller.showSettingsDrawer = false
                            }
                        }
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    controller.updateLensPinch(magnification: value.magnification)
                                }
                                .onEnded { _ in
                                    controller.endLensPinch()
                                }
                        )

                    // 3. Dynamic Music Player Card Overlay (Aligned 1:1 with Metal Element 1)
                    if controller.musicReveal > 0.005 {
                        let mScale = 0.84 + 0.16 * controller.musicReveal
                        MusicPlayerCardOverlay(controller: controller, cardWidth: cardWidth)
                            .scaleEffect(mScale)
                            .opacity(Double(min(1.0, max(0.0, controller.musicReveal))))
                            .position(controller.musicCardCenter)
                            .allowsHitTesting(controller.showMusicCard)
                    }

                    // 4. Mini Control Center Overlay (Aligned 1:1 with Metal Element 2)
                    if controller.controlReveal > 0.005 {
                        let cScale = 0.84 + 0.16 * controller.controlReveal
                        MiniControlCenterOverlay(controller: controller, cardWidth: cardWidth)
                            .scaleEffect(cScale)
                            .opacity(Double(min(1.0, max(0.0, controller.controlReveal))))
                            .position(controller.controlCardCenter)
                            .allowsHitTesting(controller.showControlCenter)
                    }

                    // 5. Main Hero Liquid Lens Interactive Target (Aligned 1:1 with Metal Element 3)
                    HeroLensHitTarget(controller: controller)

                    // 6. Collapsible Studio Control Drawer (Aligned 1:1 with Metal Element 4)
                    if controller.drawerReveal > 0.005 {
                        let dScale = 0.92 + 0.08 * controller.drawerReveal
                        let drawerH: CGFloat = 352
                        let drawerBaseY = size.height - safeBottom - 82 - drawerH * 0.5
                        let slideOffset = (1.0 - min(1.0, controller.drawerReveal)) * 44

                        StudioDrawerOverlay(
                            controller: controller,
                            selectedPhotoItem: $selectedPhotoItem,
                            drawerWidth: drawerWidth
                        )
                        .scaleEffect(dScale)
                        .opacity(Double(min(1.0, max(0.0, controller.drawerReveal))))
                        .position(x: size.width * 0.5, y: drawerBaseY + slideOffset)
                        .allowsHitTesting(controller.showSettingsDrawer)
                    }

                    // 7. Bottom Floating Liquid Dock (Aligned 1:1 with Metal Element 0)
                    FloatingLiquidDockOverlay(
                        controller: controller,
                        selectedPhotoItem: $selectedPhotoItem,
                        dockWidth: dockWidth
                    )
                    .position(x: size.width * 0.5, y: size.height - safeBottom - 36)

                    // 8. Safe-Area Top Status HUD (Below Dynamic Island)
                    TopStatusHUD(controller: controller)
                        .padding(.horizontal, 16)
                        .padding(.top, safeTop + 6)
                }
                .coordinateSpace(name: "screen")
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

// MARK: - Isolated Hero Lens Leaf View (Prevents 120Hz Physics From Invalidating Sibling Cards)

private struct HeroLensHitTarget: View {
    let controller: GlassSceneController

    var body: some View {
        let lensW = max(44, controller.lensHalfSize.width * 2)
        let lensH = max(44, controller.lensHalfSize.height * 2)

        ZStack {
            RoundedRectangle(cornerRadius: controller.lensCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .frame(width: lensW, height: lensH)
                .contentShape(RoundedRectangle(cornerRadius: controller.lensCornerRadius, style: .continuous))
                .onTapGesture(count: 2) {
                    controller.cycleLensShape()
                }
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named("screen"))
                        .onChanged { value in
                            controller.updateLensDrag(
                                translation: value.translation,
                                velocity: value.velocity,
                                location: value.location
                            )
                        }
                        .onEnded { value in
                            controller.endLensDrag(velocity: value.velocity)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            controller.updateLensPinch(magnification: value.magnification)
                        }
                        .onEnded { _ in
                            controller.endLensPinch()
                        }
                )

            if controller.showGestureHint {
                Text("拖曳彈跳 · 雙指縮放 · 雙擊變形")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.38), in: Capsule())
                    .offset(y: lensH * 0.5 + 22)
                    .allowsHitTesting(false)
            }
        }
        .position(controller.lensPosition)
    }
}
