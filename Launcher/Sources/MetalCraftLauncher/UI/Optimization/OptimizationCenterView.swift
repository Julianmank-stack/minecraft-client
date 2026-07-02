import SwiftUI

/// FPS Optimization Center: presets, renderer picker (with the experimental
/// Metal warning sheet), RAM/JVM tuning, and benchmark comparisons.
struct OptimizationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showMetalWarning = false
    @State private var pendingMode: RendererMode?

    var body: some View {
        if let instance = appState.selectedInstance {
            content(instance)
        } else {
            ContentUnavailableView(
                "No instance selected",
                systemImage: "bolt.slash",
                description: Text("Create or select an instance to optimize it.")
            )
        }
    }

    private func content(_ instance: Instance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(instance)
                presetRow(instance)
                thermalSection(instance)
                rendererPicker(instance)
                memorySection(instance)
                benchmarkSection(instance)
            }
            .padding(24)
        }
        .navigationTitle("FPS Optimization Center")
        .sheet(isPresented: $showMetalWarning) {
            MetalWarningSheet(
                onEnable: {
                    setMode(.metalExperimental, on: instance)
                    showMetalWarning = false
                },
                onUseOpenGL: {
                    setMode(appState.rendererManager.recommendedMode(), on: instance)
                    showMetalWarning = false
                }
            )
        }
    }

    private func header(_ instance: Instance) -> some View {
        GlassCard {
            HStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(instance.name).font(.headline)
                    Text("Recommended for this Mac: \(appState.rendererManager.recommendedMode().displayName)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(appState.hardware.gpuName) · \(appState.hardware.physicalMemoryMB / 1024) GB · \(appState.hardware.isAppleSilicon ? "Apple Silicon" : "Intel")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private func presetRow(_ instance: Instance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance preset").font(.headline)
            HStack(spacing: 10) {
                ForEach(PerformanceProfile.allCases) { profile in
                    let recommended = profile == appState.optimization.recommendedProfile()
                    Button {
                        var updated = appState.optimization.apply(
                            profile: profile, to: instance,
                            rendererManager: appState.rendererManager
                        )
                        // never silently enable experimental Metal via preset
                        if updated.renderer.mode == .metalExperimental {
                            updated.renderer.mode = .appleSiliconMax
                        }
                        persist(updated)
                    } label: {
                        VStack(spacing: 6) {
                            Text(profile.displayName)
                                .font(.callout.weight(.semibold))
                            if recommended {
                                Text("Recommended")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.2)))
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(instance.performanceProfile == profile
                                      ? Color.accentColor.opacity(0.18)
                                      : Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rendererPicker(_ instance: Instance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Renderer").font(.headline)
            VStack(spacing: 8) {
                ForEach(appState.rendererManager.availability(for: instance), id: \.mode) { availability in
                    // Experimental Metal only appears at all on compatible Macs
                    if availability.mode != .metalExperimental || appState.hardware.supportsExperimentalMetal {
                        rendererRow(availability, instance: instance)
                    }
                }
            }
        }
    }

    private func rendererRow(_ availability: RendererManager.ModeAvailability, instance: Instance) -> some View {
        let mode = availability.mode
        return Button {
            guard availability.available else { return }
            if mode == .metalExperimental {
                showMetalWarning = true
            } else {
                setMode(mode, on: instance)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: instance.renderer.mode == mode ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(instance.renderer.mode == mode ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.displayName).font(.callout.weight(.semibold))
                        if mode.isExperimental {
                            Label("Experimental", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.2)))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(availability.reason ?? mode.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if availability.available,
                   let estimate = appState.optimization.estimatedImprovement(for: mode) {
                    Text("est. +\(estimate.lowerBound)–\(estimate.upperBound)%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .opacity(availability.available ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    private func thermalSection(_ instance: Instance) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Heat & Frame Cap").font(.headline)
                    Spacer()
                    ThermalBadge(state: appState.thermalState)
                }

                Toggle("Cap frame rate", isOn: Binding(
                    get: { instance.fpsCap != nil },
                    set: { on in
                        var updated = instance
                        updated.fpsCap = on ? 165 : nil
                        persist(updated)
                    }
                ))

                if let cap = instance.fpsCap {
                    Picker("Max FPS", selection: Binding(
                        get: { cap },
                        set: { newValue in
                            var updated = instance
                            updated.fpsCap = newValue
                            persist(updated)
                        }
                    )) {
                        ForEach([60, 120, 144, 165, 240], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Thermal Guard — cap at 120 FPS when this Mac launches hot", isOn: Binding(
                    get: { instance.thermalGuard ?? true },
                    set: { on in
                        var updated = instance
                        updated.thermalGuard = on
                        persist(updated)
                    }
                ))

                Text("Uncapped Minecraft happily renders 500+ FPS — every frame past your display's refresh is pure heat. Once the chassis saturates, macOS throttles the whole chip and your 1% lows collapse. Capping near your refresh rate keeps the chip cool so performance stays consistent. Applied to options.txt at launch; Thermal Guard changes are restored automatically once the Mac cools down.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func memorySection(_ instance: Instance) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Memory & JVM").font(.headline)
                HStack {
                    Text("RAM allocation")
                    Slider(
                        value: Binding(
                            get: { Double(instance.memory.maxMB) },
                            set: { newValue in
                                var updated = instance
                                updated.memory.maxMB = Int(newValue / 512) * 512
                                persist(updated)
                            }
                        ),
                        in: 1024...Double(max(4096, appState.hardware.physicalMemoryMB / 2))
                    )
                    Text("\(instance.memory.maxMB / 1024) GB")
                        .font(.callout.monospacedDigit())
                        .frame(width: 50, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("JVM arguments").font(.callout)
                    TextField("JVM arguments", text: Binding(
                        get: { instance.jvmArgs.joined(separator: " ") },
                        set: { newValue in
                            var updated = instance
                            updated.jvmArgs = newValue.split(separator: " ").map(String.init)
                            persist(updated)
                        }
                    ), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                }
            }
        }
    }

    private func benchmarkSection(_ instance: Instance) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Benchmark").font(.headline)
                    Spacer()
                    Button("Run 60s Benchmark") {
                        // Runs a deterministic offline scene via the engine mod
                        // and stores measured before/after numbers.
                    }
                    .disabled(!instance.loader.type.supportsMetalCraftEngine)
                }
                Text(instance.loader.type.supportsMetalCraftEngine
                     ? "Runs a deterministic 60-second scene and records measured FPS, 1% lows and frame times. Estimates above are replaced by real numbers after the first run."
                     : "Benchmarking needs the MetalCraft Engine mod (Fabric or Quilt instances).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setMode(_ mode: RendererMode, on instance: Instance) {
        var updated = instance
        updated.renderer.mode = mode
        persist(updated)
    }

    private func persist(_ instance: Instance) {
        try? appState.instanceStore.save(instance)
        appState.instances = (try? appState.instanceStore.loadAll()) ?? []
        appState.selectedInstanceID = instance.id
    }
}

/// The honest warning sheet shown before enabling the experimental renderer.
struct MetalWarningSheet: View {
    let onEnable: () -> Void
    let onUseOpenGL: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Experimental Metal Renderer", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.orange)

            Text("""
            This renders **chunk terrain** with a native Metal backend while the rest of the game stays on OpenGL. It can improve FPS significantly on Apple Silicon, but it is experimental:

            • Visual glitches or crashes are possible.
            • After 2 crashes it disables itself automatically and falls back to OpenGL.
            • Renderer issues are logged separately (Logs → Renderer).
            • Not compatible with shader packs or Sodium-style renderer mods.
            """)
            .font(.callout)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Launch with OpenGL instead") { onUseOpenGL() }
                Button("Enable Experimental Renderer") { onEnable() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
