package dev.metalcraft.engine.config;

import com.google.gson.Gson;
import com.google.gson.JsonObject;

import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Engine configuration, written by the launcher into the instance directory
 * as metalcraft.json (schema in docs/DATA_SCHEMA.md). Falls back to safe
 * defaults when absent so the mod also works without the launcher.
 */
public record EngineConfig(
        String mode,
        boolean framePacing,
        boolean unifiedMemoryHints,
        String chunkBatching,
        boolean metalEnabled,
        boolean metalTerrainTakeover,
        int maxCrashesBeforeFallback,
        String rendererLogDir
) {
    public static final String MODE_STANDARD = "standardGL";
    public static final String MODE_MAC_OPTIMIZED = "macOptimizedGL";
    public static final String MODE_APPLE_SILICON = "appleSiliconMax";
    public static final String MODE_LOW_END = "lowEnd";
    public static final String MODE_SHADER_FRIENDLY = "shaderFriendly";
    public static final String MODE_METAL_EXPERIMENTAL = "metalExperimental";
    public static final String MODE_SAFE = "safe";

    public static EngineConfig load() {
        Path file = Path.of("..", "metalcraft.json").toAbsolutePath().normalize();
        if (!Files.exists(file)) {
            // Game dir layout: <instance>/.minecraft — config sits one level up.
            file = Path.of("metalcraft.json").toAbsolutePath();
        }
        if (Files.exists(file)) {
            try {
                JsonObject json = new Gson().fromJson(Files.readString(file), JsonObject.class);
                JsonObject metal = json.has("metal") ? json.getAsJsonObject("metal") : new JsonObject();
                JsonObject safety = json.has("safety") ? json.getAsJsonObject("safety") : new JsonObject();
                return new EngineConfig(
                        getString(json, "mode", MODE_MAC_OPTIMIZED),
                        getBool(json, "framePacing", true),
                        getBool(json, "unifiedMemoryHints", false),
                        getString(json, "chunkBatching", "off"),
                        getBool(metal, "enabled", false),
                        getBool(metal, "terrainTakeover", false),
                        getInt(safety, "maxCrashesBeforeFallback", 2),
                        getString(safety, "rendererLogDir", "logs/renderer")
                );
            } catch (Exception e) {
                // fall through to defaults
            }
        }
        return defaults();
    }

    public static EngineConfig defaults() {
        return new EngineConfig(MODE_MAC_OPTIMIZED, true, false, "off", false, false, 2, "logs/renderer");
    }

    public boolean isPassive() {
        return MODE_STANDARD.equals(mode) || MODE_SAFE.equals(mode);
    }

    private static String getString(JsonObject o, String key, String def) {
        return o.has(key) ? o.get(key).getAsString() : def;
    }

    private static boolean getBool(JsonObject o, String key, boolean def) {
        return o.has(key) ? o.get(key).getAsBoolean() : def;
    }

    private static int getInt(JsonObject o, String key, int def) {
        return o.has(key) ? o.get(key).getAsInt() : def;
    }
}
