package dev.metalcraft.engine.backend;

import java.nio.ByteBuffer;

/**
 * A rendering backend stage. Backends are selected once at startup by
 * {@link BackendSelector} and may be torn down live (crash fallback).
 */
public interface RenderBackend {

    String name();

    /** One-time setup. Throwing here triggers immediate fallback selection. */
    void initialize() throws Exception;

    /**
     * Called from MixinWindowSwap right before buffer swap. Backends use this
     * for frame pacing and end-of-frame state maintenance.
     */
    void onFrameEnd();

    /**
     * Offered a freshly built chunk mesh (post-meshing vertex data).
     *
     * @return true if this backend takes ownership of rendering that mesh
     *         (Metal terrain takeover); false to let vanilla GL handle it.
     */
    boolean offerChunkMesh(long chunkKey, ByteBuffer vertexData, int vertexCount);

    /** Live teardown; must leave the vanilla GL pipeline fully functional. */
    void shutdown();
}
