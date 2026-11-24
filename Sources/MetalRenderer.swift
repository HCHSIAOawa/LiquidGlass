import SwiftUI
import UIKit
import Metal
import MetalKit
import QuartzCore

// MARK: - SwiftUI Representable Wrapping 120Hz MTKView

struct MetalLiquidGlassView: UIViewRepresentable {
    let controller: GlassSceneController

    func makeCoordinator() -> MetalRenderer {
        MetalRenderer(controller: controller)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: context.coordinator.device)
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
        mtkView.isUserInteractionEnabled = false
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if uiView.preferredFramesPerSecond != 120 {
            uiView.preferredFramesPerSecond = 120
        }
    }
}

// MARK: - Single-Pass Pure GPU Metal Renderer

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

    // MARK: - Static Seamless Scrolling Typography Texture (Mipmapped)

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

        // Flip to UIKit top-down coordinates so NSAttributedString draws upright
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

        let evenPhrase = "LIQUID GLASS · REFRACTION · METAL 120HZ · SPECULAR · "
        let oddPhrase  = "DISPERSION · PRO MOTION · CAUSTICS · APPLE DESIGN · "

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
            // Scale horizontally so one full phrase tiles across exact 2048px with zero wrap seam
            let scaleX = CGFloat(texW) / naturalSize.width
            ctx.translateBy(x: 0, y: yOffset)
            ctx.scaleBy(x: scaleX, y: 1.0)
            attrStr.draw(at: .zero)
            ctx.restoreGState()
        }

        UIGraphicsPopContext()

        return makeMipmappedTexture(device: device, width: texW, height: texH, bytes: rawBytes)
    }

    // MARK: - Custom Photo Texture Upload (Mipmapped)

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
        let white: [UInt8] = [255, 255, 255, 255]
        tex.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: white, bytesPerRow: 4)
        return tex
    }

    // MARK: - MTKViewDelegate (120Hz Render Loop)

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let device = device,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor else {
            return
        }

        // Step 120Hz physics & build uniform buffers in lockstep with vsync
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

        // Single full-screen triangle (3 vertices, zero overdraw along screen diagonal)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
