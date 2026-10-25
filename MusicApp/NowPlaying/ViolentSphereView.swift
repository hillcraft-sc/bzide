import MetalKit
import NavidromeCore
import simd
import SwiftUI

/// The Violent Sphere visualizer: a turning ball of spikes drawn as a fine
/// wireframe, the spectrum pushing them out in patches and drum hits jolting
/// them all (`ViolentSphere` shapes it), colored from top to bottom.
///
/// Its tens of thousands of lines are too many for a SwiftUI Canvas, so it's
/// drawn with Metal (ViolentSphere.metal), one frame each time the
/// visualizer's timeline updates the view. Each frame goes through the
/// view's own `draw()`: MetalKit hands out a fresh drawable only there, and
/// drawing outside it reuses a spent one (a black, stuck screen).
struct ViolentSphereView: UIViewRepresentable {
    let levels: [Float]
    let beat: Float
    let date: Date
    /// Five colors, top to bottom.
    let colors: [Color]
    /// The space left for drawing inside the safe area; the view itself
    /// fills the screen, so long spikes can reach past it.
    let insets: EdgeInsets
    let state: ViolentSphereState

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: state.device)
        // Drawn only from updateUIView, in step with the timeline.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.sampleCount = ViolentSphereState.sampleCount
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.backgroundColor = .black
        view.delegate = state
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        state.advance(levels: levels, beat: beat, at: date, colors: colors, insets: insets)
        view.draw()
    }
}

/// The sphere's shape between frames and what Metal needs to draw it. Built
/// on the first frame, so choosing another style costs nothing.
@MainActor
final class ViolentSphereState: NSObject, MTKViewDelegate {
    static let sampleCount = 4
    /// How far the camera is, in resting radii: far enough that the near
    /// spikes aren't much bigger than the far ones.
    static let cameraDistance: Float = 10
    /// The resting radius is this fraction of the drawing space's shorter
    /// side: typical spikes fill it, and only the longest reach past.
    static let restFraction: CGFloat = 1.0 / 3
    /// The ball leans toward the viewer, so the top shows as it turns.
    static let tilt: Float = 0.35

    let device = MTLCreateSystemDefaultDevice()
    private var sphere: ViolentSphere?
    private var lastFrame: Date?
    private var drawing: Drawing?
    private var colors: [Color] = []
    private var insets = EdgeInsets()

    /// The pipeline and the mesh's buffers, which don't change.
    private struct Drawing {
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
        let faceDepth: MTLDepthStencilState
        let wireDepth: MTLDepthStencilState
        let directions: MTLBuffer
        let triangles: MTLBuffer
        let triangleCount: Int
        let edges: MTLBuffer
        let edgeCount: Int
    }

