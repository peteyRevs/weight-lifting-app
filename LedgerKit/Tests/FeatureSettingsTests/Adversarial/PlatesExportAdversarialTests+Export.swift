@testable import FeatureSettings
import Foundation
import LedgerDomain
import LedgerTestSupport
import Testing

/// F14 S2, G2 round 1: the export through the store (criterion 5, N13–N16).
extension PlatesExportAdversarialTests {
    // MARK: - Export (criterion 5, N13–N16)

    static func history() -> [WorkoutState] {
        let bench = Seeders.ExerciseLog(barbell, [.init(135, 5), .init(135, 5, done: false)])
        var first = Seeders.workout(number: 3, endedAt: Fixtures.date(2026, 9, 1, hour: 9), [bench])
        first.name = "=cmd"
        let second = Seeders.workout(number: 1, endedAt: Fixtures.date(2026, 9, 10, hour: 9), [bench])
        // Two that started together: the smaller id first.
        let third = Seeders.workout(number: 2, endedAt: Fixtures.date(2026, 9, 10, hour: 9), [bench])
        return [second, first, third]
    }

    @Test("The file's bytes are the BOM, then render over every workout oldest first, in the units on screen")
    func export_bytesEqualRender() async throws {
        let workouts = Self.history()
        let scene = try SettingsScene(settings: Fixtures.settingsKg, seed: Self.seed(workouts: workouts))
        let task = await scene.running()
        defer { task.cancel() }
        let export = try scene.model.export.file
        #expect(export.fileName == "workouts-2026-09-16.csv")
        let url = try await export.write()
        #expect(url.lastPathComponent == "workouts-2026-09-16.csv")
        let bytes = try Data(contentsOf: url)
        let ordered = workouts.sorted {
            $0.startedAt == $1.startedAt ? $0.id.rawValue.uuidString < $1.id.rawValue.uuidString : $0.startedAt < $1
                .startedAt
        }
        let expected = Data((CSVExport.byteOrderMark
                + CSVExport.render(workouts: ordered, units: .kg, calendar: Fixtures.calendar)).utf8)
        #expect(bytes == expected)
        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(ordered.map(\.id) == [workouts[1].id, workouts[0].id, workouts[2].id])
    }

    @Test("An empty log exports the BOM and the header only")
    func export_emptyLog() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        defer { task.cancel() }
        let url = try await scene.model.export.file.write()
        let bytes = try Data(contentsOf: url)
        #expect(bytes == Data((CSVExport.byteOrderMark + CSVExport.header(units: .lb)).utf8))
    }

    @Test("Each export empties the directory first, and Settings going away removes it")
    func export_directoryCleanup() async throws {
        let scene = SettingsScene()
        let task = await scene.running()
        let directory = scene.exportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stray = directory.appending(path: "workouts-2020-01-01.csv")
        try Data("old".utf8).write(to: stray)
        _ = try await scene.model.export.file.write()
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(left == ["workouts-2026-09-16.csv"])
        task.cancel()
        await task.value
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("After switching to kg, the export's weights are in kg")
    func export_followsTheUnitsOnScreen() async throws {
        let scene = try SettingsScene(seed: Self.seed(workouts: Self.history()))
        let task = await scene.running()
        defer { task.cancel() }
        scene.store.send(.setUnits(.kg))
        await eventually { scene.store.pending == nil }
        let url = try await scene.model.export.file.write()
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("weight_kg"))
        #expect(text.contains(",61.23,"))
    }

    @Test("Two exports written at once (share, cancel, share again) each return a whole file that still exists")
    func export_twoAtOnce() async throws {
        let bench = Seeders.ExerciseLog(Self.barbell, Array(repeating: .init(135, 5), count: 20))
        let workouts = (0 ..< 300).map { number in
            Seeders.workout(
                number: number,
                endedAt: Fixtures.date(2026, 1, 1).addingTimeInterval(Double(number) * 86400),
                [bench]
            )
        }
        let scene = try SettingsScene(seed: Self.seed(workouts: workouts))
        let task = await scene.running()
        defer { task.cancel() }
        let export = try scene.model.export.file
        async let first = Result { try await export.write() }
        async let second = Result { try await export.write() }
        let results = await [first, second]
        let expected = Data((CSVExport.byteOrderMark + CSVExport.render(
            workouts: workouts, units: .lb, calendar: Fixtures.calendar
        )).utf8).count
        for (index, result) in results.enumerated() {
            switch result {
            case let .success(url):
                let size = (try? Data(contentsOf: url))?.count
                #expect(size == expected, "export \(index + 1): \(size.map(String.init) ?? "no file")")
            case let .failure(error):
                Issue.record("export \(index + 1) threw \(error)")
            }
        }
    }

    @Test("A directory that cannot be made makes the write throw, and nothing is written")
    func export_failureThrows() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "G2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // A file where the directory's parent should be: the directory cannot be made.
        try Data("x".utf8).write(to: root)
        let plan = ExportFile.Plan(
            name: "workouts.csv",
            units: .lb,
            calendar: Fixtures.calendar,
            directory: root.appending(path: "Export", directoryHint: .isDirectory)
        )
        #expect(throws: (any Error).self) {
            try ExportFile.write([], as: plan)
        }
        #expect(try Data(contentsOf: root) == Data("x".utf8))
    }

    @Test("The row speaks \"Export data, CSV\" with its line as the hint")
    func exportRow_words() {
        let export = SettingsPresentation.make(SettingsInput(
            settings: Fixtures.settingsLb,
            about: SettingsFixtures.about,
            locale: Fixtures.locale,
            calendar: Fixtures.calendar
        )).export
        #expect(export.title == "Export data · CSV")
        #expect(export.spokenLabel == "Export data, CSV")
        #expect(export.detail == "Every set you logged, in your current units")
    }
}
