import Foundation
@testable import LedgerDomain
import Testing

/// Start loads against the brief's step rule, decision #21's policy and spec §6.2 (criterion 2).
@Suite("Exercise catalog start loads (adversarial)", .tags(.domain))
struct CatalogLoadsAdversarialTests {}

/// Decision #21 and the `ExerciseCatalog` doc table, restated independently: the (lb, kg) pair an
/// exercise must start at, from its equipment, pattern and name.
enum PolicyOracle {
    struct Pair: Hashable, CustomStringConvertible {
        let lb: Decimal
        let kg: Decimal
        var description: String {
            "\(lb) lb / \(kg) kg"
        }
    }

    static let floorPulls: Set = ["Deadlift", "Sumo Deadlift", "Rack Pull"]
    static let landmine: Set = ["Landmine Press", "Landmine Rotation", "T-Bar Row", "Meadows Row", "Landmine Squat"]
    /// Fix round 2 (review N3): straight-bar isolation from a rack starts at the empty bar.
    static let straightBar: Set = ["Barbell Shrug", "Barbell Calf Raise", "Behind-the-Back Wrist Curl"]

    /// Decision #21 as amended in fix round 2 (review S5): a specialty bar starts at its own empty
    /// weight, whatever the lift. Read from the name, not a list, so a new safety-bar or trap-bar lift
    /// cannot start at a standard bar's load unnoticed (close-out, round 2).
    static func specialtyBar(_ exercise: Exercise) -> Pair? {
        let name = exercise.name
        if ["Safety Bar", "Safety Squat Bar", "SSB"].contains(where: name.contains) {
            return Pair(lb: dec("65"), kg: dec("30"))
        }
        if ["Trap Bar", "Hex Bar"].contains(where: name.contains) {
            return Pair(lb: dec("55"), kg: dec("25"))
        }
        return nil
    }

    static func isCompound(_ exercise: Exercise) -> Bool {
        ![.isolation, .core].contains(exercise.pattern)
    }

    /// "Delt raises and flies, rotator-cuff rotations, kickbacks, cable hip abduction and adduction,
    /// and dumbbell wrist curls" (a band pull-apart is a rear-delt fly).
    static func isSmallRaise(_ exercise: Exercise) -> Bool {
        let name = exercise.name
        let deltWork = exercise.primaryMuscle == .shoulders && exercise.pattern == .isolation
            && ["Raise", "Fly", "Pull-Apart", "Rotation"].contains { name.contains($0) }
        return deltWork || name.contains("Kickback")
            || (exercise.equipment == .cable && (name.contains("Hip Abduction") || name.contains("Hip Adduction")))
            || (exercise.equipment == .dumbbell && name.contains("Wrist Curl"))
    }

    /// "Kettlebell upper-body, overhead, clean and get-up work takes the lighter 15 lb / 8 kg bell"
    /// (decision #21 names the clean since fix round 2, finding 2).
    static func isLightBell(_ exercise: Exercise) -> Bool {
        [.chest, .back, .shoulders, .biceps, .triceps].contains(exercise.primaryMuscle)
            || ["Press", "Snatch", "Windmill", "Get-Up", "Clean"].contains { exercise.name.contains($0) }
    }

    static func expected(_ exercise: Exercise) -> Pair {
        if let bar = specialtyBar(exercise) {
            return bar
        }
        let tier = isCompound(exercise) || straightBar.contains(exercise.name) ? 0 : isSmallRaise(exercise) ? 2 : 1
        let table: [(String, String)] = switch exercise.equipment {
        case .barbell:
            floorPulls.contains(exercise.name) ? [("95", "40")]
                : landmine.contains(exercise.name) ? [("10", "5")]
                : [("45", "20"), ("25", "10"), ("25", "10")]
        case .dumbbell: [("15", "7.5"), ("10", "5"), ("5", "2.5")]
        case .cable: [("30", "15"), ("20", "10"), ("10", "5")]
        case .machine: [("40", "20"), ("20", "10"), ("10", "5")]
        case .kettlebell: isLightBell(exercise) ? [("15", "8")] : [("25", "12")]
        case .band: [("20", "10"), ("10", "5"), ("5", "2.5")]
        case .bodyweight: exercise.name.hasPrefix("Weighted ") ? [("10", "5")] : [("0", "0")]
        }
        let (lb, kg) = table[min(tier, table.count - 1)]
        return Pair(lb: dec(lb), kg: dec(kg))
    }

