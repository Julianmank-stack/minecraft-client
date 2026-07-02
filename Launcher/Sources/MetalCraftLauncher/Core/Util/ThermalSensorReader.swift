import Foundation

/// Reads real die temperatures from the SoC's hardware sensors.
///
/// macOS has no public API for temperatures, so this uses the private
/// `IOHIDEventSystemClient` sensor interface — the same unprivileged
/// mechanism used by Stats and macmon. All symbols are resolved at runtime
/// with `dlsym`, so if Apple removes or renames them this returns `nil`
/// and the UI falls back to `ProcessInfo.thermalState` alone.
///
/// Sensor naming (the HID service's "Product" property):
///   - Apple Silicon CPU: "pACC MTR Temp Sensor…" (P-cores),
///     "eACC MTR Temp Sensor…" (E-cores), "PMU tdie…" on M1-era chips
///   - Apple Silicon GPU: "GPU MTR Temp Sensor…"
final class ThermalSensorReader: @unchecked Sendable {
    struct Reading: Equatable {
        var cpuC: Double?       // hottest CPU die sensor
        var gpuC: Double?       // hottest GPU die sensor
        var hottestC: Double    // hottest plausible sensor anywhere on the SoC
    }

    // kIOHIDEventTypeTemperature and its field base from IOHIDEventTypes.h.
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias GetFloatFn = @convention(c) (CFTypeRef, Int32) -> Double

    private let clientCreate: ClientCreateFn?
    private let setMatching: SetMatchingFn?
    private let copyServices: CopyServicesFn?
    private let copyProperty: CopyPropertyFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?

    init() {
        let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        clientCreate = symbol("IOHIDEventSystemClientCreate", as: ClientCreateFn.self)
        setMatching = symbol("IOHIDEventSystemClientSetMatching", as: SetMatchingFn.self)
        copyServices = symbol("IOHIDEventSystemClientCopyServices", as: CopyServicesFn.self)
        copyProperty = symbol("IOHIDServiceClientCopyProperty", as: CopyPropertyFn.self)
        copyEvent = symbol("IOHIDServiceClientCopyEvent", as: CopyEventFn.self)
        getFloat = symbol("IOHIDEventGetFloatValue", as: GetFloatFn.self)
    }

    /// One synchronous sensor sweep (~1 ms). Returns nil when the private
    /// interface is unavailable or no plausible temperature sensor exists.
    func read() -> Reading? {
        guard let clientCreate, let setMatching, let copyServices,
              let copyProperty, let copyEvent, let getFloat,
              let client = clientCreate(kCFAllocatorDefault) else { return nil }
        // The client comes back +1 from a Create function; CFRelease is
        // unavailable in Swift, so release through Unmanaged.
        defer { Unmanaged<AnyObject>.fromOpaque(client).release() }

        // AppleVendor usage page, usage 5 = temperature sensors.
        let matching = [
            "PrimaryUsagePage": 0xff00,
            "PrimaryUsage": 5
        ] as CFDictionary
        setMatching(client, matching)

        guard let services = copyServices(client)?.takeRetainedValue() else { return nil }

        var cpu: Double?
        var gpu: Double?
        var hottest: Double?

        for index in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = UnsafeMutableRawPointer(mutating: raw)

            guard let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
            let value = getFloat(event, Self.temperatureField)
            // Discard nonsense (disconnected sensors report 0 or huge values).
            guard value > 5, value < 125 else { continue }

            let name = (copyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String) ?? ""

            if name.contains("pACC") || name.contains("eACC") || name.localizedCaseInsensitiveContains("tdie") {
                cpu = max(cpu ?? value, value)
            } else if name.contains("GPU") {
                gpu = max(gpu ?? value, value)
            }
            hottest = max(hottest ?? value, value)
        }

        guard let hottest else { return nil }
        return Reading(cpuC: cpu, gpuC: gpu, hottestC: hottest)
    }
}
