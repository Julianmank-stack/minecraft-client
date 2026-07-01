import Foundation
import Metal
import IOSurface

/// Experimental Metal terrain renderer (Stage 3).
///
/// Receives chunk vertex data from Java (zero-copy from direct ByteBuffers),
/// keeps it resident in unified-memory MTLBuffers, and renders all terrain
/// into an IOSurface-backed texture each frame. The Java/GL side binds that
/// IOSurface via CGLTexImageIOSurface2D and composites it under the remaining
/// GL passes (entities, particles, UI) with a shared depth pre-pass.
///
/// Everything here is defensive: any failure flips `healthy` off and the Java
/// CrashSentinel degrades the session to the OpenGL path without crashing.
final class TerrainRenderer {
    static let shared = TerrainRenderer()

    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var targetTexture: MTLTexture?
    private var depthTexture: MTLTexture?
    private var ioSurface: IOSurfaceRef?

    private struct ResidentMesh {
        let buffer: MTLBuffer
        let vertexCount: Int
    }

    private var meshes: [Int64: ResidentMesh] = [:]
    private let lock = NSLock()
    private(set) var healthy = false

    private var width = 1920
    private var height = 1080

    private init() {}

    // MARK: - Lifecycle

    func initialize() {
        guard let device = MetalDeviceInfo.shared.device,
              device.supportsFamily(.metal3) else { return }
        self.device = device
        queue = device.makeCommandQueue()

        do {
            try buildPipeline(device: device)
            try buildTargets(device: device)
            healthy = pipeline != nil && targetTexture != nil
        } catch {
            healthy = false
        }
    }

    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        meshes.removeAll()
        pipeline = nil
        targetTexture = nil
        depthTexture = nil
        ioSurface = nil
        healthy = false
    }

    // MARK: - Mesh residency

    /// Copies the mesh into a shared-storage MTLBuffer. On unified-memory
    /// Apple Silicon this is a single memcpy into GPU-visible memory — no
    /// staging round trip.
    func uploadMesh(chunkKey: Int64, vertexData: UnsafeRawPointer, byteLength: Int, vertexCount: Int) {
        guard healthy, let device else { return }
        guard let buffer = device.makeBuffer(bytes: vertexData, length: byteLength, options: .storageModeShared) else {
            return
        }
        lock.lock()
        meshes[chunkKey] = ResidentMesh(buffer: buffer, vertexCount: vertexCount)
        lock.unlock()
    }

    func removeMesh(chunkKey: Int64) {
        lock.lock()
        meshes.removeValue(forKey: chunkKey)
        lock.unlock()
    }

    // MARK: - Frame

    func renderFrame() {
        guard healthy,
              let queue,
              let pipeline,
              let target = targetTexture,
              let depth = depthTexture else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1.0

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            healthy = false
            return
        }

        encoder.setRenderPipelineState(pipeline)
        if let depthState { encoder.setDepthStencilState(depthState) }

        lock.lock()
        let resident = meshes.values
        lock.unlock()

        for mesh in resident {
            encoder.setVertexBuffer(mesh.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
        }

        encoder.endEncoding()
        commands.commit()
        // No waitUntilCompleted: the GL side syncs on the IOSurface via
        // a fence when it binds the texture for composition.
    }

    // MARK: - Setup

    private func buildPipeline(device: MTLDevice) throws {
        // Shaders ship as .metal source in the bundle and are compiled at
        // first run (cached by the OS shader cache afterwards).
        let library: MTLLibrary
        if let url = Bundle.module.url(forResource: "Terrain", withExtension: "metal"),
           let source = try? String(contentsOf: url) {
            library = try device.makeLibrary(source: source, options: nil)
        } else if let defaultLibrary = try? device.makeDefaultLibrary(bundle: .module) {
            library = defaultLibrary
        } else {
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "terrain_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "terrain_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    private func buildTargets(device: MTLDevice) throws {
        let surfaceProps: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        guard let surface = IOSurface(properties: surfaceProps) else { return }
        ioSurface = surface as IOSurfaceRef

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        targetTexture = device.makeTexture(descriptor: colorDescriptor, iosurface: surface as IOSurfaceRef, plane: 0)

        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        depthTexture = device.makeTexture(descriptor: depthDescriptor)
    }
}
