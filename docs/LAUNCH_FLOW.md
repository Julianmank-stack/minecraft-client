# Minecraft Launch Flow

All game files come **only from official Mojang sources**. Nothing is redistributed.

## Pipeline

```
Play pressed
  1. Auth check          → refresh Minecraft token if expiring (see AUTH_FLOW.md)
  2. Version resolve     → version_manifest_v2.json (piston-meta.mojang.com, 24h cache)
                           → versions/<id>.json (pinned, immutable cache)
                           → loader profile merge (Fabric/Quilt/Forge/NeoForge JSON)
  3. Java resolve        → version JSON's javaVersion.majorVersion
                           → JavaRuntimeManager picks matching runtime
                             (aarch64-native Temurin on Apple Silicon; x64 on Intel;
                              downloads from Adoptium API if missing)
  4. Download & verify   → client.jar, libraries (rules-filtered: os.name == "osx",
                           arch), natives, asset index + objects
                           → every file SHA-1 checked; existing valid files skipped
                           → 6-wide concurrent TaskGroup with progress reporting
  5. Natives extraction  → macOS natives (*.dylib) into instance natives dir
  6. Renderer prep       → write metalcraft.json for the selected mode
                           → ensure MetalCraft Engine mod + dylib present when the
                             mode requires them (Fabric/Quilt only)
  7. Classpath build     → shared libraries/ store (Maven layout) + client.jar
  8. Argument build      → JVM args: memory, GC tuning per performance profile,
                           -XstartOnFirstThread (required on macOS!),
                           -Djava.library.path=<natives>,
                           -Dmetalcraft.native=<dylib path> when Metal mode
                           → game args from version JSON with ${...} substitution
                             (auth_player_name, auth_uuid, auth_access_token,
                              game_directory, assets_root, assets_index_name,
                              resolution — user rules honored)
  9. Spawn               → Foundation Process, cwd = instance/.minecraft
                           → stdout/stderr piped line-by-line into the live log view
 10. Supervise           → exit code 0: update play time, done
                           → nonzero: CrashAnalyzer runs (see below)
```

## Checksums & repair

- SHA-1 from the version JSON verifies client jar, every library, every asset object.
- **Repair Instance** re-walks steps 2–5 with `force = true`: re-verifies every file,
  re-downloads mismatches, re-extracts natives, rewrites `metalcraft.json`.

## Crash handling

`CrashAnalyzer` inspects (in order): `crash-reports/crash-*.txt`, `hs_err_pid*.log`,
last 200 lines of `latest.log`, and `logs/renderer/*`. It produces a readable
diagnosis card:

| Signature | Diagnosis shown | Suggested action |
|-----------|-----------------|------------------|
| `OutOfMemoryError` | "Ran out of memory (X MB allocated)" | Raise RAM slider |
| Missing mod dependency (loader message) | "Mod X requires Y" | Install Y (Modrinth link) |
| `UnsupportedClassVersionError` | "Wrong Java version" | Auto-switch Java |
| `libmetalcraft_native` / Metal frames | "Renderer crash" | Auto-fallback + renderer log |
| GLFW / `-XstartOnFirstThread` missing | "macOS threading flag missing" | Auto-fix & relaunch |
| Unknown | Raw report, prettified | Open logs / Repair |

Renderer-attributed crashes also increment the per-mode crash counter that drives
the automatic fallback chain (see METALCRAFT_ENGINE.md).
