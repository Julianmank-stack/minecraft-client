package dev.metalcraft.engine.backend;

import dev.metalcraft.engine.bridge.MetalNative;
import dev.metalcraft.engine.config.EngineConfig;
import dev.metalcraft.engine.safety.RendererLog;
import net.fabricmc.loader.api.FabricLoader;

/**
 * Picks the backend from config + runtime environment, enforcing the
 * compatibility gates documented in docs/METALCRAFT_ENGINE.md.
 */
public final class BackendSelector {

    private BackendSelector() {}

    public static RenderBackend select(EngineConfig config) {
        if (config.isPassive()) {
            RendererLog.info("Passive mode requested (" + config.mode() + ")");
            return passiveFallback();
        }

        if (config.metalEnabled() && config.metalTerrainTakeover()) {
            String blocker = metalBlocker();
            if (blocker == null) {
                RendererLog.info("Selecting experimental Metal backend");
                return new MetalBackend(config);
            }
            RendererLog.warn("Metal backend requested but blocked: " + blocker
                    + " — using optimized OpenGL instead.");
        }

        return new OpenGLOptimizedBackend(config);
    }

    public static RenderBackend passiveFallback() {
        return new RenderBackend() {
            @Override public String name() { return "passive"; }
            @Override public void initialize() {}
            @Override public void onFrameEnd() {}
            @Override public boolean offerChunkMesh(long key, java.nio.ByteBuffer data, int count) { return false; }
            @Override public void shutdown() {}
        };
    }

    /** Returns a human-readable reason the Metal backend can't run, or null if it can. */
    private static String metalBlocker() {
        if (FabricLoader.getInstance().isModLoaded("sodium")
                || FabricLoader.getInstance().isModLoaded("embeddium")) {
            return "a Sodium-style renderer mod is installed";
        }
        if (FabricLoader.getInstance().isModLoaded("iris")) {
            return "a shader pipeline mod (Iris) is installed";
        }
        if (!MetalNative.isAvailable()) {
            return "libmetalcraft_native.dylib not found (set -Dmetalcraft.native=<path>)";
        }
        if (!MetalNative.deviceSupportsMetal3()) {
            return "this GPU does not support Metal 3";
        }
        return null;
    }
}
