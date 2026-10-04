#if DEBUG
    import Foundation
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerWatchAppKit
    import Testing

    /// What the watch's Diagnostics page shows (F07 criterion 7) and launch-to-first-frame (product decision #30).
    @Suite("Watch diagnostics", .timeLimit(.minutes(1)))
    struct DiagnosticsTests {
        /// Every line's value, by its identifier.
        static func values(_ sections: [DiagnosticsSection]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: sections.flatMap(\.lines).map { ($0.id, $0.value) })
        }

        @Test("The root's first appearance measures launch-to-first-frame from the process start, once")
        func rootAppeared_measuresOnce() {
            let harness = Harness()
            defer { harness.remove() }
            let composition = harness.composition(processStart: Harness.now.addingTimeInterval(-0.25))
            #expect(composition.launchToFirstFrame == nil)
            composition.rootAppeared()
            #expect(composition.launchToFirstFrame == .milliseconds(250))
            composition.rootAppeared()
            #expect(composition.launchToFirstFrame == .milliseconds(250))
        }

        @Test("Without the process's start time, nothing is measured")
        func noStartTime_measuresNothing() {
            let harness = Harness()
            defer { harness.remove() }
            let composition = harness.composition()
            composition.rootAppeared()
            #expect(composition.launchToFirstFrame == nil)
        }

        /// Called with no key bound: a read of a store key or `deviceID` would fail the test, naming the key (S2-N2).
        @Test("The page reads the composition's own stores, never a dependency key")
        func diagnostics_readTheCompositionsStores() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let composition = harness.composition(processStart: Harness.now.addingTimeInterval(-0.3124))
            composition.boot()
            await composition.resume(in: .active)
            composition.rootAppeared()

            let sections = await composition.diagnostics(health: .denied)

            #expect(sections.map(\.title) == ["App", "Rows"])
            #expect(sections.first?.lines.map(\.label) == [
                "Database", "Device", "Health", "Launch to first frame", "Dependencies"
            ])
            let values = Self.values(sections)
            #expect(values["debug.diagnostics.path"] == harness.databasePath)
            #expect(values["debug.diagnostics.deviceID"] == Harness.deviceUUID.uuidString)
            #expect(values["debug.diagnostics.health"] == "Denied")
            #expect(values["debug.diagnostics.launch"] == "312 ms")
            #expect(values["debug.diagnostics.context"] == "test")
            #expect(try values["debug.diagnostics.rows.exercise"] == String(ExerciseCatalog.seed().count))
            #expect(values["debug.diagnostics.rows.device"] == "1")
        }

        @Test("Before the database opens, the page says so and lists no table")
        func unopened_saysNotOpen() async {
            let sections = await Harness().composition().diagnostics(health: .notDetermined)
            #expect(sections.first?.lines.map(\.value) == [
                "Not open",
                "Unknown",
                "Not determined",
                "Not measured",
                "test"
            ])
            #expect(sections.last?.lines.isEmpty == true)
        }

        @Test("A database that cannot be read shows why, in the database's line")
        func unreadable_showsWhy() async throws {
            let harness = Harness()
            defer { harness.remove() }
            let composition = harness.booted()
            try #require(composition.stores).queue.close()
            let sections = await composition.diagnostics(health: .authorized)
            let value = try #require(sections.first?.lines.first?.value)
            #expect(value != harness.databasePath && value != "Not open", "\(value)")
            #expect(sections.last?.lines.isEmpty == true)
        }
    }
#endif
