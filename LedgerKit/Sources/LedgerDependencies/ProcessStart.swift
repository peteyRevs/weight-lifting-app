import Foundation

/// When the kernel started this process: where launch-to-first-frame begins (product decision #30), which the
/// composition roots measure and Debug's Diagnostics screen shows.
public enum ProcessStart {
    /// The process's start time as the kernel recorded it (`sysctl` `KERN_PROC_PID`), or nil if it cannot say.
    public static func date() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
