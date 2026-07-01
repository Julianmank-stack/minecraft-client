package dev.metalcraft.engine.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;

/**
 * A toggleable HUD module (Ping, FPS, CPS, …) drawn as a small rounded box.
 * Modules are toggled and repositioned from the R-Shift mod menu
 * ({@link ModMenuScreen}) and persisted by {@link HudManager}.
 */
public abstract class HudModule {

    private final String id;
    private final String displayName;

    private boolean enabled;
    private int x;
    private int y;

    protected HudModule(String id, String displayName, boolean enabledByDefault, int defaultX, int defaultY) {
        this.id = id;
        this.displayName = displayName;
        this.enabled = enabledByDefault;
        this.x = defaultX;
        this.y = defaultY;
    }

    /** The text shown inside the box this frame, e.g. "FPS: 120". */
    public abstract String text(MinecraftClient client);

    public void render(DrawContext context, MinecraftClient client) {
        if (!enabled) return;
        drawBox(context, client, text(client), x, y);
    }

    /** Shared box style: translucent dark fill, accent left edge, shadowed text. */
    static void drawBox(DrawContext context, MinecraftClient client, String text, int x, int y) {
        int width = client.textRenderer.getWidth(text) + PADDING * 2;
        int height = client.textRenderer.fontHeight + PADDING * 2 - 2;
        context.fill(x, y, x + width, y + height, 0x90101014);          // body
        context.fill(x, y, x + 2, y + height, 0xFF4C8DFF);              // accent edge
        context.drawTextWithShadow(client.textRenderer, text, x + PADDING, y + PADDING - 1, 0xFFFFFFFF);
    }

    static final int PADDING = 5;

    public int boxWidth(MinecraftClient client) {
        return client.textRenderer.getWidth(text(client)) + PADDING * 2;
    }

    public int boxHeight(MinecraftClient client) {
        return client.textRenderer.fontHeight + PADDING * 2 - 2;
    }

    // Accessors used by the menu + persistence

    public String id() { return id; }
    public String displayName() { return displayName; }
    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }
    public void toggle() { enabled = !enabled; }
    public int getX() { return x; }
    public int getY() { return y; }
    public void setPosition(int x, int y) { this.x = x; this.y = y; }
}
