package dev.metalcraft.engine.hud;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.text.Text;

/**
 * The Right-Shift box menu.
 *
 * <p>A centered translucent panel listing every HUD module with an ON/OFF
 * toggle. While the menu is open the live HUD boxes stay visible and can be
 * dragged with the mouse to reposition them. Closing the menu (Esc or Right
 * Shift again) saves toggle state and positions.
 */
public final class ModMenuScreen extends Screen {

    private static final int PANEL_WIDTH = 220;
    private static final int ROW_HEIGHT = 26;

    private HudModule dragging;
    private int dragOffsetX;
    private int dragOffsetY;

    public ModMenuScreen() {
        super(Text.literal("MetalCraft Mods"));
    }

    @Override
    protected void init() {
        var modules = HudManager.INSTANCE.modules();
        int panelX = (width - PANEL_WIDTH) / 2;
        int panelY = panelTop();

        int row = 0;
        for (HudModule module : modules) {
            final HudModule m = module;
            addDrawableChild(ButtonWidget.builder(toggleLabel(m), button -> {
                        m.toggle();
                        button.setMessage(toggleLabel(m));
                    })
                    .dimensions(panelX + PANEL_WIDTH - 58, panelY + 34 + row * ROW_HEIGHT, 48, 20)
                    .build());
            row++;
        }

        addDrawableChild(ButtonWidget.builder(Text.literal("Done"), button -> close())
                .dimensions(panelX + (PANEL_WIDTH - 60) / 2, panelY + 40 + row * ROW_HEIGHT, 60, 20)
                .build());
    }

    private static Text toggleLabel(HudModule module) {
        return Text.literal(module.isEnabled() ? "§aON" : "§7OFF");
    }

    private int panelTop() {
        int rows = HudManager.INSTANCE.modules().size();
        return (height - (74 + rows * ROW_HEIGHT)) / 2;
    }

    @Override
    public void render(DrawContext context, int mouseX, int mouseY, float delta) {
        var modules = HudManager.INSTANCE.modules();
        int rows = modules.size();
        int panelX = (width - PANEL_WIDTH) / 2;
        int panelY = panelTop();
        int panelHeight = 74 + rows * ROW_HEIGHT;

        // Dim world, then the box panel with an accent header strip
        context.fill(0, 0, width, height, 0x66000000);
        context.fill(panelX, panelY, panelX + PANEL_WIDTH, panelY + panelHeight, 0xE016161C);
        context.fill(panelX, panelY, panelX + PANEL_WIDTH, panelY + 3, 0xFF4C8DFF);

        context.drawCenteredTextWithShadow(textRenderer, "MetalCraft Mods",
                panelX + PANEL_WIDTH / 2, panelY + 12, 0xFFFFFFFF);

        int row = 0;
        for (HudModule module : modules) {
            context.drawTextWithShadow(textRenderer, module.displayName(),
                    panelX + 12, panelY + 40 + row * ROW_HEIGHT, 0xFFE0E0E0);
            row++;
        }

        context.drawCenteredTextWithShadow(textRenderer, "§7Drag the boxes to move them",
                panelX + PANEL_WIDTH / 2, panelY + panelHeight - 14, 0xFF808080);

        super.render(context, mouseX, mouseY, delta);

        // Live previews of every module so positions can be adjusted visually
        MinecraftClient client = MinecraftClient.getInstance();
        for (HudModule module : modules) {
            if (module.isEnabled()) {
                module.render(context, client);
            }
        }
    }

    // MARK: dragging HUD boxes

    @Override
    public boolean mouseClicked(double mouseX, double mouseY, int button) {
        if (button == 0) {
            MinecraftClient client = MinecraftClient.getInstance();
            for (HudModule module : HudManager.INSTANCE.modules()) {
                if (module.isEnabled()
                        && mouseX >= module.getX() && mouseX <= module.getX() + module.boxWidth(client)
                        && mouseY >= module.getY() && mouseY <= module.getY() + module.boxHeight(client)) {
                    dragging = module;
                    dragOffsetX = (int) mouseX - module.getX();
                    dragOffsetY = (int) mouseY - module.getY();
                    return true;
                }
            }
        }
        return super.mouseClicked(mouseX, mouseY, button);
    }

    @Override
    public boolean mouseDragged(double mouseX, double mouseY, int button, double deltaX, double deltaY) {
        if (dragging != null && button == 0) {
            int x = Math.max(0, Math.min((int) mouseX - dragOffsetX, width - 20));
            int y = Math.max(0, Math.min((int) mouseY - dragOffsetY, height - 12));
            dragging.setPosition(x, y);
            return true;
        }
        return super.mouseDragged(mouseX, mouseY, button, deltaX, deltaY);
    }

    @Override
    public boolean mouseReleased(double mouseX, double mouseY, int button) {
        if (dragging != null && button == 0) {
            dragging = null;
            return true;
        }
        return super.mouseReleased(mouseX, mouseY, button);
    }

    @Override
    public boolean keyPressed(int keyCode, int scanCode, int modifiers) {
        if (keyCode == org.lwjgl.glfw.GLFW.GLFW_KEY_RIGHT_SHIFT) {
            close();
            return true;
        }
        return super.keyPressed(keyCode, scanCode, modifiers);
    }

    @Override
    public void close() {
        HudManager.INSTANCE.save();
        super.close();
    }

    @Override
    public boolean shouldPause() {
        return false;
    }
}
