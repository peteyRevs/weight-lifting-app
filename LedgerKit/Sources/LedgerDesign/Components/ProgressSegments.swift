import SwiftUI

/// One exercise's share of ``ProgressSegments``.
public nonisolated struct ProgressSegment: Equatable, Sendable {
    public nonisolated enum State: Sendable {
        case done, current, upcoming
    }

    /// The segment's share of the bar, relative to the others (the exercise's set count). Zero or
    /// less draws nothing and takes no gap, as if the segment were not there.
    public let length: Int
    public let state: State

    public init(length: Int, state: State) {
        self.length = length
        self.state = state
    }
}

/// A workout's progress as one thin bar per exercise (v2 Active workout): each segment as long as its
/// share of the sets, grey once done, orange for the current one, a faint track for the rest.
///
/// The bar draws no text, so `label` and `value` are what VoiceOver reads ("Workout progress",
/// "Exercise 2 of 5"); both are required. Show the same progress in words on screen too: the track
/// is as faint as the prototype's, below WCAG 1.4.11's 3:1, as the rest ring's is, so the words carry
/// the count. The done and current segments reach 3:1 on the ground.
public struct ProgressSegments: View {
    /// The prototype's 2 px bar and 3 px gaps.
    nonisolated static let height: CGFloat = 2
    nonisolated static let gap: CGFloat = 3

    private let segments: [ProgressSegment]
    private let label: String
    private let value: String

    public init(_ segments: [ProgressSegment], label: String, value: String) {
        self.segments = segments
        self.label = label
        self.value = value
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = Self.widths(of: segments, in: proxy.size.width)
            HStack(spacing: Self.gap) {
                ForEach(segments.indices.filter { segments[$0].length > 0 }, id: \.self) { index in
                    Rectangle().fill(color(segments[index].state)).frame(width: widths[index])
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: value))
    }

    /// Each segment's width: `total` less the gaps between the segments drawn, shared in proportion to
    /// the lengths. A segment of zero or less gets 0 and no gap.
    nonisolated static func widths(of segments: [ProgressSegment], in total: CGFloat) -> [CGFloat] {
        let lengths = segments.map { CGFloat(max($0.length, 0)) }
        let drawn = lengths.count { $0 > 0 }
        let sum = lengths.reduce(0, +)
        let available = max(total - gap * CGFloat(max(drawn - 1, 0)), 0)
        return lengths.map { sum > 0 ? available * $0 / sum : 0 }
    }

    private func color(_ state: ProgressSegment.State) -> Color {
        switch state {
        case .done: LedgerColor.inkMuted // the prototype's .5
        case .current: LedgerColor.accentText // the orange that reads on paper too
        case .upcoming: LedgerColor.hairlineStrong // the prototype's .12 track
        }
    }
}

/// The start, the middle and the end of v2's five-exercise workout, for the preview, the snapshot
/// tests and the gallery.
struct ProgressSegmentsGallery: View {
    static let lengths = [5, 3, 4, 3, 3]

    var body: some View {
        VStack(spacing: LedgerSpacing.xl) {
            ForEach([0, 2, 4], id: \.self) { current in
                ProgressSegments(
                    Self.workout(current: current),
                    label: "Workout progress",
                    value: "Exercise \(current + 1) of 5"
                )
            }
        }
    }

    static func workout(current: Int) -> [ProgressSegment] {
        lengths.enumerated().map { index, length in
            ProgressSegment(
                length: length,
                state: index < current ? .done : index == current ? .current : .upcoming
            )
        }
    }
}
