package dev.metalcraft.engine.mixin;

import dev.metalcraft.engine.hud.ClickTracker;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.Mouse;
import org.lwjgl.glfw.GLFW;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Feeds the CPS modules: records every left/right mouse-button press while
 * in-game (menus don't count, matching how CPS counters usually behave).
 */
@Mixin(Mouse.class)
public abstract class MixinMouse {

    @Inject(method = "onMouseButton", at = @At("HEAD"))
    private void metalcraft$countClicks(long window, int button, int action, int mods, CallbackInfo ci) {
        if (action != GLFW.GLFW_PRESS) return;
        if (MinecraftClient.getInstance().currentScreen != null) return;
        if (button == GLFW.GLFW_MOUSE_BUTTON_LEFT) {
            ClickTracker.LEFT.recordClick();
        } else if (button == GLFW.GLFW_MOUSE_BUTTON_RIGHT) {
            ClickTracker.RIGHT.recordClick();
        }
    }
}
