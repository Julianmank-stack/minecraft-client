package dev.metalcraft.engine.hud.modules;

import dev.metalcraft.engine.hud.HudModule;
import net.minecraft.client.MinecraftClient;

public final class FpsModule extends HudModule {

    public FpsModule() {
        super("fps", "FPS", true, 6, 6);
    }

    @Override
    public String text(MinecraftClient client) {
        return "FPS: " + client.getCurrentFps();
    }
}
