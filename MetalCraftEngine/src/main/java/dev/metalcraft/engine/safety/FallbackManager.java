package dev.metalcraft.engine.safety;

import dev.metalcraft.engine.config.EngineConfig;

import java.util.List;

/**
 * The automatic downgrade chain (mirrors RendererMode.fallback in the
 * launcher, which owns the persistent crash counters in instance.json):
 *
 * <pre>metalExperimental → appleSiliconMax → macOptimizedGL → standardGL → safe</pre>
 *
 * The mod applies the in-session live degrade (MetalBackend → GL); the
 * launcher applies the cross-launch fallback when crash counts hit the
 * configured threshold.
 */
public final class FallbackManager {

    private static final List<String> CHAIN = List.of(
            EngineConfig.MODE_METAL_EXPERIMENTAL,
            EngineConfig.MODE_APPLE_SILICON,
            EngineConfig.MODE_MAC_OPTIMIZED,
            EngineConfig.MODE_STANDARD,
            EngineConfig.MODE_SAFE
    );

    private FallbackManager() {}

    /** Next-safer mode, or "safe" if already at the end of the chain. */
    public static String fallbackFor(String mode) {
        int index = CHAIN.indexOf(mode);
        if (index < 0 || index == CHAIN.size() - 1) {
            return EngineConfig.MODE_SAFE;
        }
        return CHAIN.get(index + 1);
    }
}
