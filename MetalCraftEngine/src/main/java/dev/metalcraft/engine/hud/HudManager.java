package dev.metalcraft.engine.hud;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import dev.metalcraft.engine.hud.modules.CpsModule;
import dev.metalcraft.engine.hud.modules.FpsModule;
import dev.metalcraft.engine.hud.modules.PingModule;
import dev.metalcraft.engine.safety.RendererLog;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import org.lwjgl.glfw.GLFW;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * The mod-menu HUD system: registers the Right-Shift key binding, owns the
 * module list (Ping, FPS, CPS left/right — more to come), renders enabled
 * modules every frame, and persists toggle state + positions to
 * config/metalcraft-hud.json.
 */
public final class HudManager {

    public static final HudManager INSTANCE = new HudManager();

    private final List<HudModule> modules = List.of(
            new FpsModule(),
            new PingModule(),
            new CpsModule(CpsModule.Button.LEFT),
            new CpsModule(CpsModule.Button.RIGHT)
    );

    private KeyBinding menuKey;

    private HudManager() {}

    public void register() {
        load();

        menuKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.metalcraft.menu",
                InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_RIGHT_SHIFT,
                "category.metalcraft"
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            while (menuKey.wasPressed()) {
                if (client.currentScreen == null) {
                    client.setScreen(new ModMenuScreen());
                }
            }
        });

        HudRenderCallback.EVENT.register((context, tickCounter) -> {
            MinecraftClient client = MinecraftClient.getInstance();
            if (client.options.hudHidden || client.getDebugHud().shouldShowDebugHud()) return;
            for (HudModule module : modules) {
                module.render(context, client);
            }
        });

        RendererLog.info("HUD registered: " + modules.size() + " modules, menu on Right Shift");
    }

    public List<HudModule> modules() {
        return modules;
    }

    // MARK: persistence (config/metalcraft-hud.json)

    private Path configFile() {
        return FabricLoader.getInstance().getConfigDir().resolve("metalcraft-hud.json");
    }

    public void save() {
        JsonObject root = new JsonObject();
        for (HudModule module : modules) {
            JsonObject m = new JsonObject();
            m.addProperty("enabled", module.isEnabled());
            m.addProperty("x", module.getX());
            m.addProperty("y", module.getY());
            root.add(module.id(), m);
        }
        try {
            Gson gson = new GsonBuilder().setPrettyPrinting().create();
            Files.createDirectories(configFile().getParent());
            Files.writeString(configFile(), gson.toJson(root));
        } catch (IOException e) {
            RendererLog.warn("Could not save HUD config: " + e.getMessage());
        }
    }

    private void load() {
        Path file = configFile();
        if (!Files.exists(file)) return;
        try {
            JsonObject root = new Gson().fromJson(Files.readString(file), JsonObject.class);
            for (HudModule module : modules) {
                if (root.has(module.id())) {
                    JsonObject m = root.getAsJsonObject(module.id());
                    if (m.has("enabled")) module.setEnabled(m.get("enabled").getAsBoolean());
                    if (m.has("x") && m.has("y")) module.setPosition(m.get("x").getAsInt(), m.get("y").getAsInt());
                }
            }
        } catch (Exception e) {
            RendererLog.warn("Could not load HUD config: " + e.getMessage());
        }
    }
}
