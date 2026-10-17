#if os(iOS) && DEBUG
    @testable import FeatureProgram
    import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing
    import UIKit

    /// One way the phone can be set, for the F11 S9 adversarial suites (gate G2, round 1): a text size, the
    /// width of the page, Bold Text, and the direction of the layout.
    nonisolated struct ViewsSetting: Sendable, CustomTestStringConvertible {
        var size: DynamicTypeSize = .large
        var width: CGFloat = SnapshotConfig.phoneWidth
        var isBold = false
        var isRightToLeft = false

        /// The narrower of the two phones.
        static let narrowWidth: CGFloat = 375

        /// The widths swept: an iPhone 17's, and a 375 pt phone's.
        static let widths: [CGFloat] = [SnapshotConfig.phoneWidth, narrowWidth]

        var testDescription: String {
            "\(size), \(Int(width)) pt" + (isBold ? ", Bold Text" : "") + (isRightToLeft ? ", right to left" : "")
        }

        /// A size on both widths, each plain, with Bold Text, and right to left. On the hosted PR runner
        /// (`TestSweep`) three of the six: the iPhone 17 plain, and the 375 pt phone with Bold Text and right
        /// to left.
        static func sweep(_ size: DynamicTypeSize) -> [ViewsSetting] {
            let all = widths.flatMap { width in
                [
                    ViewsSetting(size: size, width: width),
                    ViewsSetting(size: size, width: width, isBold: true),
                    ViewsSetting(size: size, width: width, isRightToLeft: true)
                ]
            }
            return TestSweep.subset(all) { setting in
                setting.width == narrowWidth
                    ? setting.isBold || setting.isRightToLeft
                    : !setting.isBold && !setting.isRightToLeft
            }
        }
    }

    /// Hosting and measuring, shared by the F11 S9 adversarial suites. Nothing here reads a reference image:
    /// every check is a measurement of the hosted view.
    enum ProgramViewsProbe {
        /// The stops of `view` with their frames, the view laid out `setting.width` wide; or, `atItsOwnWidth`,
        /// as wide as it asks to be when nothing limits it, every line of text on one line.
        static func placed(_ view: some View, _ setting: ViewsSetting, atItsOwnWidth: Bool = false) -> [PlacedStop] {
            let sized = atItsOwnWidth
                ? AnyView(view.fixedSize(horizontal: true, vertical: false))
                : AnyView(view.frame(width: setting.width))
            return sized
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
                .environment(\.layoutDirection, setting.isRightToLeft ? .rightToLeft : .leftToRight)
                .placedStops(SnapshotAppearance(.light, setting.size))
        }

        /// The stops of `page` that were given less width than they take alone, and are no taller for it: what
        /// such a stop draws is cut short or shrunk inside its frame, which no frame on the page shows by
        /// itself. `alone` holds, for each stop of the page in order, the same part by itself, or nil for a
        /// stop that is not measured (a text that wraps freely, a row as wide as the page). A stop that wraps
        /// onto more lines in the page is taller there and is not listed. A line each.
        static func cut(_ page: some View, alone: [AnyView?], _ setting: ViewsSetting) -> [String] {
            let laidOut = placed(page, setting)
            guard laidOut.count == alone.count else {
                return ["the page reads \(laidOut.count) stops, and \(alone.count) were expected"]
            }
            let measured = alone.indices.filter { alone[$0] != nil }
            let column = VStack(alignment: .leading, spacing: 0) {
                ForEach(measured, id: \.self) { alone[$0].fixedSize() }
            }
            let own = placed(column, setting, atItsOwnWidth: true)
            guard own.count == measured.count else {
                return ["\(measured.count) parts alone read \(own.count) stops"]
            }
            return zip(measured, own).compactMap { place, own in
                let item = laidOut[place]
                guard item.stop == own.stop else {
                    return "stop \(place + 1) is \(item.stop) in the page and \(own.stop) alone"
                }
                // A heading is letter-spaced, and alone it is measured with the space after its last letter:
                // a quarter of its height is more than that space at every size. A heading has no line limit
                // and wraps when it lacks room, which makes it taller, so the slack hides no cut.
                // Anything else is cut as soon as it lacks half a point (a third is a pixel's rounding at 3×).
                let slack = item.stop.kind == .heading ? max(1, own.frame.height / 4) : 0.5
                let isNarrower = item.frame.width < own.frame.width - slack
                let isNoTaller = item.frame.height < own.frame.height + 1
                guard isNarrower, isNoTaller else {
                    return nil
                }
                let (has, asks) = (rounded(item.frame.width), rounded(own.frame.width))
                return "\(item.stop.label) \(item.stop.value): \(has) pt wide, alone it takes \(asks)"
            }
        }

        /// How much word a view draws: over the pixels of `view`, drawn in the dark theme at `setting`'s text
        /// size and weight, the sum of how much lighter each is than a hairline. The inks count (#F4F2ED, and
        /// the muted ink at half of it); the hairlines, the quiet fill and the ground do not. It is a sum and
        /// not a count, so a letter's soft edge weighs what it covers: the same words drawn whole weigh the
        /// same wherever they stand, and words cut short ("RE…") weigh less. The view must hold no ink fill.
        static func wordInk(of view: some View, _ setting: ViewsSetting) throws -> Int {
            let drawn = view
                .environment(\.dynamicTypeSize, setting.size)
                .environment(\.legibilityWeight, setting.isBold ? .bold : .regular)
            return try ProgramDrawing.pixels(of: drawn, .dark).pixels.reduce(0) { $0 + max(0, Int($1.red) - 48) }
        }

        nonisolated static func rounded(_ length: CGFloat) -> String {
            String(format: "%.1f", Double(length))
        }

        /// What is wrong with the frames of `stops` on a page `width` wide, centred in the hosting window: a
        /// stop with no size, outside the page, a target under 44 pt, two stops over each other. A line each.
        nonisolated static func faults(in stops: [PlacedStop], width: CGFloat) -> [String] {
            let leading = (SnapshotConfig.phoneWidth - width) / 2
            var lines: [String] = []
            for item in stops {
                let frame = item.frame
                if frame.width < 1 || frame.height < 1 {
                    lines.append("no size: \(item.stop) \(frame.size)")
                }
                if frame.minX < leading - 0.5 || frame.maxX > leading + width + 0.5 {
                    lines.append("outside the page: \(item.stop) x \(rounded(frame.minX))...\(rounded(frame.maxX))")
                }
                // Half a point of grace: a target that shares a row can be a pixel short (43.67 pt at 3×).
                let isTarget = item.stop.kind == .button || item.stop.kind == .adjustable
                if isTarget, frame.height < 43.5 || frame.width < 43.5 {
                    lines.append("target under 44 pt: \(item.stop) \(frame.size)")
                }
            }
            for (index, first) in stops.enumerated() {
                for second in stops[(index + 1)...] {
                    let shared = first.frame.intersection(second.frame)
                    if !shared.isNull, shared.width > 0.5, shared.height > 0.5 {
                        lines.append("overlap \(shared.size): \(first.stop) and \(second.stop)")
                    }
                }
            }
            return lines
        }
    }

    // MARK: - The parts of a page alone, for `cut`

    /// For each stop of a page, in the order of `ProgramViewsOracle`, the part that draws it, by itself: the
    /// parts whose words stand on one line (a heading, a note, a pill, a week's chip, a weekday's cell).
    enum ProgramViewsAlone {
        static func builder(_ model: ProgramBuilderModel) -> [AnyView?] {
            func pill(_ control: ProgramBuilderModel.Control) -> AnyView? {
                AnyView(PillButton(control.title) {}.disabled(control.action == nil))
            }
            let week = model.week
            var parts: [AnyView?] = [AnyView(Eyebrow(model.header.eyebrow)), AnyView(Eyebrow(model.block.title)), nil]
            parts += model.block.chips.map { AnyView(WeekChips(chips: [$0]) { _ in }) }
            parts += (model.notice == nil ? [] : [nil]) + [AnyView(Eyebrow(week.title))]
            parts += week.hint.map { [AnyView(SectionNote(text: $0))] } ?? []
            parts += week.cells.map { AnyView(ScheduleStrip(cells: [$0]) { _ in }) }
            parts += [pill(week.copyPrevious)] + (week.applyToLater.map { [pill($0)] } ?? [])
            parts.append(AnyView(PillButton(week.deload.title, style: week.deload.isOn ? .filled : .outline) {}))
            parts += [AnyView(Eyebrow(model.days.title)), AnyView(SectionNote(text: model.days.summary)), nil]
            return parts + model.days.cards.map { _ in nil } + [pill(model.days.addDay)]
        }

        static func library(_ model: ExercisePickerModel) -> [AnyView?] {
            func pill(_ chip: ExercisePickerModel.Chip) -> AnyView? {
                AnyView(
                    PillButton(chip.title, style: chip.isSelected ? .filled : .outline) {}
                        .accessibilityLabel(chip.spokenLabel)
                )
            }
            var parts: [AnyView?] = [nil, AnyView(PillButton(model.cancel.title, style: .ghost) {})]
            parts += (model.muscles.chips + model.equipment.chips).map(pill)
            switch model.content {
            case let .rows(rows): parts += rows.map { _ in nil }
            case let .nothingMatches(empty): parts += [nil, AnyView(PillButton(empty.clear.title) {})]
            }
            return parts + [nil]
        }

        /// The places, among a builder's stops, of the strip's seven weekdays.
        nonisolated static func cells(of model: ProgramBuilderModel) -> Range<Int> {
            let first = 3 + model.block.chips
                .count + (model.notice == nil ? 0 : 1) + 1 + (model.week.hint == nil ? 0 : 1)
            return first ..< first + model.week.cells.count
        }
    }

    // MARK: - What a page must read, from the notes' tables and the model alone

    /// The VoiceOver tree a model must give, written from the notes' tables for S9 and S12 ("The VoiceOver
    /// trees") and from the model, never from a view: each stop with what activating it must send (nil:
    /// nothing).
    nonisolated enum ProgramViewsOracle {
        struct Expected<Action: Equatable & Sendable>: Sendable {
            let stop: ViewStop
            var sends: Action?
        }

        static func builder(_ model: ProgramBuilderModel) -> [Expected<ProgramBuilderAction>] {
            typealias Stop = Expected<ProgramBuilderAction>
            func control(_ control: ProgramBuilderModel.Control) -> Stop {
                control.action.map { Stop(stop: .button(control.title), sends: $0) }
                    ?? Stop(stop: .dimmedButton(control.title))
            }
            let week = model.week
            var stops: [Stop] = [
                Stop(stop: .heading(model.header.eyebrow)),
                Stop(stop: .heading(model.block.title)),
                Stop(stop: .adjustable(model.block.spokenLabel, value: model.block.spokenValue))
            ]
            stops += model.block.chips.map {
                Stop(stop: .button($0.spokenLabel, value: $0.spokenValue, selected: $0.isSelected), sends: $0.action)
            }
            stops += (model.notice.map { [Stop(stop: .text($0))] } ?? []) + [Stop(stop: .heading(week.title))]
            stops += week.hint.map { [Stop(stop: .text($0))] } ?? []
            stops += week.cells.map { cell in
                cell.action.map {
                    Stop(
                        stop: .button(cell.spokenLabel, value: cell.spokenValue, hint: cell.spokenHint ?? ""),
                        sends: $0
                    )
                } ?? Stop(stop: .text(cell.spokenLabel, value: cell.spokenValue))
            }
            stops += [control(week.copyPrevious)] + (week.applyToLater.map { [control($0)] } ?? [])
            stops.append(Stop(stop: .button(week.deload.title, selected: week.deload.isOn), sends: week.deload.action))
            stops += [
                Stop(stop: .heading(model.days.title)),
                Stop(stop: .text(model.days.summary)),
                Stop(stop: .text(model.days.helper))
            ]
            stops += model.days.cards.map {
                Stop(stop: .button($0.spokenLabel, value: $0.spokenValue), sends: $0.action)
            }
            return stops + [control(model.days.addDay)]
        }

        static func library(_ model: ExercisePickerModel) -> [Expected<ExercisePickerAction>] {
            typealias Stop = Expected<ExercisePickerAction>
            var stops: [Stop] = [
                Stop(stop: .heading(model.title)),
                Stop(stop: .button(model.cancel.title), sends: model.cancel.action)
            ]
            stops += (model.muscles.chips + model.equipment.chips).map {
                Stop(stop: .button($0.spokenLabel, selected: $0.isSelected), sends: $0.action)
            }
            switch model.content {
            case let .rows(rows):
                stops += rows.map {
                    Stop(stop: .button($0.name, value: $0.line, selected: $0.isPicked), sends: $0.action)
                }
            case let .nothingMatches(empty):
                stops += [
                    Stop(stop: .text(empty.message)),
                    Stop(stop: .button(empty.clear.title), sends: empty.clear.action)
                ]
            }
            stops.append(
                model.foot.action.map { Stop(stop: .button(model.foot.title), sends: $0) }
                    ?? Stop(stop: .dimmedButton(model.foot.title))
            )
            return stops
        }
    }
#endif
