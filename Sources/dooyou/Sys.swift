import Foundation
import Darwin

// System metrics that matter when running CLI AI: CPU load, memory, swap.
// CPU drives the running cat's speed (RunCat-style).
struct SysStats {
    var cpu = 0.0          // % busy (0-100)
    var memUsed = 0.0      // GB
    var memTotal = 0.0     // GB
    var memPct = 0.0       // %
    var swap = 0.0         // GB used
    var diskFreeGB = 0.0
    var netDownBytesPerSec = 0.0
    var netUpBytesPerSec = 0.0
}

private var prevTicks: host_cpu_load_info?
private var prevNetworkSample: (rx: UInt64, tx: UInt64, ts: Date)?

func sampleCPU() -> Double {
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    var info = host_cpu_load_info()
    let kr = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    defer { prevTicks = info }
    guard let p = prevTicks else { return 0 }
    let u = Double(info.cpu_ticks.0) - Double(p.cpu_ticks.0)   // user
    let s = Double(info.cpu_ticks.1) - Double(p.cpu_ticks.1)   // system
    let i = Double(info.cpu_ticks.2) - Double(p.cpu_ticks.2)   // idle
    let n = Double(info.cpu_ticks.3) - Double(p.cpu_ticks.3)   // nice
    let busy = u + s + n, total = busy + i
    return total > 0 ? min(100, max(0, busy / total * 100)) : 0
}

func sampleMemory() -> (used: Double, total: Double, pct: Double) {
    var total: UInt64 = 0; var sz = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &total, &sz, nil, 0)
    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &vm) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    let gb = 1_073_741_824.0
    guard kr == KERN_SUCCESS, total > 0 else { return (0, Double(total) / gb, 0) }
    let page = Double(vm_kernel_page_size)
    // ~ Activity Monitor "used" = app(active) + wired + compressed
    let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
    return (used / gb, Double(total) / gb, used / Double(total) * 100)
}

func sampleSwap() -> Double {
    var xsw = xsw_usage(); var sz = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &xsw, &sz, nil, 0) == 0 { return Double(xsw.xsu_used) / 1_073_741_824.0 }
    return 0
}

func sampleDiskFree() -> Double {
    var s = statfs()
    guard statfs(NSHomeDirectory(), &s) == 0 else { return 0 }
    return Double(s.f_bavail) * Double(s.f_bsize) / 1_073_741_824.0
}

func sampleNetwork() -> (down: Double, up: Double) {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
    defer { freeifaddrs(addrs) }
    var rx: UInt64 = 0
    var tx: UInt64 = 0
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let current = ptr {
        defer { ptr = current.pointee.ifa_next }
        let flags = Int32(current.pointee.ifa_flags)
        guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
        guard let data = current.pointee.ifa_data else { continue }
        let stats = data.assumingMemoryBound(to: if_data.self).pointee
        rx += UInt64(stats.ifi_ibytes)
        tx += UInt64(stats.ifi_obytes)
    }
    let now = Date()
    defer { prevNetworkSample = (rx, tx, now) }
    guard let prev = prevNetworkSample else { return (0, 0) }
    let dt = max(0.1, now.timeIntervalSince(prev.ts))
    return (Double(rx >= prev.rx ? rx - prev.rx : 0) / dt,
            Double(tx >= prev.tx ? tx - prev.tx : 0) / dt)
}

func sampleSys() -> SysStats {
    let m = sampleMemory()
    let n = sampleNetwork()
    return SysStats(cpu: sampleCPU(), memUsed: m.used, memTotal: m.total, memPct: m.pct,
                    swap: sampleSwap(), diskFreeGB: sampleDiskFree(),
                    netDownBytesPerSec: n.down, netUpBytesPerSec: n.up)
}
