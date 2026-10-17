import Foundation

// The device clients a store reaches through `@Dependency` (architecture §13; F07). Shape only, like
// `HealthStore`: the brief that first needs one adds its methods, and its live implementation.
// `Sendable`, so a nonisolated dependency key can hold one and a `@MainActor` store can call it.

/// Haptic feedback: the engine's `.haptic` effects, played by the workout stores (F10, F18).
public protocol HapticsClient: Sendable {
    /// Plays `haptic` once. It cannot fail: a device that cannot play it plays nothing.
    func play(_ haptic: Haptic) async
}

/// Local notifications: the rest-over alert while the phone app is in the background (F10 schedules it, F23
/// implements it). The session's host calls it, not a screen: a rest also starts and ends with no screen up.
public protocol NotificationsClient: Sendable {
    /// Schedules the rest-over notification for `endsAt`, in place of any that was scheduled: there is at
    /// most one.
    func scheduleRestOver(at endsAt: Date) async
    /// Takes back the scheduled rest-over notification, if there is one.
    func cancelRestOver() async
}

/// The Live Activity for elapsed and rest time on the Lock Screen and Dynamic Island (F21).
public protocol LiveActivitiesClient: Sendable {}
