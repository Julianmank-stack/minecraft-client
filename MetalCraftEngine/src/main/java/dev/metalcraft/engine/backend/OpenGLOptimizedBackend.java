package dev.metalcraft.engine.backend;

import dev.metalcraft.engine.config.EngineConfig;
import dev.metalcraft.engine.perf.ChunkBatchPlanner;
import dev.metalcraft.engine.perf.FramePacer;
import dev.metalcraft.engine.safety.RendererLog;

import java.nio.ByteBuffer;

/**
 * Stage 1/2: Mac Optimized OpenGL and Apple Silicon Max FPS.
 *
 * <p>Pure Java/LWJGL — no native code required. The concrete optimizations:
 * <ul>
 *   <li><b>State-change elision</b> — GLStateCache mirrors bind/enable state and
 *       drops redundant calls before they reach Apple's expensive GL validation.</li>
 *   <li><b>Buffer orphaning discipline</b> — mid-frame {@code glBufferSubData}
 *       updates are rewritten to orphan+write to avoid CPU/GPU sync stalls.</li>
 *   <li><b>Chunk batch planning</b> — merges contiguous chunk draw ranges and
 *       sorts by render layer to cut program/texture rebinds (Stage 2).</li>
 *   <li><b>Frame pacing</b> — aligns swap timing with the display via the native
 *       CVDisplayLink pacer when the dylib is present, else adaptive vsync.</li>
 * </ul>
 */
public final class OpenGLOptimizedBackend implements RenderBackend {

    private final EngineConfig config;
    private final FramePacer pacer = new FramePacer();
    private final ChunkBatchPlanner batchPlanner;

    public OpenGLOptimizedBackend(EngineConfig config) {
        this.config = config;
        this.batchPlanner = new ChunkBatchPlanner(config.chunkBatching());
    }

    @Override
    public String name() {
        return EngineConfig.MODE_APPLE_SILICON.equals(config.mode())
                ? "OpenGL (Apple Silicon Max FPS)"
                : "OpenGL (Mac Optimized)";
    }

    @Override
    public void initialize() {
        if (config.framePacing()) {
            pacer.start();
        }
        RendererLog.info("GL optimizations active: stateElision=on, batching="
                + config.chunkBatching() + ", unifiedMemoryHints=" + config.unifiedMemoryHints());
    }

    @Override
    public void onFrameEnd() {
        batchPlanner.flushFrame();
        if (config.framePacing()) {
            pacer.awaitPresentWindow();
        }
    }

    @Override
    public boolean offerChunkMesh(long chunkKey, ByteBuffer vertexData, int vertexCount) {
        batchPlanner.registerMesh(chunkKey, vertexCount);
        return false; // GL keeps ownership; we only plan batches
    }

    @Override
    public void shutdown() {
        pacer.stop();
    }
}
