import Foundation

/// C ABI exported for the Java side (MetalNative.java).
///
/// JNI note: functions follow the JNI naming convention
/// Java_dev_metalcraft_engine_bridge_MetalNative_<method> so System.load +
/// native method resolution binds them directly. The JNIEnv/jclass parameters
/// are received as opaque pointers; we don't call back into the JVM except to
/// return primitives, and the mesh path uses GetDirectBufferAddress semantics
/// via the raw address passed from a direct ByteBuffer.

// MARK: - Device capabilities

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_deviceHasUnifiedMemory")
public func mc_device_hasUnifiedMemory(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) -> UInt8 {
    MetalDeviceInfo.shared.hasUnifiedMemory ? 1 : 0
}

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_deviceSupportsMetal3")
public func mc_device_supportsMetal3(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) -> UInt8 {
    MetalDeviceInfo.shared.supportsMetal3 ? 1 : 0
}

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_deviceRecommendedWorkingSetMB")
public func mc_device_recommendedWorkingSetMB(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) -> Int64 {
    MetalDeviceInfo.shared.recommendedWorkingSetMB
}

// deviceName returns a jstring; constructing it needs JNIEnv->NewStringUTF.
// The C shim for string returns lives in the JNI glue (see JNIGlue.c note in
// README); until then Java callers should treat name as optional.

// MARK: - Frame pacing

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_pacerStart")
public func mc_pacer_start(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) {
    FramePacer.shared.start()
}

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_pacerStop")
public func mc_pacer_stop(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) {
    FramePacer.shared.stop()
}

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_pacerAwaitPresentWindow")
public func mc_pacer_awaitPresentWindow(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) {
    FramePacer.shared.awaitPresentWindow()
}

// MARK: - Experimental terrain renderer

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_initTerrainRenderer")
public func mc_terrain_init(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) {
    TerrainRenderer.shared.initialize()
}

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_shutdownTerrainRenderer")
public func mc_terrain_shutdown(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) {
    TerrainRenderer.shared.shutdown()
}

@_cdecl("Java_dev_metalcraft_engine_bridge_MetalNative_renderTerrainFrame")
public func mc_terrain_renderFrame(_ env: UnsafeMutableRawPointer?, _ cls: UnsafeMutableRawPointer?) {
    TerrainRenderer.shared.renderFrame()
}

@_cdecl("mc_terrain_uploadChunkMesh")
public func mc_terrain_uploadChunkMesh(_ chunkKey: Int64, _ vertexData: UnsafeRawPointer?, _ byteLength: Int32, _ vertexCount: Int32) {
    guard let vertexData else { return }
    TerrainRenderer.shared.uploadMesh(
        chunkKey: chunkKey,
        vertexData: vertexData,
        byteLength: Int(byteLength),
        vertexCount: Int(vertexCount)
    )
}

@_cdecl("mc_terrain_removeChunkMesh")
public func mc_terrain_removeChunkMesh(_ chunkKey: Int64) {
    TerrainRenderer.shared.removeMesh(chunkKey: chunkKey)
}
