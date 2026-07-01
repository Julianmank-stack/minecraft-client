package dev.metalcraft.engine.mixin;

import dev.metalcraft.engine.MetalCraftMod;
import dev.metalcraft.engine.backend.RenderBackend;
import net.minecraft.client.util.Window;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/**
 * Hooks the buffer swap: gives the active backend its end-of-frame callback
 * (frame pacing, Metal terrain present, batch flush) right before GLFW swaps.
 */
@Mixin(Window.class)
public abstract class MixinWindowSwap {

    @Inject(method = "swapBuffers", at = @At("HEAD"))
    private void metalcraft$onFrameEnd(CallbackInfo ci) {
        RenderBackend backend = MetalCraftMod.backend();
        if (backend != null) {
            backend.onFrameEnd();
        }
    }
}
