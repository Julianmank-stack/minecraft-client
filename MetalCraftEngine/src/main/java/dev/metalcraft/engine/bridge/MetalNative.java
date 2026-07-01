package dev.metalcraft.engine.bridge;

import dev.metalcraft.engine.safety.RendererLog;

import java.nio.ByteBuffer;

/**
 * JNI bridge to libmetalcraft_native.dylib (Swift + Metal).
 *
 * <p>The dylib path is provided by the launcher via
 * {@code -Dmetalcraft.native=<path>}. All functions here have @_cdecl
 * counterparts in MetalCraftNative/Sources/MetalCraftNative/CBridge.swift.
 */
public final class MetalNative {

    private static volatile boolean loaded;

    private MetalNative() {}

    public static boolean isAvailable() {
        if (loaded) return true;
        String path = System.getProperty("metalcraft.native");
        if (path == null || path.isBlank()) return false;
        try {
            System.load(path);
            loaded = true;
            RendererLog.info("Loaded native library: " + path);
            return true;
        } catch (UnsatisfiedLinkError e) {
            RendererLog.warn("Could not load native library: " + e.getMessage());
            return false;
        }
    }

    // Device capabilities (CBridge.swift: mc_device_*)
    public static native String deviceName();
    public static native boolean deviceHasUnifiedMemory();
    public static native boolean deviceSupportsMetal3();
    public static native long deviceRecommendedWorkingSetMB();

    // Frame pacing (CBridge.swift: mc_pacer_*)
    public static native void pacerStart();
    public static native void pacerStop();

    /** Blocks until the next ideal present window (CVDisplayLink-aligned). */
    public static native void pacerAwaitPresentWindow();

    // Experimental terrain renderer (CBridge.swift: mc_terrain_*)
    public static native void initTerrainRenderer();
    public static native void shutdownTerrainRenderer();

    /**
     * Zero-copy upload: {@code vertexData} MUST be a direct buffer using the
     * vanilla block-vertex layout. The native side keeps it resident in a
     * unified-memory MTLBuffer keyed by {@code chunkKey}.
     */
    public static native void uploadChunkMesh(long chunkKey, ByteBuffer vertexData, int vertexCount);

    public static native void removeChunkMesh(long chunkKey);

    /** Renders all resident terrain into the shared IOSurface for composition. */
    public static native void renderTerrainFrame();
}
