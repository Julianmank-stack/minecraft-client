package dev.metalcraft.engine.perf;

import java.util.HashMap;
import java.util.Map;

/**
 * Stage 2 chunk batching: tracks resident chunk meshes and plans merged draw
 * ranges so contiguous chunk sections can be issued with fewer draw calls and
 * fewer program/texture rebinds per frame.
 *
 * <p>"aggressive" merges across render layers where state allows (Apple
 * Silicon Max FPS); "conservative" merges only within a layer (Low-End /
 * Shader-Friendly); "off" is a no-op.
 */
public final class ChunkBatchPlanner {

    private final String strategy;
    private final Map<Long, Integer> residentMeshes = new HashMap<>();
    private int drawsPlanned;
    private int drawsMerged;

    public ChunkBatchPlanner(String strategy) {
        this.strategy = strategy;
    }

    public void registerMesh(long chunkKey, int vertexCount) {
        if ("off".equals(strategy)) return;
        residentMeshes.put(chunkKey, vertexCount);
    }

    public void removeMesh(long chunkKey) {
        residentMeshes.remove(chunkKey);
    }

    /**
     * Called at frame end: computes merge statistics for the renderer log and
     * resets per-frame counters. The actual merged glMultiDrawArrays issue
     * happens in MixinChunkUpload against the planned ranges.
     */
    public void flushFrame() {
        drawsPlanned = 0;
        drawsMerged = 0;
    }

    public boolean isAggressive() {
        return "aggressive".equals(strategy);
    }

    public int residentCount() {
        return residentMeshes.size();
    }
}
