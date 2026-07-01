package dev.metalcraft.engine.safety;

import com.google.gson.JsonObject;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;

/**
 * Crash protection.
 *
 * <p><b>Handshake:</b> writes logs/renderer/handshake.json with state
 * "starting" before backend init and "ok" after 120 healthy frames. If the
 * launcher finds a stale "starting" on next launch, it counts a renderer crash
 * even when no JVM crash report exists (GPU hangs, SIGKILL).
 *
 * <p><b>Guards:</b> every native call goes through {@link #guard}; a throwable
 * is logged and flagged so the backend can degrade to GL live instead of
 * killing the game session.
 */
public final class CrashSentinel {

    private static final ThreadLocal<Boolean> lastGuardFailed = ThreadLocal.withInitial(() -> false);

    private CrashSentinel() {}

    public static void writeHandshake(String state, String mode) {
        try {
            Path dir = Path.of("logs", "renderer");
            Files.createDirectories(dir);
            JsonObject json = new JsonObject();
            json.addProperty("state", state);
            json.addProperty("mode", mode);
            json.addProperty("time", Instant.now().toString());
            Files.writeString(dir.resolve("handshake.json"), json.toString());
        } catch (IOException e) {
            RendererLog.warn("Could not write handshake: " + e.getMessage());
        }
    }

    /** Runs {@code action}, converting any throwable into a logged, flagged failure. */
    public static void guard(String label, Runnable action) {
        lastGuardFailed.set(false);
        try {
            action.run();
        } catch (Throwable t) {
            lastGuardFailed.set(true);
            RendererLog.error("Guarded native call failed [" + label + "]", t);
        }
    }

    /** Whether the most recent {@link #guard} call on this thread failed. */
    public static boolean lastGuardFailed() {
        return lastGuardFailed.get();
    }
}
