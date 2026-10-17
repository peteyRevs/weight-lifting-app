#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    // The Day editor's previews: cases of `ProgramPreview`, the module's one registry, each drawn from the
    // model `DayEditorPresentation` makes of a day of the spec's seed program.

    nonisolated extension ProgramPreviewData {
        static let longDayName = "Upper body with the long accessory circuit, push focus, autumn block"
        static let longExerciseName = "Single-Arm Half-Kneeling Landmine Press with a pause at the top"

        /// Which day of the seed program a Day editor preview shows, which of its exercises is open, and in
        /// which week of the block; all by their place, 0 the first.
        private struct Place {
            var day = 0
            var open: Int?
            var week = 0
        }

        private static func place(of preview: ProgramPreview) -> Place {
            switch preview {
            case .daySuperset: Place(day: 1, open: 3)
            case .dayOpenLinear: Place(open: 0)
            case .dayOpenDouble: Place(open: 1)
            case .dayDropSet: Place(day: 2, open: 3)
            case .dayDeload: Place(open: 0, week: 7)
            default: Place()
            }
        }

        static func dayEditorInput(for preview: ProgramPreview) throws -> DayEditorInput {
            let place = place(of: preview)
            var program = try Fixtures.seedProgram()
            var exercises = try Dictionary(ExerciseCatalog.seed().map { ($0.id, $0) }) { first, _ in first }
            guard program.days.indices.contains(place.day) else {
                throw NoSuchDay()
            }
            let day = program.days[place.day]
            if preview == .dayLongNames {
                program = ProgramEditing.renameDay(program, day: day.id, to: longDayName)
                // The first exercise and the first of the superset.
                for slot in [day.slots.first, day.slots.dropLast().last].compactMap(\.self) {
                    exercises[slot.exerciseID]?.name = longExerciseName
                }
            }
            return DayEditorInput(
                program: program,
                day: day.id,
                exercises: exercises,
                settings: Fixtures.settingsLb,
                weekIndex: place.week,
                openSlot: place.open.flatMap { day.slots.indices.contains($0) ? day.slots[$0].id : nil },
                locale: Fixtures.locale
            )
        }

        /// The editor's content for the case. The seed program holds each day, so the model is never "the day
        /// is gone".
        static func dayEditorContent(for preview: ProgramPreview) throws -> DayEditorModel.Content {
            guard case let .editing(content) = try DayEditorPresentation.make(dayEditorInput(for: preview)) else {
                throw NoSuchDay()
            }
            return content
        }

        struct NoSuchDay: Error {}
    }

    #Preview("Day editor") {
        ProgramPreview.dayEditor.content
    }

    #Preview("A superset, its second exercise open") {
        ProgramPreview.daySuperset.content
    }

    #Preview("An exercise open, linear") {
        ProgramPreview.dayOpenLinear.content
    }

    #Preview("An exercise open, double") {
        ProgramPreview.dayOpenDouble.content
    }

    #Preview("Drop set on") {
        ProgramPreview.dayDropSet.content
    }

    #Preview("Deload week, an exercise open") {
        ProgramPreview.dayDeload.content
    }

    #Preview("Long day and exercise names") {
        ProgramPreview.dayLongNames.content
    }
#endif
