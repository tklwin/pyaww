import Darwin

/// Process memory helpers for the Phase 3 benchmarks (SPEC §5.2).

/// `phys_footprint` — the number Activity Monitor shows as "Memory" (MB).
func currentFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return .nan }
    return Double(info.phys_footprint) / 1_048_576
}

/// Peak resident set size (macOS reports `ru_maxrss` in bytes).
func peakRSSMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
}