    /// Moves the spikes on to this frame.
    func advance(levels: [Float], beat: Float, at date: Date, colors: [Color], insets: EdgeInsets) {
        if sphere == nil { sphere = ViolentSphere() }
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
        lastFrame = date
        // In place, so the big arrays aren't copied every frame.
        sphere?.update(levels: levels, beat: beat, elapsed: elapsed)
        self.colors = colors
        self.insets = insets
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let sphere, let drawing = drawing ?? makeDrawing(for: sphere, view: view) else { return }
        self.drawing = drawing
        let size = view.bounds.size
        guard size.width > 0, size.height > 0,
              let radii = drawing.queue.device.makeBuffer(
                bytes: sphere.radii, length: sphere.radii.count * MemoryLayout<Float>.stride
              ),
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = drawing.queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        // Centered in the drawing space, in clip space (y up).
        let safe = view.safeAreaInsets
        let space = view.bounds.inset(by: UIEdgeInsets(
            top: safe.top + insets.top, left: safe.left + insets.leading,
            bottom: safe.bottom + insets.bottom, right: safe.right + insets.trailing
        ))
        let rest = Float(min(space.width, space.height) * Self.restFraction)
        var frame = SIMD4<Float>(rest / Float(size.width / 2), rest / Float(size.height / 2), Self.cameraDistance, 0)
        var center = SIMD4<Float>(
            Float((space.midX - size.width / 2) / (size.width / 2)),
            Float((size.height / 2 - space.midY) / (size.height / 2)),
            0, 0
        )
        var turn = Self.turn(spin: sphere.spin)
        var stops = Self.stops(colors)

        encoder.setRenderPipelineState(drawing.pipeline)
        encoder.setVertexBuffer(drawing.directions, offset: 0, index: 0)
        encoder.setVertexBuffer(radii, offset: 0, index: 1)
        encoder.setVertexBytes(&turn, length: MemoryLayout<simd_float4x4>.stride, index: 2)
        encoder.setVertexBytes(&stops, length: MemoryLayout<SIMD4<Float>>.stride * stops.count, index: 3)
        encoder.setVertexBytes(&frame, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
        encoder.setVertexBytes(&center, length: MemoryLayout<SIMD4<Float>>.stride, index: 5)

        // Dark faces first, hiding the wires on the far side.
        var faces = SIMD4<Float>(0.15, 1, 0, 0)
        encoder.setDepthStencilState(drawing.faceDepth)
        encoder.setVertexBytes(&faces, length: MemoryLayout<SIMD4<Float>>.stride, index: 6)
        encoder.drawIndexedPrimitives(
            type: .triangle, indexCount: drawing.triangleCount, indexType: .uint32, indexBuffer: drawing.triangles, indexBufferOffset: 0
        )
        var wires = SIMD4<Float>(1, 1.004, 0, 0)
        encoder.setDepthStencilState(drawing.wireDepth)
        encoder.setVertexBytes(&wires, length: MemoryLayout<SIMD4<Float>>.stride, index: 6)
        encoder.drawIndexedPrimitives(
            type: .line, indexCount: drawing.edgeCount, indexType: .uint32, indexBuffer: drawing.edges, indexBufferOffset: 0
        )
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Turned about the vertical by `spin`, then leaned toward the viewer.
    private static func turn(spin: Float) -> simd_float4x4 {
        let around = simd_quatf(angle: spin, axis: SIMD3(0, 1, 0))
        let lean = simd_quatf(angle: tilt, axis: SIMD3(1, 0, 0))
        return simd_float4x4(lean * around)
    }

    /// Five colors as the shader's RGBA, in the screen's sRGB.
    private static func stops(_ colors: [Color]) -> [SIMD4<Float>] {
        let five = colors.isEmpty ? [Color.white] : colors
        return (0..<5).map { index in
            var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            UIColor(five[min(index, five.count - 1)]).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD4(Float(red), Float(green), Float(blue), 1)
        }
    }

    private func makeDrawing(for sphere: ViolentSphere, view: MTKView) -> Drawing? {
        guard let device,
              let library = device.makeDefaultLibrary(),
              let queue = device.makeCommandQueue()
        else { return nil }
        let description = MTLRenderPipelineDescriptor()
        description.vertexFunction = library.makeFunction(name: "violentSphereVertex")
        description.fragmentFunction = library.makeFunction(name: "violentSphereFragment")
        description.colorAttachments[0].pixelFormat = view.colorPixelFormat
        description.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        description.rasterSampleCount = view.sampleCount
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: description),
              let faceDepth = Self.depth(on: device, compare: .less, writes: true),
              let wireDepth = Self.depth(on: device, compare: .lessEqual, writes: false)
        else { return nil }

        // Packed three floats a point, as the shader reads them.
        let packed = sphere.directions.flatMap { [$0.x, $0.y, $0.z] }
        guard let directions = device.makeBuffer(bytes: packed, length: packed.count * MemoryLayout<Float>.stride),
              let triangles = device.makeBuffer(
                bytes: sphere.triangles, length: sphere.triangles.count * MemoryLayout<UInt32>.stride
              ),
              let edges = device.makeBuffer(bytes: sphere.edges, length: sphere.edges.count * MemoryLayout<UInt32>.stride)
        else { return nil }
        return Drawing(
            queue: queue, pipeline: pipeline, faceDepth: faceDepth, wireDepth: wireDepth,
            directions: directions, triangles: triangles, triangleCount: sphere.triangles.count,
            edges: edges, edgeCount: sphere.edges.count
        )
    }

    private static func depth(on device: MTLDevice, compare: MTLCompareFunction, writes: Bool) -> MTLDepthStencilState? {
        let description = MTLDepthStencilDescriptor()
        description.depthCompareFunction = compare
        description.isDepthWriteEnabled = writes
        return device.makeDepthStencilState(descriptor: description)
    }
}
