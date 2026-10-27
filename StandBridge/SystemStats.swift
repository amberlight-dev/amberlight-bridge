import Darwin
import Foundation
import IOKit.ps

@MainActor
enum SystemStats {
    private static var previousTicks: [UInt32]?
    private static var previousTraffic: (input: UInt32, output: UInt32, at: Date)?

    static func current() -> JSON {
        let memory = memoryUsage()
        let traffic = trafficRates()
        var stats: JSON = [
            "cpu": cpuLoad(),
            "memory": memory.used / memory.total,
            "memoryUsed": memory.used,
            "memoryTotal": memory.total,
            "pressure": pressureLevel(),
            "netIn": traffic.input,
            "netOut": traffic.output,
            "thermal": thermalState(),
        ]
        if let battery = battery() {
            stats["battery"] = battery.level
            stats["charging"] = battery.charging
        }
        return stats
    }

    static func cpuLoad() -> Double {
        guard let ticks = cpuTicks() else { return 0 }
        defer { previousTicks = ticks }
        guard let previousTicks else { return 0 }
        let delta = zip(ticks, previousTicks).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        let idle = delta[Int(CPU_STATE_IDLE)]
        return total > 0 ? min(max((total - idle) / total, 0), 1) : 0
    }

    static func memoryUsage() -> (used: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let pages = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return (min(pages * Double(getpagesize()), total), total)
    }

    static func pressureLevel() -> String {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return "normal" }
        switch level {
        case 4: return "critical"
        case 2: return "warn"
        default: return "normal"
        }
    }

    static func trafficRates() -> (input: Double, output: Double) {
        guard let totals = trafficTotals() else { return (0, 0) }
        let now = Date.now
        defer { previousTraffic = (totals.input, totals.output, now) }
        guard let previous = previousTraffic else { return (0, 0) }
        let seconds = now.timeIntervalSince(previous.at)
        guard seconds > 0 else { return (0, 0) }
        return (Double(totals.input &- previous.input) / seconds, Double(totals.output &- previous.output) / seconds)
    }

    private static func trafficTotals() -> (input: UInt32, output: UInt32)? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }
        var input: UInt32 = 0
        var output: UInt32 = 0
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  !String(cString: entry.ifa_name).hasPrefix("lo"),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
            input &+= data.ifi_ibytes
            output &+= data.ifi_obytes
        }
        return (input, output)
    }

    static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "nominal"
        }
    }

    private static func battery() -> (level: Double, charging: Bool)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return (Double(current) / Double(maximum), description[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return nil
    }

    private static func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return [ticks.0, ticks.1, ticks.2, ticks.3]
    }
}
