import Foundation

/// What goes between the phone and the watch during a live workout, over any live transport (F17; ADR-005 §3).
/// `WireCodec` turns a frame into bytes and back.
///
/// The two devices keep one symmetric log per workout (ADR-004), so every frame is about envelopes: some to
/// store, or what the sender already holds, so the receiver can send what is missing.
public enum WireFrame: Hashable, Codable, Sendable {
    /// Envelopes to store, from any device: the sender's own, or ones it relays (a gap replay sends every
    /// envelope the peer lacks, whoever made it). The receiver appends them before it rebuilds, whatever they
    /// hold (ADR-004, "The host loop").
    case envelopes([EventEnvelope])
    /// What the sender holds of `workoutID`'s log, sent on every link-up and after a launch that resumed the
    /// workout. For each device, `contiguousSeq` is the highest `n` such that the sender holds that device's
    /// envelopes `1 ... n`, so a lost envelope below a received one is still replayed (F17 "Inputs from F04",
    /// item 4). A device the sender holds nothing of is absent. The receiver replies with every envelope of its
    /// own that the vector does not cover, then with its own handshake.
    case handshake(workoutID: WorkoutID, contiguousSeq: [DeviceID: UInt64])
    /// The same vector as a handshake, asking for what it does not cover without a handshake in reply: the
    /// explicit form, sent after a frame could not be read.
    case replayRequest(workoutID: WorkoutID, contiguousSeq: [DeviceID: UInt64])
}
