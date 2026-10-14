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

/// What VoiceOver is asked to say aloud about something that happened by itself: a rest that began, a rest
/// that ended (F10 S7). Posting one is ambient, so a store reaches it here and no feature posts its own.
public protocol AnnouncementsClient: Sendable {
    /// Asks the system to speak `text` once. It cannot fail: with no assistive technology running nothing
    /// is said.
    func announce(_ text: String) async
}

/// The Live Activity for elapsed and rest time on the Lock Screen and Dynamic Island (F21).
public protocol LiveActivitiesClient: Sendable {}