    static func actual(_ exercise: Exercise) -> Pair? {
        guard let lb = exercise.defaultStartLoad[.lb], let kg = exercise.defaultStartLoad[.kg] else {
            return nil
        }
        return Pair(lb: lb.pounds, kg: kg.kilograms)
    }
}

// MARK: - Steps, signs, bodyweight

extension CatalogLoadsAdversarialTests {
    @Test("Both units are present, non-negative and whole multiples of the equipment's step (decisions #9, #22).")
    func startLoads_multiplesOfStep() throws {
        for exercise in try CatalogUnderTest.exercises() {
            #expect(exercise.defaultStartLoad.count == 2, "\(exercise.name)")
            for units in Units.allCases {
                let load = try #require(exercise.defaultStartLoad[units], "\(exercise.name) \(units)")
                let value = load.value(in: units)
                #expect(value >= 0, "\(exercise.name) \(units)")
                let step = StepOracle.step(exercise.equipment, units)
                #expect(StepOracle.isMultiple(value, of: step), "\(exercise.name): \(value) \(units) vs step \(step)")
            }
        }
    }

    @Test("Bodyweight: 0 in both units with loadKind bodyweight, except weighted variants; nothing else is 0.")
    func bodyweight_zeroExactlyWhenLoadKindSaysSo() throws {
        let exercises = try CatalogUnderTest.exercises()
        let raw = try CatalogUnderTest.rawEntries()
        for (exercise, entry) in zip(exercises, raw) {
            let zero = exercise.defaultStartLoad.values.allSatisfy { $0 == .zero }
            let flagged = entry["loadKind"] as? String == "bodyweight"
            #expect(zero == flagged, "\(exercise.name)")
            #expect(!zero || exercise.equipment == .bodyweight, "\(exercise.name)")
            if exercise.equipment == .bodyweight {
                #expect(zero != exercise.name.hasPrefix("Weighted "), "\(exercise.name)")
            }
        }
    }
}

// MARK: - Policy (decision #21) and the 22 prototype entries (criterion 2)

extension CatalogLoadsAdversarialTests {
    @Test("Every exercise starts where decision #21's policy puts it, in lb and in kg.")
    func startLoads_followPolicy() throws {
        for exercise in try CatalogUnderTest.exercises() {
            let actual = PolicyOracle.actual(exercise)
            let expected = PolicyOracle.expected(exercise)
            #expect(actual == expected, "\(exercise.name) (\(exercise.equipment), \(exercise.pattern))")
        }
    }

    /// A spec §6.2 row: name, equipment, muscle family, `sh`, then the policy's loads (not `W0`).
    struct PrototypeRow: Sendable {
        let name: String
        let equipment: Equipment
        let family: String
        let short: String
        let lb: String
        let kg: String

        init(_ name: String, _ equipment: Equipment, _ family: String, _ short: String, _ lb: String, _ kg: String) {
            (self.name, self.equipment, self.family, self.short, self.lb, self.kg) = (
                name,
                equipment,
                family,
                short,
                lb,
                kg
            )
        }
    }

    static let prototype: [PrototypeRow] = [
        PrototypeRow("Barbell Bench Press", .barbell, "Chest", "BENCH", "45", "20"),
        PrototypeRow("Incline DB Press", .dumbbell, "Chest", "INCLINE", "15", "7.5"),
        PrototypeRow("Low-to-High Cable Fly", .cable, "Chest", "FLY", "20", "10"),
        PrototypeRow("Weighted Dip", .bodyweight, "Chest", "DIP", "10", "5"),
        PrototypeRow("Barbell Row", .barbell, "Back", "ROW", "45", "20"),
        PrototypeRow("Chest-Supported Row", .machine, "Back", "CS ROW", "40", "20"),
        PrototypeRow("Lat Pulldown", .cable, "Back", "PULLDOWN", "30", "15"),
        PrototypeRow("Weighted Pull-Up", .bodyweight, "Back", "PULL-UP", "10", "5"),
        PrototypeRow("Overhead Press", .barbell, "Shoulders", "OHP", "45", "20"),
        PrototypeRow("Cable Lateral Raise", .cable, "Shoulders", "LATERAL", "10", "5"),
        PrototypeRow("Rear Delt Fly", .machine, "Shoulders", "REAR DELT", "10", "5"),
        PrototypeRow("Back Squat", .barbell, "Legs", "SQUAT", "45", "20"),
        PrototypeRow("Front Squat", .barbell, "Legs", "FRONT SQ", "45", "20"),
        PrototypeRow("Romanian Deadlift", .barbell, "Legs", "RDL", "45", "20"),
        PrototypeRow("Deadlift", .barbell, "Legs", "DEADLIFT", "95", "40"),
        PrototypeRow("Leg Press", .machine, "Legs", "LEG PRESS", "40", "20"),
        PrototypeRow("Seated Leg Curl", .machine, "Legs", "LEG CURL", "20", "10"),
        PrototypeRow("Standing Calf Raise", .machine, "Legs", "CALF", "20", "10"),
        PrototypeRow("Barbell Curl", .barbell, "Arms", "CURL", "25", "10"),
        PrototypeRow("Incline DB Curl", .dumbbell, "Arms", "DB CURL", "10", "5"),
        PrototypeRow("Cable Triceps Pushdown", .cable, "Arms", "PUSHDOWN", "20", "10"),
        PrototypeRow("Overhead Cable Extension", .cable, "Arms", "OH EXT", "20", "10")
    ]

