# Data & Schema Design

All persistent launcher data is JSON on disk (versioned with `schemaVersion`), stored
under `~/Library/Application Support/MetalCraft/`. Secrets never touch these files —
they live in the macOS Keychain.

## `launcher.json` — global settings

```json
{
  "schemaVersion": 1,
  "theme": "system",
  "accentSource": "instanceIcon",
  "defaultRamMB": 4096,
  "concurrentDownloads": 6,
  "notifications": { "launchReady": true, "crashAlerts": true, "updateAvailable": true },
  "selectedInstance": "6f1c9f5e-...",
  "selectedAccount": "d3adb33f-..."
}
```

## `accounts.json` — account metadata (no secrets)

```json
{
  "schemaVersion": 1,
  "accounts": [
    {
      "id": "d3adb33f-...",
      "username": "PlayerName",
      "uuid": "069a79f4-44e9-4726-a5be-fca90e38aaf5",
      "skinURL": "https://textures.minecraft.net/texture/…",
      "skinModel": "classic",
      "capeURL": null,
      "lastRefresh": "2026-07-01T12:00:00Z"
    }
  ]
}
```

Keychain items (service `dev.metalcraft.launcher`):

| Account | Item | Contents |
|---------|------|----------|
| `<uuid>.msa` | MSA refresh token | opaque string |
| `<uuid>.mc`  | Minecraft access token + expiry | JSON blob |

## `instances/<uuid>/instance.json`

```json
{
  "schemaVersion": 1,
  "id": "6f1c9f5e-...",
  "name": "Fabric 1.21.4 Performance",
  "icon": "grass_block",
  "created": "2026-07-01T12:00:00Z",
  "lastPlayed": "2026-07-01T18:30:00Z",
  "totalPlayTimeSeconds": 86400,
  "minecraftVersion": "1.21.4",
  "loader": { "type": "fabric", "version": "0.16.9" },
  "java": { "path": null, "majorOverride": null },
  "memory": { "minMB": 1024, "maxMB": 6144 },
  "jvmArgs": ["-XX:+UseZGC"],
  "resolution": { "width": 1920, "height": 1080, "fullscreen": false },
  "renderer": { "mode": "macOptimizedGL", "crashCounts": { "metalExperimental": 0 } },
  "performanceProfile": "balanced",
  "modrinth": { "projectId": null, "versionId": null },
  "importedFrom": null,
  "notes": ""
}
```

- `loader.type` ∈ `vanilla | fabric | quilt | forge | neoforge`
- `renderer.mode` ∈ `standardGL | macOptimizedGL | appleSiliconMax | lowEnd | shaderFriendly | metalExperimental | safe`
- `importedFrom` records `{ "launcher": "prism", "path": "...", "date": "..." }` for
  Prism imports.
- Mods/shaders/resource packs/saves/screenshots are **not** duplicated in JSON — the
  filesystem inside `.minecraft/` is the source of truth; the launcher indexes it at
  view time and caches metadata in `.minecraft/.metalcraft-modindex.json`.

## `instances/<uuid>/metalcraft.json` — read by the mod at runtime

```json
{
  "schemaVersion": 1,
  "mode": "macOptimizedGL",
  "framePacing": true,
  "unifiedMemoryHints": true,
  "chunkBatching": "aggressive",
  "metal": { "enabled": false, "terrainTakeover": false },
  "safety": { "maxCrashesBeforeFallback": 2, "rendererLogDir": "logs/renderer" }
}
```

## `servers.json`

```json
{
  "schemaVersion": 1,
  "folders": [
    { "id": "f1", "name": "Friends" }
  ],
  "servers": [
    {
      "id": "s1",
      "folderId": "f1",
      "name": "Hypixel",
      "address": "mc.hypixel.net",
      "port": 25565,
      "notes": "",
      "iconBase64": null,
      "preferredInstance": "6f1c9f5e-..."
    }
  ]
}
```

Ping results (MOTD, players, latency, version) are runtime-only, never persisted.

## `skins/library.json`

```json
{
  "schemaVersion": 1,
  "skins": [
    { "id": "sk1", "name": "Summer", "file": "sk1.png", "model": "slim", "added": "2026-07-01T12:00:00Z" }
  ]
}
```

## Cached metadata (`meta/`)

- `version_manifest_v2.json` (24h TTL)
- `versions/<id>.json` — pinned per version, immutable
- `java_runtimes.json` — detected JDK inventory (invalidated on filesystem change)
- `benchmarks/<instance>/<timestamp>.json` — benchmark results:

```json
{
  "instance": "6f1c9f5e-...",
  "date": "2026-07-01T18:00:00Z",
  "mode": "appleSiliconMax",
  "durationSeconds": 60,
  "avgFPS": 187.2,
  "onePercentLowFPS": 121.0,
  "avgFrameTimeMs": 5.34,
  "maxMemoryMB": 3821,
  "scene": "vanilla-world-spiral"
}
```

## Migration policy

Every file carries `schemaVersion`. Loaders migrate forward in place and keep a
`.bak` of the pre-migration file. Unknown keys are preserved on rewrite (decode into
dictionaries where forward-compat matters).
