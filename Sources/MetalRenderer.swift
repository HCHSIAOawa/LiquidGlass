import SwiftUI
import UIKit
import Metal
import MetalKit
import QuartzCore

// MARK: - Interactive 120Hz MTKView (Handles Droplet, Pinch & Cutout Touches with Zero SwiftUI State Overhead)

@MainActor
final class InteractiveMTKView: MTKView, UIGestureRecognizerDelegate {
    weak var sceneController: GlassSceneController?

    private enum ActivePanTarget {
        case none
        case islandCutout
        case companionDroplet
        case heroDroplet
        case waterCanvas
    }

    private var activePanTarget: ActivePanTarget = .none
    private var lastWaterRippleTime: CFTimeInterval = 0

    func installPlaygroundGestures() {
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer) ||
           (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer) {
            return true
        }
        return false
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let ctrl = sceneController else { return }
        let loc = gesture.location(in: self)
        let trans = gesture.translation(in: self)
        let vel = gesture.velocity(in: self)

        switch gesture.state {
        case .began:
            if ctrl.hitTestHardwareIsland(at: loc) {
                activePanTarget = .islandCutout
            } else if ctrl.hitTestCompanionDroplet(at: loc) {
                activePanTarget = .companionDroplet
                ctrl.beginCompanionDrag()
            } else if ctrl.hitTestHeroDroplet(at: loc) {
                activePanTarget = .heroDroplet
                ctrl.beginLensDrag()
            } else {
                activePanTarget = .waterCanvas
                ctrl.triggerRipple(at: loc, strength: 0.65)
            }

        case .changed:
            switch activePanTarget {
            case .islandCutout:
                if trans.y > 0 {
                    ctrl.updateIslandPullDown(translationY: trans.y)
                }
            case .companionDroplet:
                ctrl.updateCompanionDrag(translation: CGSize(width: trans.x, height: trans.y), velocity: CGSize(width: vel.x, height: vel.y), location: loc)
            case .heroDroplet:
                ctrl.updateLensDrag(translation: CGSize(width: trans.x, height: trans.y), velocity: CGSize(width: vel.x, height: vel.y), location: loc)
            case .waterCanvas:
                let now = CACurrentMediaTime()
                if now - lastWaterRippleTime > 0.09 {
                    lastWaterRippleTime = now
                    ctrl.triggerRipple(at: loc, strength: 0.45)
                }
            case .none:
                break
            }

        case .ended, .cancelled, .failed:
            switch activePanTarget {
            case .islandCutout:
                ctrl.endIslandPullDown()
            case .companionDroplet:
                ctrl.endCompanionDrag(velocity: CGSize(width: vel.x, height: vel.y))
            case .heroDroplet:
                ctrl.endLensDrag(velocity: CGSize(width: vel.x, height: vel.y))
            case .waterCanvas, .none:
                break
            }
            activePanTarget = .none

        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let ctrl = sceneController else { return }
        switch gesture.state {
        case .began, .changed:
            ctrl.updateLensPinch(magnification: gesture.scale)
        case .ended, .cancelled, .failed:
            ctrl.endLensPinch()
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let ctrl = sceneController else { return }
        ctrl.cycleLensShape()
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let ctrl = sceneController else { return }
        let loc = gesture.location(in: self)
        if ctrl.hitTestHardwareIsland(at: loc) {
            ctrl.handleHardwareIslandTap()
        } else {
            ctrl.triggerRipple(at: loc, strength: 0.78)
            HapticsManager.shared.tapSoft(intensity: 0.38)
            if ctrl.selectedTab == .opticalStudio {
                ctrl.selectedTab = .lensLab
            }
        }
    }
}

// MARK: - SwiftUI Representable Wrapping 120Hz InteractiveMTKView

@MainActor
struct MetalLiquidGlassView: UIViewRepresentable {
    let controller: GlassSceneController

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(controller: controller)
    }

    func makeUIView(context: Context) -> InteractiveMTKView {
        let mtkView = InteractiveMTKView(frame: .zero, device: context.coordinator.device)
        mtkView.sceneController = controller
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 120
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.025, green: 0.042, blue: 0.105, alpha: 1.0)
        let displayScale = UITraitCollection.current.displayScale
        mtkView.contentScaleFactor = displayScale > 0 ? min(displayScale, 3.0) : 3.0
        mtkView.isOpaque = true
        mtkView.installPlaygroundGestures()
        return mtkView
    }

    func updateUIView(_ uiView: InteractiveMTKView, context: Context) {
        uiView.sceneController = controller
        if uiView.preferredFramesPerSecond != 120 {
            uiView.preferredFramesPerSecond = 120
        }
    }
}

// MARK: - Single-Pass Pure GPU Metal Renderer

