#if os(iOS) && DEBUG
    @testable import FeatureWorkout
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F10 S6 after round 1, criterion 17: the panel leaves the page room at every text size. On the
    /// tester's three phones (`WorkoutRestPanelAdversarialTests.phones`: a 375 pt phone with a home button,
    /// one with a notch, an iPhone 17), measured as the tester measures (`room(on:at:)`), at least 120 pt
    /// of the page show between the header and the panel, to see a row in and to drag.
    @Suite("Rest panel: the page's room", .serialized, .tags(.feature))
    struct RestPanelRoomTests {
        typealias Rooms = WorkoutRestPanelAdversarialTests

        /// The least height of page the ruling asks for.
        nonisolated static let leastPage: CGFloat = 120

        /// Every text size. On the hosted PR runner (`TestSweep`) the representative sizes and `.accessibility4`,
        /// where the page is least on every phone (173 pt on the 375 pt phone with a home button, 182 at
        /// `.accessibility5`; 2026-10-21).
        nonisolated static let sizes = TestSweep.sizes(DynamicTypeSize.allCases, also: [.accessibility4])

        @Test("At every text size at least 120 pt of the page show over the panel, on three phones", arguments: [
            WorkoutPreview.resting, .restOver
        ])
        func page_keepsItsRoom(_ preview: WorkoutPreview) throws {
            var table: [String] = []
            var least = CGFloat.infinity
            for phone in Rooms.phones {
                var row: [String] = []
                for size in Self.sizes {
                    let room = try Rooms.room(on: phone.size, at: size, preview)
                    least = min(least, room.page)
                    row.append("\(Int(room.page))/\(Int(room.panel))")
                    #expect(room.panelEnd <= phone.size.height + 0.5, "\(phone.name) at \(size): below the screen")
                }
                table.append("\(phone.name): " + row.joined(separator: " "))
            }
            let swept = Self.sizes.map { "\($0)" }.joined(separator: ", ")
            let measured = "page/panel in pt at \(swept). \(table.joined(separator: " | "))"
            #expect(least >= Self.leastPage, "\(measured)")
            // The table, for the notes: kept with the run's result.
            Attachment.record(measured, named: "room-\(preview.rawValue)")
        }

        @Test("The compact panel has no ring: at an accessibility size it is shorter than at the size before it")
        func compactPanel_isShorter() throws {
            let phone = Rooms.phones[2].size
            let regular = try Rooms.room(on: phone, at: .xxxLarge).panel
            let compact = try Rooms.room(on: phone, at: .accessibility1).panel
            #expect(compact < regular, "\(compact) pt against \(regular) pt")
        }
    }
#endif
