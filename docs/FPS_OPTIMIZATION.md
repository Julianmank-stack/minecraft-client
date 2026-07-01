# FPS Optimization Center & Benchmark System

## Recommendation engine

At first run (and on demand) the launcher builds a `HardwareReport`:

- `sysctl hw.optional.arm64` → Apple Silicon vs Intel
- `MTLCreateSystemDefaultDevice()` → GPU name, `MTLGPUFamily` support, unified
  memory, `recommendedMaxWorkingSetSize`
- Physical RAM, performance/efficiency core counts
- macOS version

Rules (first match wins):

| Hardware | Recommended mode | Default preset |
|----------|------------------|----------------|
| Apple Silicon, Metal3, ≥16 GB | Apple Silicon Max FPS | Max FPS |
| Apple Silicon, Metal3, 8 GB | Apple Silicon Max FPS | Balanced |
| Apple Silicon (M1-era, non-Metal3) | Mac Optimized OpenGL | Balanced |
| Intel + discrete AMD GPU | Mac Optimized OpenGL | Balanced |
| Intel iGPU / <8 GB RAM | Low-End Mac Mode | Low-End |
| Shader pack detected in instance | Shader-Friendly Mode | Shader-Friendly |

The Experimental Metal Renderer is **never** auto-recommended; it is offered as an
opt-in card on compatible hardware.

## Presets → concrete settings

| Preset | RAM | GC | Engine config |
|--------|-----|----|----------------|
| Balanced | min(¼ RAM, 4 GB) | G1 tuned | Stage 1 (+Stage 2 on AS) |
| Max FPS | min(⅓ RAM, 8 GB) | ZGC | aggressive batching, frame pacing on |
| Low-End | 2 GB | G1 small-heap | conservative batching, reduced effects |
| Shader-Friendly | 6 GB | G1 tuned | state-elision only |
| Safe | 2 GB | JVM defaults | engine passive |

JVM argument sets are built by `OptimizationEngine.jvmArguments(for:)` — see
`Launcher/.../Optimization/OptimizationEngine.swift`. Users can override any of it
per instance; overrides are diffed against the preset so "Reset to preset" is exact.

## Benchmark system

- **Scenario**: launches the instance with `metalcraft.benchmark=true`; the engine
  mod loads a bundled flat benchmark world, runs a scripted 60s camera spiral
  (deterministic seed + fixed daytime), records per-frame times, writes
  `logs/renderer/benchmark-<ts>.json`, and exits.
- **Metrics**: avg FPS, 1% low FPS, avg/95p frame time, peak memory, chunk-update
  throughput.
- **Before/after**: the Optimization Center stores the last result per (instance,
  mode) and renders comparison bars. "Estimated improvement" (shown before any
  benchmark has run) comes from hardware-class lookup tables and is always labeled
  *estimated*; once a real benchmark exists, only measured numbers are shown.

## Live stats

While the game runs, the launcher samples (2 Hz):

- CPU% and RSS of the game process (`proc_pid_rusage`)
- System GPU utilization (IOKit performance statistics, best-effort)
- Frame-time stream from the engine mod via a local socket
  (`~/Library/Application Support/MetalCraft/run/<instance>.sock`), when the mod is
  present; otherwise stats degrade gracefully to process-level only.

Displayed as sparklines in the Optimization Center and a compact strip on the
dashboard while running.