    static let families: [String: Set<MuscleGroup>] = [
        "Chest": [.chest], "Back": [.back], "Shoulders": [.shoulders],
        "Legs": [.quads, .hamstrings, .glutes, .calves], "Arms": [.biceps, .triceps, .forearms]
    ]

    @Test(
        "The 22 spec §6.2 entries exist with the prototype's equipment and muscles and the policy loads (criterion 2)."
    )
    func prototypeEntries_policyLoads() throws {
        let exercises = try CatalogUnderTest.exercises()
        #expect(Self.prototype.count == 22)
        for row in Self.prototype {
            let (name, lb, kg) = (row.name, row.lb, row.kg)
            let exercise = try CatalogUnderTest.named(name, in: exercises)
            #expect(exercise.equipment == row.equipment, "\(name)")
            #expect(Self.families[row.family]?.contains(exercise.primaryMuscle) == true, "\(name)")
            #expect(exercise.defaultStartLoad[.lb] == .pounds(dec(lb)), "\(name) lb")
            #expect(exercise.defaultStartLoad[.kg] == .kilograms(dec(kg)), "\(name) kg")
            #expect(exercise.startLoad(in: .lb).formatted(in: .lb) == lb, "\(name)")
            #expect(exercise.startLoad(in: .kg).formatted(in: .kg) == kg, "\(name)")
        }
    }

    @Test("The 22 spec §6.2 entries keep the prototype's short names (`sh`), bar the one documented deviation.")
    func prototypeEntries_shortNames() throws {
        let exercises = try CatalogUnderTest.exercises()
        // F03 notes, decision 4: Incline DB Curl is INC DB CURL so Dumbbell Curl can keep DB CURL.
        let deviations = ["Incline DB Curl": "INC DB CURL"]
        for row in Self.prototype {
            let expected = deviations[row.name] ?? row.short
            #expect(try CatalogUnderTest.named(row.name, in: exercises).shortName == expected, "\(row.name)")
        }
        #expect(try CatalogUnderTest.named("Dumbbell Curl", in: exercises).shortName == "DB CURL")
    }
}

// MARK: - Exact decimals (ADR-007)

extension CatalogLoadsAdversarialTests {
    @Test("Each load equals its JSON digits exactly, prints back as written and survives a Codable round trip.")
    func loads_exactFromDigits() throws {
        let exercises = try CatalogUnderTest.exercises()
        let texts = try CatalogUnderTest.loadTexts()
        #expect(texts.count == exercises.count)
        for (exercise, text) in zip(exercises, texts) {
            #expect(exercise.defaultStartLoad[.lb] == .pounds(dec(text.lb)), "\(exercise.name)")
            #expect(exercise.defaultStartLoad[.kg] == .kilograms(dec(text.kg)), "\(exercise.name)")
            #expect(exercise.defaultStartLoad[.lb]?.formatted(in: .lb) == text.lb, "\(exercise.name)")
            #expect(exercise.defaultStartLoad[.kg]?.formatted(in: .kg) == text.kg, "\(exercise.name)")
        }
        let decoded = try JSONDecoder().decode([Exercise].self, from: JSONEncoder().encode(exercises))
        #expect(decoded == exercises)
        // 15 lb is 6,803.88555 g exactly (15 × 453.59237), not a Double's neighbour.
        let dumbbell = try CatalogUnderTest.named("Dumbbell Bench Press", in: exercises)
        #expect(dumbbell.defaultStartLoad[.lb]?.grams == dec("6803.88555"))
        #expect(dumbbell.defaultStartLoad[.kg]?.grams == dec("7500"))
    }
}
