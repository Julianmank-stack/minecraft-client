package dev.metalcraft.engine.hud;

import java.util.ArrayDeque;
import java.util.Deque;

/**
 * Rolling one-second click counters for the CPS modules. Fed by MixinMouse
 * on every mouse-button press; reads prune anything older than one second.
 */
public final class ClickTracker {

    public static final ClickTracker LEFT = new ClickTracker();
    public static final ClickTracker RIGHT = new ClickTracker();

    private final Deque<Long> clicks = new ArrayDeque<>();

    private ClickTracker() {}

    public synchronized void recordClick() {
        clicks.addLast(System.nanoTime());
    }

    /** Clicks in the last second. */
    public synchronized int cps() {
        long cutoff = System.nanoTime() - 1_000_000_000L;
        while (!clicks.isEmpty() && clicks.peekFirst() < cutoff) {
            clicks.removeFirst();
        }
        return clicks.size();
    }
}
