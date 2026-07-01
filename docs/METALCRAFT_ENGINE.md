# MetalCraft Engine — Custom macOS Rendering Optimization System

## Design goals

Minecraft Java renders through OpenGL via LWJGL. On macOS this is uniquely painful:

- OpenGL is capped at **4.1 core** and the driver has been deprecated since 2018.
- Apple's GL implementation serializes heavily and has expensive state validation.
- Vanilla's swap behavior fights the compositor, causing frame-pacing stutter.
- Vanilla buffer management ignores Apple Silicon's **unified memory** (it copies
  through staging paths designed for discrete GPUs).

MetalCraft Engine attacks these in **honest, staged levels**. It never claims to
"convert Minecraft to Metal" — it optimizes what can be optimized today and grows a
real Metal backend behind strict safety rails.

## Components

```
MetalCraftEngine (Java, Fabric/Quilt mod)
├── EngineConfig          reads metalcraft.json written by the launcher
├── BackendSelector       picks backend from config + hardware + crash history
├── OpenGLOptimizedBackend  Stage 1/2 optimizations (pure Java/LWJGL)
├── MetalBackend          Stage 3 — drives the native library via JNI
├── FramePacer            CVDisplayLink-aligned present timing
├── ChunkBatchPlanner     merged draw ranges, reduced rebind churn
├── CrashSentinel         startup handshake + crash counting
├── FallbackManager       automatic downgrade chain
└── RendererLog           separate renderer log stream (logs/renderer/)

libmetalcraft_native.dylib (Swift + Metal)
├── CBridge               @_cdecl C ABI (JNI-callable)
├── MetalDeviceInfo       GPU name, Apple/Intel, unified memory, family caps
├── FramePacer            CVDisplayLink; tells Java the ideal present deadline
├── TerrainRenderer       experimental Metal chunk-terrain pass
└── Shaders/Terrain.metal terrain vertex/fragment shaders
```

## Stage 1 — Mac Optimized OpenGL (ships first, pure Java)

Implementable entirely with Mixins + LWJGL calls; no native code required:

