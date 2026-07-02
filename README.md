# MetalCraft Launcher

A clean, modern **Minecraft Java launcher built exclusively for macOS** — with a custom
Mac-first rendering optimization system, **MetalCraft Engine**.

> Premium Mac feel. Native SwiftUI. Apple Silicon first. Honest performance engineering.

---

## What's in this repository

| Component | Path | Language | Purpose |
|-----------|------|----------|---------|
| **Launcher app** | `Launcher/` | Swift / SwiftUI | Native macOS launcher UI + core services |
| **MetalCraft Engine (mod)** | `MetalCraftEngine/` | Java (Fabric/Quilt) | In-game rendering optimization mod |
| **MetalCraft Native** | `MetalCraftNative/` | Swift + Metal | Native macOS Metal bridge (JNI dylib) |
| **Documentation** | `docs/` | Markdown | Architecture, flows, schema, renderer design |

## Feature overview

- **macOS-first launcher** — SwiftUI, translucent materials, rounded cards, keyboard
  shortcuts, light/dark mode, native notifications, Finder integration,
  `~/Library/Application Support/MetalCraft` storage, Keychain token storage.
- **Instances** — Vanilla, Fabric, Quilt, Forge, NeoForge; per-instance Java, RAM,
  JVM args, resolution, renderer mode, performance profile, mods/shaders/packs/saves.
- **Modrinth integration** — search, install, update modpacks; dependency resolution;
  `.mrpack` drag-and-drop import.
- **Prism Launcher import** — detect and import existing Prism instances
  (`instance.cfg` + `mmc-pack.json`), keeping them fully editable.
- **Microsoft account auth only** — OAuth 2.0 device-code flow → Xbox Live → XSTS →
  Minecraft Services. Works out of the box via Microsoft's public Xbox Live client
  (optional custom Azure app: [`docs/AZURE_APP_SETUP.md`](docs/AZURE_APP_SETUP.md)).
  Tokens live in the macOS Keychain. No cracked accounts, ever.
- **Real launch flow** — official Piston-Meta manifests, SHA-1 verified downloads of
  client jar / libraries / assets / natives, correct classpath and argument
  substitution, live logs, readable crash reports, Repair Instance.
- **FPS Optimization Center** — presets, before/after benchmarks, RAM & JVM tuning,
  renderer selection with hardware-based recommendations, live CPU/GPU/memory/frame-time.
- **Skin manager** — 2D/3D preview, upload via official Minecraft services API,
  slim/classic, local skin library, cape display.
- **Server manager** — Server List Ping (MOTD, players, latency, version), folders,
  Launch & Join, quick copy.

## MetalCraft Engine — the honest version

Minecraft Java renders through OpenGL (LWJGL). macOS caps OpenGL at 4.1 and its GL
driver is deprecated and slow. **No launcher can flip a switch and make vanilla
Minecraft render on Metal** — so we don't claim to. Instead, MetalCraft Engine is a
companion mod + native library with **staged, truthful levels of optimization**:

1. **Mac Optimized OpenGL** *(works today)* — macOS-tuned GL state management, JVM
   flags, buffer strategies, and frame pacing via `CVDisplayLink`-aligned present.
2. **Apple Silicon Max FPS** *(works today)* — unified-memory-aware buffer allocation,
   aggressive batching, reduced synchronization for M-series GPUs.
3. **Experimental Metal Renderer** *(experimental, staged)* — a native Metal backend
   that progressively takes over well-isolated subsystems (terrain/chunk rendering
   first) through a JNI bridge, compositing with the remaining GL pipeline via
   IOSurface sharing. Guarded by crash detection with automatic fallback to OpenGL.

Full design: [`docs/METALCRAFT_ENGINE.md`](docs/METALCRAFT_ENGINE.md).

## Rendering modes

| Mode | Availability | Description |
|------|--------------|-------------|
| Standard OpenGL | Always | Vanilla pipeline, untouched |
| Mac Optimized OpenGL | Always | macOS-tuned GL + JVM flags |
| Apple Silicon Max FPS | M-series only | Unified-memory optimizations |
| Low-End Mac Mode | Always | Reduced effects, low RAM footprint |
| Shader-Friendly Mode | Always | Compatible with Iris/shader packs |
| Experimental Metal Renderer | Compatible Macs only | Native Metal subsystem takeover, auto-fallback |
| Safe Mode | Always | Everything off; maximum compatibility |

## Installing as a Mac app

One command on your Mac (needs Xcode 15+ or Command Line Tools with Swift):

```bash
./scripts/package-app.sh --install
```

This builds the launcher in release mode, wraps it into **MetalCraft.app**
(ad-hoc signed, `.mrpack` files associated), and copies it into
`/Applications` — then just hit `⌘Space` and type "MetalCraft".
Omit `--install` to get `dist/MetalCraft.app` without installing.

## Building

### Launcher (requires macOS 14+, Xcode 15+)

```bash
cd Launcher
swift build            # or open Package.swift in Xcode and run
```

### MetalCraft Engine mod (requires JDK 21)

```bash
cd MetalCraftEngine
./gradlew build
```

### MetalCraft Native (requires macOS + Xcode CLT)

```bash
cd MetalCraftNative
swift build -c release   # produces libmetalcraft_native.dylib
```

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — full app architecture & folder structure
- [`docs/DATA_SCHEMA.md`](docs/DATA_SCHEMA.md) — on-disk data & schema design
- [`docs/UI_DESIGN.md`](docs/UI_DESIGN.md) — UI mockup descriptions & design language
- [`docs/AUTH_FLOW.md`](docs/AUTH_FLOW.md) — Microsoft → Xbox → Minecraft auth flow
- [`docs/LAUNCH_FLOW.md`](docs/LAUNCH_FLOW.md) — full game launch pipeline
- [`docs/MODRINTH_FLOW.md`](docs/MODRINTH_FLOW.md) — modpack search/install/update
- [`docs/PRISM_IMPORT.md`](docs/PRISM_IMPORT.md) — Prism Launcher import
- [`docs/METALCRAFT_ENGINE.md`](docs/METALCRAFT_ENGINE.md) — custom renderer design, fallback & crash handling
- [`docs/FPS_OPTIMIZATION.md`](docs/FPS_OPTIMIZATION.md) — optimization center & benchmark system

## Safety & legality

- Official Microsoft/Minecraft authentication only. No password storage, no auth bypass.
- Game files are downloaded **only** from Mojang's official servers
  (`piston-meta.mojang.com`, `libraries.minecraft.net`, `resources.download.minecraft.net`).
- Mods and modpacks come from Modrinth's official API; licenses and source links are
  shown before install.
- MetalCraft Engine is an original implementation — no code copied from existing
  renderer mods.
- Nothing from Mojang is redistributed in this repository.

## License

MIT for all code in this repository. Minecraft is a trademark of Mojang/Microsoft;
this project is not affiliated with or endorsed by them.
