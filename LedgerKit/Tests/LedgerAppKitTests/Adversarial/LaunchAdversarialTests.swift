import Dependencies
import Foundation
import GRDB
@testable import LedgerAppKit
import LedgerDependencies
import LedgerDomain
import LedgerPersistence
import SwiftUI
import Testing

/// F07 S2 adversarial round 1: the iPhone launch's state machine under cancelled and overlapping resumes, against
/// a model of the notes' sequence over random phase sequences and faults (the watch target runs the same model, so
/// the two launches are held to one spec), and decisions #28 and #29 beyond the implementer's cases.
@Suite("Adversarial F07 S2 · iPhone launch", .timeLimit(.minutes(1)))
struct LaunchAdversarialTests {
    typealias Composition = AppComposition

    /// A log entry as both platforms spell it (the iPhone's handler entries left out).
    static func spelled(_ log: [Harness.Entry]) -> [String] {
        log.compactMap { entry in
            switch entry {
            case let .event(.began(step)) where step.rawValue != "assignMirroringHandler": "began \(step.rawValue)"
            case let .event(.failed(step)): "failed \(step.rawValue)"
            case .companionActivated: "companion"
            default: nil
            }
        }
    }

    static func save(_ settings: LedgerDomain.Settings, at harness: Harness) async throws {
        let queue = try LedgerDatabase.open(at: harness.databaseURL)
        try await GRDBSettingsRepository(queue).save(settings)
        try queue.close()
    }

    static var kilograms: LedgerDomain.Settings {
        var settings = LedgerDomain.Settings.default
        settings.units = .kg
        return settings
    }

    // MARK: - Cancelled and overlapping resumes

    @Test("F7-S2-1: a first resume cancelled by a phase change still loads the settings on the next foreground")
    func cancelledFirstResume_settingsStillLoad() async throws {
        let harness = Harness()
        defer { harness.remove() }
        try await Self.save(Self.kilograms, at: harness)
        let composition = harness.booted()
        // `.task(id: scenePhase)` cancels the running resume when the phase changes (launched in the background
        // by a workout, then opened): GRDB's reads and writes then throw `CancellationError`.
        let first = Task { await composition.resume(in: .background) }
        first.cancel()
        await first.value
        await composition.resume(in: .active)
        #expect(composition.isCatalogSeeded)
        #expect(composition.settings == Self.kilograms, "the lifter's kg settings were never loaded")
    }

    @Test("F7-S2-1: a cancelled resume is not a failure: nothing is logged at fault level as failed")
    func cancelledFirstResume_logsNoFailure() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        let first = Task { await composition.resume(in: .inactive) }
        first.cancel()
        await first.value
        #expect(!harness.log.contains(.event(.failed(.seedCatalog))))
        #expect(!harness.log.contains(.event(.failed(.loadSettings))))
    }

    @Test("F7-S2-1: two resumes overlapping (a phase change while the first awaits) run each step once")
    func overlappingResumes_runEachStepOnce() async {
        let harness = Harness()
        defer { harness.remove() }
        let composition = harness.booted()
        async let first: Void = composition.resume(in: .inactive)
        async let second: Void = composition.resume(in: .active)
        _ = await (first, second)
        let spelled = Self.spelled(harness.log)
        #expect(spelled.filter { $0 == "began seedCatalog" }.count == 1, "\(spelled)")
        #expect(spelled.filter { $0 == "began loadSettings" }.count == 1, "\(spelled)")
        #expect(composition.isCatalogSeeded)
    }
}

extension LaunchAdversarialTests {
    // MARK: - The model

    /// The launch as the notes specify it: what each call logs, given which attempts fail.
    struct Model {
        var openFails: Bool
        var seedFails: Bool
        var isOpen = false
        var isSeeded = false
        var hasResumed = false
        var hasLoadedSettings = false
        /// Sanctioned edit (F10 S2, orchestrator 2026-10-05): the launch gained the step `resumeWorkout`.
        var hasResumedWorkout = false
        var isCompanionActive = false
        var log: [String] = []

        mutating func boot() {
            open()
        }

        mutating func open() {
            log.append("began openDatabase")
            if openFails {
                log.append("failed openDatabase")
            } else {
                isOpen = true
            }
        }

        mutating func resume(_ phase: ScenePhase) {
            if hasResumed {
                guard phase == .active else {
                    return
                }
                if !isOpen {
                    open()
                }
            }
            hasResumed = true
            if isOpen {
                if !isSeeded {
                    log.append("began seedCatalog")
                    if seedFails {
                        log.append("failed seedCatalog")
                    } else {
                        isSeeded = true
                    }
                }
                if !hasLoadedSettings {
                    log.append("began loadSettings")
                    hasLoadedSettings = true
                }
                // After the settings, once the database is open, in whatever phase: the live workout's recovery
                // begins. No fault this test injects reaches it (it only reads an empty event log), so it never
                // fails here, and a step that succeeded is not run again. Its failure and its retry on the next
                // foreground are `WorkoutSessionWiringTests`'.
                if !hasResumedWorkout {
                    log.append("began resumeWorkout")
                    hasResumedWorkout = true
                }
            }
            if !isCompanionActive {
                log += ["began activateCompanionSession", "companion"]
                isCompanionActive = true
            }
        }
    }

    static let phases: [ScenePhase] = [.active, .inactive, .background]

    @Test(
        "Random phase sequences with an open or a seed failing until a random step: the log is the model's",
        arguments: 0 ..< 60
    )
    func randomPhases_matchTheModel(seed: Int) async throws {
        var random = SeededRandom(seed: UInt64(seed))
        let harness = Harness("randomPhases\(seed)") // one directory per case: the cases run in parallel
        defer { harness.remove() }
        let fault = Int.random(in: 0 ... 2, using: &random)
        let heal = Int.random(in: 0 ... 6, using: &random)
        if fault == 1 {
            try FileManager.default.createDirectory(at: harness.databaseURL, withIntermediateDirectories: true)
        }
        if fault == 2 {
            try harness.arrange { database in
                try database
                    .execute(
                        sql: "CREATE TRIGGER refuse BEFORE INSERT ON exercise BEGIN SELECT RAISE(ABORT, 'no'); END"
                    )
            }
        }
        var model = Model(openFails: fault == 1, seedFails: fault == 2)
        let composition = harness.booted()
        model.boot()
        for step in 0 ..< 7 {
            if step == heal, fault == 1 {
                try FileManager.default.removeItem(at: harness.databaseURL)
                model.openFails = false
            }
            if step == heal, fault == 2 {
                let queue = try LedgerDatabase.open(at: harness.databaseURL)
                try await queue.write { try $0.execute(sql: "DROP TRIGGER refuse") }
                try queue.close()
                model.seedFails = false
            }
            let phase = Self.phases[Int.random(in: 0 ..< 3, using: &random)]
            await composition.resume(in: phase)
            model.resume(phase)
            #expect(Self.spelled(harness.log) == model.log, "seed \(seed) fault \(fault) heal \(heal) step \(step)")
            #expect((composition.state == .ready) == model.isOpen)
            #expect(composition.isCatalogSeeded == model.isSeeded)
        }
    }
}

/// SplitMix64, for the random phase sequences.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
