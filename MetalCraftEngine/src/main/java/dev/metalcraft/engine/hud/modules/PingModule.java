package dev.metalcraft.engine.hud.modules;

import dev.metalcraft.engine.hud.HudModule;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.PlayerListEntry;

public final class PingModule extends HudModule {

    public PingModule() {
        super("ping", "Ping", true, 6, 26);
    }

    @Override
    public String text(MinecraftClient client) {
        if (client.player != null && client.getNetworkHandler() != null) {
            PlayerListEntry entry = client.getNetworkHandler().getPlayerListEntry(client.player.getUuid());
            if (entry != null && entry.getLatency() > 0) {
                return "Ping: " + entry.getLatency() + " ms";
            }
        }
        return "Ping: —"; // singleplayer / not connected
    }
}
