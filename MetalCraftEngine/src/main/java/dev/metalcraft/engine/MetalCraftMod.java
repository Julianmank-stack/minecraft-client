package dev.metalcraft.engine;

import dev.metalcraft.engine.backend.BackendSelector;
import dev.metalcraft.engine.backend.RenderBackend;
import dev.metalcraft.engine.config.EngineConfig;
import dev.metalcraft.engine.hud.HudManager;
import dev.metalcraft.engine.safety.CrashSentinel;
import dev.metalcraft.engine.safety.RendererLog;
import net.fabricmc.api.ClientModInitializer;

/**
 * MetalCraft Engine — macOS-first rendering optimization system.
 *
 * <p>This is an original implementation: no code is copied from existing
 * renderer mods. On non-macOS platforms the mod stays completely passive.
 *
 * <p>Configuration is written by the MetalCraft Launcher into
 * {@code <instance>/metalcraft.json}; without it the mod defaults to the
 * conservative "macOptimizedGL" behavior (Stage 1 only).
 */
public final class MetalCraftMod implements ClientModInitializer {

    public static final String MOD_ID = "metalcraft-engine";

    private static RenderBackend activeBackend;
    private static EngineConfig config;

    @Override
    public void onInitializeClient() {
        // HUD + R-Shift mod menu work on every platform.
        HudManager.INSTANCE.register();

        // The rendering backend is macOS-only.
        if (!System.getProperty("os.name", "").contains("Mac")) {
            RendererLog.info("Not running on macOS — MetalCraft renderer is passive (HUD still active).");
            return;
        }

        config = EngineConfig.load();
        RendererLog.init(config.rendererLogDir());
        RendererLog.info("MetalCraft Engine starting, requested mode: " + config.mode());

        CrashSentinel.writeHandshake("starting", config.mode());

        activeBackend = BackendSelector.select(config);
        try {
            activeBackend.initialize();
            RendererLog.info("Backend initialized: " + activeBackend.name());
        } catch (Throwable t) {
            RendererLog.error("Backend init failed, falling back to passive GL", t);
            activeBackend = BackendSelector.passiveFallback();
        }
    }

    public static RenderBackend backend() {
        return activeBackend;
    }

    public static EngineConfig config() {
        return config;
    }

    /** Called by MixinWindowSwap once the game has rendered its first frames. */
    public static void markRenderingHealthy() {
        CrashSentinel.writeHandshake("ok", config != null ? config.mode() : "unknown");
    }
}
