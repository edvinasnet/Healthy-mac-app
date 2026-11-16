import Darwin
import Observation
import SwiftUI

/// Samples HealthyMac's own CPU and memory use.
@MainActor
@Observable
final class SelfMonitor {
    /// Percent of one core, like Activity Monitor (can exceed 100 on multi-threaded work).
    private(set) var cpu: Double = 0
    /// Physical footprint in bytes — the "Memory" column in Activity Monitor.
    private(set) var memory: Int64 = 0

    private var lastCPUTime: Double?
    private var lastSample = Date()
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        sample()
        loop = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                sample()
            }
        }
    }

    private func sample() {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpuTime = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        let now = Date()
        let wall = now.timeIntervalSince(lastSample)
        if let last = lastCPUTime, wall > 0 {
            cpu = max(0, (cpuTime - last) / wall * 100)
        }
        lastCPUTime = cpuTime
        lastSample = now
        memory = Self.physicalFootprint()
    }

    static func physicalFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

struct SelfUsageFooter: View {
    let monitor: SelfMonitor

    var body: some View {
        HStack(spacing: 10) {
            Label(String(format: "%.1f%%", monitor.cpu), systemImage: "cpu")
                .foregroundStyle(monitor.cpu > 50 ? .orange : .secondary)
            Label(FileSize.format(monitor.memory), systemImage: "memorychip")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.caption.monospacedDigit())
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .help("HealthyMac's own CPU and memory use (updated every 2 s)")
        .task { monitor.start() }
    }
}
