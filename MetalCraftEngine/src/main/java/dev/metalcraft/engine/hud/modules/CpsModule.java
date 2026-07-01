package dev.metalcraft.engine.hud.modules;

import dev.metalcraft.engine.hud.ClickTracker;
import dev.metalcraft.engine.hud.HudModule;
import net.minecraft.client.MinecraftClient;

/** Clicks-per-second box; one instance per mouse button (left, right). */
public final class CpsModule extends HudModule {

    public enum Button { LEFT, RIGHT }

    private final Button button;

    public CpsModule(Button button) {
        super(
                button == Button.LEFT ? "cps_left" : "cps_right",
                button == Button.LEFT ? "CPS (Left)" : "CPS (Right)",
                true,
                6,
                button == Button.LEFT ? 46 : 66
        );
        this.button = button;
    }

    @Override
    public String text(MinecraftClient client) {
        int cps = (button == Button.LEFT ? ClickTracker.LEFT : ClickTracker.RIGHT).cps();
        return (button == Button.LEFT ? "LCPS: " : "RCPS: ") + cps;
    }
}
