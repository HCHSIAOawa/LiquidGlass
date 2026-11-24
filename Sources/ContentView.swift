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
                let cardWidth = min(size.width - 32, 346)
                let labPillWidth = min(size.width - 32, 336)
                let drawerWidth = min(size.width - 24, 366)
                let dockCenterY = controller.dockCenterY(for: size.height, safeBottom: safeBottom)

                ZStack(alignment: .topLeading) {
                    // 1. Single-Pass 120Hz Pure Metal GPU Pipeline
                    MetalLiquidGlassView(controller: controller)
                        .frame(width: size.width, height: size.height)

                    // 2. Interactive Canvas Layer (Tap for Water Shockwave Ripple + Two-Finger Pinch)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture(coordinateSpace: .named("screen"))
                                .onEnded { event in
                                    controller.triggerRipple(at: event.location, strength: 0.78)
                                    HapticsManager.shared.tapSoft(intensity: 0.40)
                                    if controller.selectedTab == .opticalStudio {
                                        controller.selectedTab = .lensLab
                                    }
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

                    // 3. Zone 0: Dual-Droplet Liquid Fusion Lab Pill Bar
                    if controller.labBarReveal > 0.005 {
                        let lScale = 0.88 + 0.12 * controller.labBarReveal
                        LensFusionLabPillOverlay(controller: controller, pillWidth: labPillWidth)
                            .scaleEffect(lScale)
                            .opacity(Double(min(1.0, max(0.0, controller.labBarReveal))))
                            .position(x: size.width * 0.5, y: safeTop + 74)
                            .allowsHitTesting(controller.isLensLabBarVisible)
                    }

                    // 4. Zone 1: Dynamic Music & Synth Beat Card
                    if controller.musicReveal > 0.005 {
                        let mScale = 0.84 + 0.16 * controller.musicReveal
                        MusicPlayerCardOverlay(controller: controller, cardWidth: cardWidth)
                            .scaleEffect(mScale)
                            .opacity(Double(min(1.0, max(0.0, controller.musicReveal))))
                            .position(controller.musicCardCenter)
                            .allowsHitTesting(controller.isMusicVisible)
                    }

                    // 5. Zone 2: Liquid Control Hub Card
                    if controller.controlReveal > 0.005 {
                        let cScale = 0.84 + 0.16 * controller.controlReveal
                        MiniControlCenterOverlay(controller: controller, cardWidth: cardWidth)
                            .scaleEffect(cScale)
                            .opacity(Double(min(1.0, max(0.0, controller.controlReveal))))
                            .position(controller.controlCardCenter)
                            .allowsHitTesting(controller.isControlVisible)
                    }

                    // 6. Zone 3: Spatial Weather & 24h Solar Arc Card
                    if controller.weatherReveal > 0.005 {
                        let wScale = 0.84 + 0.16 * controller.weatherReveal
                        WeatherSolarCardOverlay(controller: controller, cardWidth: cardWidth)
                            .scaleEffect(wScale)
                            .opacity(Double(min(1.0, max(0.0, controller.weatherReveal))))
                            .position(controller.weatherCardCenter)
                            .allowsHitTesting(controller.isWeatherVisible)
                    }

                    // 7. Interactive Liquid Droplets (Main Hero Lens + Fusable Companion Droplet)
                    HeroLensHitTarget(controller: controller)

                    if controller.companionReveal > 0.02 {
                        CompanionDropletHitTarget(controller: controller)
                            .allowsHitTesting(controller.dualDropletEnabled)
                    }

                    // 8. Zone 4: Optical & Wallpaper Studio Drawer
                    if controller.drawerReveal > 0.005 {
                        let dScale = 0.92 + 0.08 * controller.drawerReveal
                        let drawerH: CGFloat = 360
                        let drawerBaseY = size.height - safeBottom - 86 - drawerH * 0.5
                        let slideOffset = (1.0 - min(1.0, controller.drawerReveal)) * 44

                        StudioDrawerOverlay(
                            controller: controller,
                            selectedPhotoItem: $selectedPhotoItem,
                            drawerWidth: drawerWidth
                        )
                        .scaleEffect(dScale)
                        .opacity(Double(min(1.0, max(0.0, controller.drawerReveal))))
                        .position(x: size.width * 0.5, y: drawerBaseY + slideOffset)
                        .allowsHitTesting(controller.isStudioVisible)
                    }

                    // 9. Native iOS 26 Sliding Jelly-Magnifier Bottom Liquid Dock
                    NativeLiquidDockOverlay(
                        controller: controller,
                        screenWidth: size.width
                    )
                    .position(x: size.width * 0.5, y: dockCenterY)

                    // 10. Safe-Area Top Status HUD
                    TopStatusHUD(
                        controller: controller,
                        selectedPhotoItem: $selectedPhotoItem
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, safeTop + 6)
                }
                .coordinateSpace(.named("screen"))
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

// MARK: - Isolated Droplet Hit Targets (Prevent 120Hz Physics From Invalidating Sibling Views)

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
                Text("拖曳雙水滴融合 · 底部按住滑動果凍放大")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.42), in: Capsule())
                    .offset(y: lensH * 0.5 + 22)
                    .allowsHitTesting(false)
            }
        }
        .position(controller.lensPosition)
    }
}

private struct CompanionDropletHitTarget: View {
    let controller: GlassSceneController

    var body: some View {
        let diameter = max(40, controller.companionRadius * 2)

        Circle()
            .fill(Color.white.opacity(0.001))
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("screen"))
                    .onChanged { value in
                        controller.updateCompanionDrag(
                            translation: value.translation,
                            velocity: value.velocity,
                            location: value.location
                        )
                    }
                    .onEnded { value in
                        controller.endCompanionDrag(velocity: value.velocity)
                    }
            )
            .position(controller.companionPosition)
    }
}