- **State-change elision**: shadow GL state in Java and skip redundant
  `glBindTexture`/`glUseProgram`/`glEnable` calls (Apple's driver validates each).
- **Buffer orphaning discipline**: replace `glBufferSubData` mid-frame updates with
  orphan + write patterns that avoid GPU/CPU sync stalls on Apple's driver.
- **Swap tuning**: control `glfwSwapInterval` dynamically; align buffer swaps with
  the display refresh via the native FramePacer when available.
- **JVM-side wins** (applied by the launcher, not the mod): ZGC/G1 tuning, larger
  code cache, `-Dsun.java2d.metal=true` for launcher-owned AWT surfaces.

## Stage 2 — Apple Silicon Max FPS

- **Unified-memory hints**: prefer `GL_STREAM_DRAW` + persistent client-side mirrors;
  avoid pixel-transfer round trips that exist only for discrete-GPU architectures.
- **Aggressive chunk batching**: `ChunkBatchPlanner` merges contiguous chunk draw
  ranges into fewer `glMultiDrawArrays` calls and sorts by render layer to minimize
  program/texture rebinds.
- **Entity batching**: group entities sharing texture + model buffers into
  instanced-style draws where the 4.1 feature set allows.
- **Texture atlas residency**: pin the block atlas and mipmap chain; avoid vanilla's
  per-frame anisotropy/param resets.

## Stage 3 — Experimental Metal Renderer

Full pipeline replacement is a multi-year effort, so the Metal backend takes over
**one well-isolated subsystem at a time**, starting with chunk terrain (the biggest
draw-call and fill-rate consumer):

1. Java intercepts terrain mesh uploads (post-meshing vertex data) via Mixin and
   hands buffers to the native layer over JNI (direct `ByteBuffer`s, zero-copy).
2. `TerrainRenderer` renders terrain into a Metal texture backed by an **IOSurface**.
3. The IOSurface is bound into the GL context as a texture rectangle
   (`CGLTexImageIOSurface2D`) and composited under the remaining GL passes
   (entities, particles, UI) with correct depth via a shared depth pre-pass.
4. Present is driven by the Metal layer's `CAMetalDisplayLink` timing, with GL
   drawing into the composition rather than owning the swap.

Why this is credible: IOSurface interop between GL and Metal is a supported,
documented macOS mechanism (it is how browsers composite WebGL). The risk is
concentrated in depth-coherency and translucency ordering — which is exactly why the
subsystem is gated as *experimental* with automatic fallback.

### Compatibility gate (all must pass)

- macOS 13+; Metal 3-capable GPU (`MTLGPUFamily.metal3` or Apple7+)
- Fabric or Quilt loader (Forge/NeoForge: Stage 1/2 only, planned later)
- No known-conflicting renderer mods present (Sodium/Embeddium detected → the Metal
  terrain takeover disables itself and logs why; Stage 1 state-elision remains)
- Shader packs (Iris) present → Metal terrain takeover disabled ("Shader-Friendly
  Mode" instead)

## Rendering modes → engine behavior

| Mode | Stage 1 | Stage 2 | Stage 3 | Notes |
|------|:-:|:-:|:-:|-------|
| Standard OpenGL | – | – | – | mod fully passive |
| Mac Optimized OpenGL | ✓ | – | – | default on Intel Macs |
| Apple Silicon Max FPS | ✓ | ✓ | – | default on M-series |
| Low-End Mac Mode | ✓ | partial | – | + reduced effects config |
| Shader-Friendly Mode | ✓ | safe subset | – | never touches shader pipelines |
| Experimental Metal Renderer | ✓ | ✓ | ✓ | gated, warned, auto-fallback |
| Safe Mode | – | – | – | mod passive + vanilla JVM args |

## Crash protection & automatic fallback

**Startup handshake.** The mod writes `logs/renderer/handshake.json` with
`{"state":"starting","mode":…}` before initializing a backend and rewrites it to
`"ok"` after the first 120 rendered frames. If the launcher finds a stale
`"starting"` handshake on next launch, that counts as a renderer crash even when no
JVM crash report exists (covers GPU hangs / SIGKILL).

**Crash counting.** Per-instance, per-mode counters live in `instance.json`
(`renderer.crashCounts`). Increment when: handshake stale, JVM exit code ≠ 0 with the
renderer active, or `hs_err_pid`/crash report mentions `libmetalcraft_native`,
`Metal`, or GL driver frames.

**Fallback chain.** After `maxCrashesBeforeFallback` (default 2):

```
metalExperimental → appleSiliconMax → macOptimizedGL → standardGL → safe
```

The launcher shows: *"The Experimental Metal Renderer crashed twice on this instance
and has been disabled. Now using Apple Silicon Max FPS. [Renderer log] [Re-enable]"*.
Re-enabling resets the counter but keeps history in the renderer log.

**In-game watchdog.** `CrashSentinel` wraps every native call; a native exception or
a >2s device-lost stall flushes `RendererLog`, tears down the Metal backend, and
switches to the GL path **live** without killing the game session.

**Separate renderer logs.** `logs/renderer/renderer-<timestamp>.log` — backend
decisions, capability report, per-mode timings, fallback events. The launcher's Logs
tab has a dedicated "Renderer" filter and these are attached to crash diagnoses.

## Honest-claims policy (UI copy rules)

- The Experimental Metal Renderer option only renders on compatible Macs, always
  carries the ⚠️ *Experimental* badge, and its enable sheet includes a
  **"Launch with OpenGL instead"** button.
- Benchmark numbers are always measured, never estimated, when shown as "improvement".
  Pre-benchmark, the UI shows *"estimated"* ranges clearly labeled as estimates
  derived from hardware class, not promises.
- No UI copy ever states that Minecraft "runs on Metal" — it states which subsystems
  do.
