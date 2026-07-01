# Architecture

## System overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                       MetalCraft Launcher (SwiftUI)                  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐  │
│  │Dashboard │ │Instances │ │ Modrinth │ │  Skins   │ │  Servers  │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └─────┬─────┘  │
│       └────────────┴───────────┬┴────────────┴─────────────┘        │
│                          AppState (ObservableObject)                 │
├──────────────────────────────────────────────────────────────────────┤
│                            Launcher Core                             │
│  AuthService · InstanceStore · ModrinthAPI · PrismImporter           │
│  LaunchEngine · JavaRuntimeManager · RendererManager                 │
│  OptimizationEngine · BenchmarkRunner · CrashAnalyzer                │
│  ServerPinger · SkinManager · KeychainStore · DownloadManager        │
├──────────────────────────────────────────────────────────────────────┤
│  macOS: Keychain · UserNotifications · NSWorkspace (Finder) · Metal  │
└──────────────────────────┬───────────────────────────────────────────┘
                           │ launches JVM, injects mod + dylib path
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Minecraft (Java, LWJGL/OpenGL)                    │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │              MetalCraft Engine (Fabric/Quilt mod)              │  │
│  │  BackendSelector · GLOptimizer · ChunkBatcher · FramePacer     │  │
│  │  CrashSentinel · FallbackManager · RendererLog                 │  │
│  │            │ JNI                                               │  │
│  │            ▼                                                   │  │
│  │  libmetalcraft_native.dylib (Swift + Metal)                    │  │
│  │  MetalDeviceInfo · MetalTerrainRenderer · IOSurface compositor │  │
│  └────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

## Layers

### 1. UI layer (`Launcher/Sources/MetalCraftLauncher/UI`)
Pure SwiftUI. No business logic; every view talks to `AppState` or a focused
`ObservableObject` view model. Materials (`.ultraThinMaterial`) for the sidebar,
rounded 12pt cards, spring animations, `⌘`-shortcuts throughout.

### 2. Launcher core (`Launcher/Sources/MetalCraftLauncher/Core`)
Async/await Swift services. Each service is a small, testable actor/class:

| Service | Responsibility |
|---------|----------------|
| `MicrosoftAuthService` | OAuth device-code → XBL → XSTS → Minecraft token → profile |
| `KeychainStore` | Token storage via Security.framework |
| `InstanceStore` | CRUD + JSON persistence of instances |
| `PrismImporter` | Parse `instance.cfg` / `mmc-pack.json`, copy content |
| `ModrinthAPI` | REST client for api.modrinth.com/v2 |
| `MrPackInstaller` | `.mrpack` extraction, file download, overrides |
| `VersionManifestService` | Piston-Meta manifests + version JSON |
| `DownloadManager` | Concurrent, SHA-1-verified downloads with progress |
| `JavaRuntimeManager` | Detect installed JDKs, pick per-MC-version major, download Temurin (aarch64/x64) |
| `LaunchEngine` | Classpath, arg substitution, natives extraction, `Process` spawn, live logs |
| `RendererManager` | Hardware detection, mode availability, crash-count gating |
| `OptimizationEngine` | Presets → JVM args + engine config + recommendations |
| `BenchmarkRunner` | Scripted benchmark launches, frame-time capture, before/after |
| `CrashAnalyzer` | Parse crash reports/logs into readable diagnoses |
| `ServerPinger` | Modern Server List Ping over `Network.framework` |
| `SkinManager` | Minecraft services skin API, local library, 3D preview data |

### 3. Companion mod (`MetalCraftEngine/`)
Fabric mod (Quilt-compatible) targeting supported Minecraft versions. Loads the
launcher-provided config (`metalcraft.json` in the instance dir), applies the selected
rendering mode, and hosts the JNI bridge to the native layer. Original code only.

### 4. Native layer (`MetalCraftNative/`)
Swift package producing `libmetalcraft_native.dylib`. Exposes a C ABI (JNI-callable)
for GPU capability queries, Metal device management, the experimental terrain
renderer, and CVDisplayLink-based frame pacing.

## Folder structure

