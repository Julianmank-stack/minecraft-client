package dev.metalcraft.engine.perf;

import dev.metalcraft.engine.bridge.MetalNative;

import java.util.concurrent.locks.LockSupport;

/**
 * Frame pacing: aligns buffer swaps with the display refresh to reduce stutter.
 *
 * <p>With the native dylib present this delegates to a CVDisplayLink pacer
 * (exact display timing, ProMotion-aware). Without it, a pure-Java fallback
 * paces to the estimated refresh interval, which still smooths frame delivery
 * compared to vanilla's free-running swap.
 */
public final class FramePacer {

    private boolean useNative;
    private boolean running;
    private long lastFrameNanos;
    private long targetIntervalNanos = 16_666_667L; // ~60 Hz fallback estimate

    public void start() {
        useNative = MetalNative.isAvailable();
        if (useNative) {
            MetalNative.pacerStart();
        }
        running = true;
        lastFrameNanos = System.nanoTime();
    }

    public void awaitPresentWindow() {
        if (!running) return;
        if (useNative) {
            MetalNative.pacerAwaitPresentWindow();
            return;
        }
        // Java fallback: sleep-until-deadline with a spin tail for accuracy.
        long now = System.nanoTime();
        long deadline = lastFrameNanos + targetIntervalNanos;
        long remaining = deadline - now;
        if (remaining > 2_000_000L) {
            LockSupport.parkNanos(remaining - 1_500_000L);
        }
        while (System.nanoTime() < deadline) {
            Thread.onSpinWait();
        }
        lastFrameNanos = Math.max(deadline, System.nanoTime() - targetIntervalNanos);
    }

    public void stop() {
        if (useNative) {
            MetalNative.pacerStop();
        }
        running = false;
    }
}
