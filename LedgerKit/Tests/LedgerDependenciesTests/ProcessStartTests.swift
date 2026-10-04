import Foundation
import LedgerDependencies
import Testing

/// `ProcessStart`, where launch-to-first-frame begins (product decision #30).
@Suite("Process start")
struct ProcessStartTests {
    @Test("The kernel's start time for this process is in the past, and the same on every read")
    func processStart_isThisProcesses() throws {
        let start = try #require(ProcessStart.date())
        let now = Date()
        #expect(start <= now)
        #expect(now.timeIntervalSince(start) < 24 * 60 * 60, "this test process started \(start)")
        #expect(ProcessStart.date() == start)
    }

    /// A reference read of the same kernel field, kept whole: the start time keeps its microseconds, so the figure
    /// Diagnostics shows (#30) is not off by up to a second (F07 S3 adversarial V10).
    @Test("The start time keeps the kernel's microseconds")
    func processStart_keepsMicroseconds() throws {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        try #require(sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0)
        let kernel = info.kp_proc.p_un.__p_starttime
        let start = try #require(ProcessStart.date()).timeIntervalSince1970
        #expect(Int(start) == kernel.tv_sec)
        #expect(abs((start - Double(kernel.tv_sec)) * 1_000_000 - Double(kernel.tv_usec)) < 1, "\(start), \(kernel)")
    }
}