```
minecraft-client/
├── README.md, LICENSE, .gitignore
├── docs/                          # design documents (this folder)
├── Launcher/                      # SwiftUI macOS app (Swift Package)
│   ├── Package.swift
│   └── Sources/MetalCraftLauncher/
│       ├── MetalCraftLauncherApp.swift
│       ├── AppState.swift
│       ├── UI/
│       │   ├── RootView.swift, SidebarView.swift
│       │   ├── Dashboard/DashboardView.swift
│       │   ├── Login/LoginView.swift
│       │   ├── Instances/{InstancesView,InstanceDetailView}.swift
│       │   ├── Modrinth/ModrinthBrowserView.swift
│       │   ├── Optimization/OptimizationCenterView.swift
│       │   ├── Skins/SkinManagerView.swift
│       │   ├── Servers/ServerManagerView.swift
│       │   ├── Logs/LogsView.swift
│       │   └── Components/{GlassCard,PlayButton,StatBadge}.swift
│       └── Core/
│           ├── Auth/{MicrosoftAuthService,KeychainStore,MinecraftAccount}.swift
│           ├── Instances/{Instance,InstanceStore,PrismImporter}.swift
│           ├── Launch/{VersionManifest,DownloadManager,JavaRuntimeManager,LaunchEngine}.swift
│           ├── Modrinth/{ModrinthAPI,MrPackInstaller}.swift
│           ├── Renderer/{RendererMode,RendererManager,GPUCapabilities}.swift
│           ├── Optimization/{OptimizationEngine,BenchmarkRunner}.swift
│           ├── Servers/{ServerEntry,ServerPinger}.swift
│           ├── Skins/SkinManager.swift
│           ├── Crash/CrashAnalyzer.swift
│           └── Util/{Paths,Notifier}.swift
├── MetalCraftEngine/              # Java companion mod
│   ├── build.gradle, settings.gradle, gradle.properties
│   └── src/main/
│       ├── java/dev/metalcraft/engine/
│       │   ├── MetalCraftMod.java
│       │   ├── config/EngineConfig.java
│       │   ├── backend/{RenderBackend,BackendSelector,OpenGLOptimizedBackend,MetalBackend}.java
│       │   ├── bridge/MetalNative.java
│       │   ├── perf/{FramePacer,ChunkBatchPlanner}.java
│       │   ├── safety/{CrashSentinel,FallbackManager,RendererLog}.java
│       │   └── mixin/{MixinWindowSwap,MixinChunkUpload}.java
│       └── resources/{fabric.mod.json,metalcraft.mixins.json}
└── MetalCraftNative/              # Swift + Metal dylib
    ├── Package.swift
    └── Sources/MetalCraftNative/
        ├── CBridge.swift          # @_cdecl C ABI for JNI
        ├── MetalDeviceInfo.swift
        ├── FramePacer.swift
        ├── TerrainRenderer.swift
        └── Shaders/Terrain.metal
```

## Data storage (macOS conventions)

Everything lives under `~/Library/Application Support/MetalCraft/`:

```
MetalCraft/
├── launcher.json              # global settings
├── accounts.json              # account metadata (tokens are in Keychain)
├── instances/<uuid>/          # one folder per instance
│   ├── instance.json          # instance config (see DATA_SCHEMA.md)
│   ├── metalcraft.json        # renderer/engine config read by the mod
│   ├── .minecraft/            # game dir (mods, saves, resourcepacks, …)
│   └── logs/renderer/         # separate renderer logs
├── meta/                      # cached manifests & version JSONs
├── libraries/                 # shared library store (Maven layout)
├── assets/                    # shared assets (objects/ + indexes/)
├── java/                      # managed Temurin runtimes
├── skins/                     # local skin library
└── servers.json               # server manager data
```

Shared `libraries/` and `assets/` are hard-linked/classpathed into instances rather
than copied — the same strategy Prism uses — keeping disk usage low.

## Concurrency & error model

- All I/O is `async/await`; downloads run in a `TaskGroup` with limited width (6).
- Services throw typed errors (`AuthError`, `LaunchError`, `ModrinthError`) which the
  UI maps to human-readable alerts with recovery actions ("Repair Instance",
  "Switch to OpenGL", "Retry").
- The launched game process is supervised by `LaunchEngine`; exit codes + log tail
  feed `CrashAnalyzer`, and renderer-related crashes increment the per-mode crash
  counter used by the automatic fallback system.
