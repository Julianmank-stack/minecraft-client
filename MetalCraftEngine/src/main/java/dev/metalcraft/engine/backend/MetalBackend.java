package dev.metalcraft.engine.backend;

import dev.metalcraft.engine.bridge.MetalNative;
import dev.metalcraft.engine.config.EngineConfig;
import dev.metalcraft.engine.safety.CrashSentinel;
import dev.metalcraft.engine.safety.RendererLog;

import java.nio.ByteBuffer;

/**
 * Stage 3: the Experimental Metal Renderer.
 *
 * <p>Takes over <b>chunk terrain rendering only</b>. Terrain meshes are handed
 * to the native layer (zero-copy direct ByteBuffers over JNI); the native
 * TerrainRenderer draws them into an IOSurface-backed Metal texture that is
 * composited with the remaining GL pipeline. Everything else — entities,
 * particles, UI, shaders — stays on OpenGL, and the mod never claims otherwise.
 *
 * <p>Every native call is wrapped by {@link CrashSentinel}; a native failure
 * tears this backend down live and continues on optimized OpenGL.
 */
public final class MetalBackend implements RenderBackend {

    private final EngineConfig config;
    private final OpenGLOptimizedBackend glFallback;
    private volatile boolean healthy;
    private long framesRendered;

    public MetalBackend(EngineConfig config) {
        this.config = config;
        this.glFallback = new OpenGLOptimizedBackend(config);
    }

    @Override
    public String name() {
        return "Metal (experimental terrain) + OpenGL";
    }

    @Override
    public void initialize() throws Exception {
        glFallback.initialize();
        CrashSentinel.guard("metal-init", () -> {
            MetalNative.initTerrainRenderer();
            healthy = true;
        });
        if (!healthy) {
            throw new IllegalStateException("Metal terrain renderer failed to initialize");
        }
        RendererLog.info("Metal terrain renderer initialized on "
                + MetalNative.deviceName() + " (unified memory: "
                + MetalNative.deviceHasUnifiedMemory() + ")");
    }

    @Override
    public void onFrameEnd() {
        if (healthy) {
            CrashSentinel.guard("metal-frame", () -> {
                MetalNative.renderTerrainFrame();
                framesRendered++;
                if (framesRendered == 120) {
                    dev.metalcraft.engine.MetalCraftMod.markRenderingHealthy();
                }
            });
            if (CrashSentinel.lastGuardFailed()) {
                degradeToGL("native frame error");
                return;
            }
        }
        glFallback.onFrameEnd();
    }

    @Override
    public boolean offerChunkMesh(long chunkKey, ByteBuffer vertexData, int vertexCount) {
        if (!healthy || !vertexData.isDirect()) {
            return glFallback.offerChunkMesh(chunkKey, vertexData, vertexCount);
        }
        CrashSentinel.guard("metal-upload", () ->
                MetalNative.uploadChunkMesh(chunkKey, vertexData, vertexCount));
        if (CrashSentinel.lastGuardFailed()) {
            degradeToGL("mesh upload error");
            return false;
        }
        return true; // Metal owns this mesh now
    }

    @Override
    public void shutdown() {
        if (healthy) {
            CrashSentinel.guard("metal-shutdown", MetalNative::shutdownTerrainRenderer);
        }
        glFallback.shutdown();
    }

    /** Live in-game downgrade: Metal off, optimized GL keeps the session alive. */
    private void degradeToGL(String reason) {
        healthy = false;
        RendererLog.error("Metal backend degraded to OpenGL (" + reason
                + "). The session continues on the GL path.", null);
        CrashSentinel.guard("metal-teardown", MetalNative::shutdownTerrainRenderer);
    }
}