@MainActor
final class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?

    private var textTexture: MTLTexture?
    private var photoTexture: MTLTexture?
    private var fallbackTexture: MTLTexture?
    private var uploadedPhotoRevision: Int = 0

    private let controller: GlassSceneController

    init(controller: GlassSceneController) {
        self.controller = controller
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.commandQueue = dev?.makeCommandQueue()
        super.init()

        guard let dev = dev else { return }
        buildPipeline(device: dev)
        fallbackTexture = makeSolidFallbackTexture(device: dev)
        textTexture = buildScrollingTypographyTexture(device: dev)
    }

    private func buildPipeline(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: "liquidGlassVertex"),
              let fragmentFn = library.makeFunction(name: "liquidGlassFragment") else {
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "LiquidGlassSinglePassPipeline"
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = false

        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildScrollingTypographyTexture(device: MTLDevice) -> MTLTexture? {
        let texW = 2048
        let texH = 1024
        let rowCount = 8
        let rowHeight = CGFloat(texH) / CGFloat(rowCount)

        let bytesPerRow = texW * 4
        var rawBytes = [UInt8](repeating: 0, count: bytesPerRow * texH)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: &rawBytes,
            width: texW,
            height: texH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.translateBy(x: 0, y: CGFloat(texH))
        ctx.scaleBy(x: 1.0, y: -1.0)
        UIGraphicsPushContext(ctx)

        let baseFont = UIFont.systemFont(ofSize: 62, weight: .black)
        let roundedFont: UIFont
        if let desc = baseFont.fontDescriptor.withDesign(.rounded) {
            roundedFont = UIFont(descriptor: desc, size: 62)
        } else {
            roundedFont = baseFont
        }

        let evenPhrase = "LIQUID GLASS · DISPERSION · METAL 120FPS · "
        let oddPhrase  = "PRO MOTION · REFRACTION · PRISM OPTICS · "

        for row in 0..<rowCount {
            let isEven = (row % 2 == 0)
            let text = isEven ? evenPhrase : oddPhrase
            let color = isEven
                ? UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.90)
                : UIColor(red: 0.42, green: 0.92, blue: 1.0, alpha: 0.86)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont,
                .foregroundColor: color,
                .kern: 1.6
            ]

            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let naturalSize = attrStr.size()
            guard naturalSize.width > 10 else { continue }

            ctx.saveGState()
            let rowTop = CGFloat(row) * rowHeight
            let yOffset = rowTop + (rowHeight - naturalSize.height) * 0.5
            let scaleX = CGFloat(texW) / naturalSize.width
            ctx.translateBy(x: 0, y: yOffset)
            ctx.scaleBy(x: scaleX, y: 1.0)
            attrStr.draw(at: .zero)
            ctx.restoreGState()
        }

        UIGraphicsPopContext()
        return makeMipmappedTexture(device: device, width: texW, height: texH, bytes: rawBytes)
    }

    private func uploadCustomPhotoIfNeeded(device: MTLDevice) {
        guard controller.customPhotoRevision != uploadedPhotoRevision else { return }
        uploadedPhotoRevision = controller.customPhotoRevision

        guard let uiImage = controller.customPhotoImage,
              let cgImage = uiImage.cgImage else { return }

        let texW = max(1, cgImage.width)
        let texH = max(1, cgImage.height)
        let bytesPerRow = texW * 4
        var rawBytes = [UInt8](repeating: 0, count: bytesPerRow * texH)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let ctx = CGContext(
            data: &rawBytes,
            width: texW,
            height: texH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: texW, height: texH))
        photoTexture = makeMipmappedTexture(device: device, width: texW, height: texH, bytes: rawBytes)
    }

    private func makeMipmappedTexture(device: MTLDevice, width: Int, height: Int, bytes: [UInt8]) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: true
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        bytes.withUnsafeBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: width * 4
                )
            }
        }

        if let cmdBuf = commandQueue?.makeCommandBuffer(),
           let blit = cmdBuf.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            cmdBuf.commit()
        }

        return texture
    }

    private func makeSolidFallbackTexture(device: MTLDevice) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        let darkNeutral: [UInt8] = [28, 14, 10, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: darkNeutral, bytesPerRow: 4)
        return tex
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let device = device,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor else {
            return
        }

        // Pure GPU/Controller float update — NEVER mutates SwiftUI @State per frame!
        controller.stepFrame(now: CACurrentMediaTime(), drawablePointSize: view.bounds.size)
        uploadCustomPhotoIfNeeded(device: device)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            return
        }

        encoder.label = "LiquidGlassRenderEncoder"
        encoder.setRenderPipelineState(pipelineState)

        encoder.setFragmentBytes(
            &controller.sceneUniforms,
            length: MemoryLayout<SceneUniforms>.stride,
            index: 0
        )

        controller.elementUniforms.withUnsafeBytes { rawPtr in
            if let base = rawPtr.baseAddress {
                encoder.setFragmentBytes(base, length: rawPtr.count, index: 1)
            }
        }

        encoder.setFragmentTexture(textTexture ?? fallbackTexture, index: 0)
        encoder.setFragmentTexture(photoTexture ?? fallbackTexture, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
