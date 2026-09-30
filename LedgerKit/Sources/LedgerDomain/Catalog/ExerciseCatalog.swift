import Foundation

/// The seeded exercise catalog (F03, decision #12): `Resources/exercises.json`, decoded and checked
/// into `Exercise` values. F05's `seedIfNeeded(_:version:)` stores them; F07 calls it at launch.
///
/// ## Movement patterns
///
/// `pattern` is the exercise's swap family (decision #13): a swap offers only alternatives with
/// the same pattern, so each rule below says what a lifter would accept as a substitute.
/// - `horizontalPush`: presses in front of the torso — flat, incline and decline presses,
///   push-ups and dips. Dips stand in for a bench press, not an overhead press.
/// - `verticalPush`: presses overhead — overhead presses, the landmine press, pike and handstand
///   push-ups.
/// - `horizontalPull`: rows to the torso.
/// - `verticalPull`: pull-ups, chin-ups and pulldowns.
/// - `squat`: two-legged, knee-dominant lifts — squats (front squat included), leg presses and
///   hack squats.
/// - `lunge`: single-leg, knee-dominant lifts — lunges, split squats, step-ups and pistols.
/// - `hinge`: hip-dominant lifts, on one leg or two — deadlifts (the RDL included), good mornings,
///   hip thrusts, bridges, swings, cleans, back extensions and pull-throughs.
/// - `carry`: loaded walks. Reps count lengths.
/// - `core`: trunk work that is not a carry — crunches, sit-ups, leg raises, rollouts, Pallof
///   presses, chops, side bends and the Turkish get-up.
/// - `isolation`: single-joint accessories, and the small-muscle accessories whose only sensible
///   swaps are other accessories for the same muscle, even though more than one joint moves:
///   face pulls, upright rows, shrugs, pullovers and straight-arm pulldowns. Every isolation
///   alternative trains the same primary muscle.
///
/// ## Start loads
///
/// `defaultStartLoad` holds both units. Each is a multiple of the equipment's default step in
/// that unit, and the kilogram value is the pound value converted and rounded to the kilogram
/// step. The 22 prototype entries keep spec §6.2's `W0`; the rest are conservative beginner loads.
/// Dumbbell and kettlebell loads are per implement; landmine lifts count the plates only; band
/// loads are the band's rated resistance; bodyweight exercises start at zero, and their weighted
/// versions (Weighted Dip) give the added load.
public enum ExerciseCatalog {
    /// The catalog's content version. Bump it by one with every change to `exercises.json` and
    /// append the new SHA-256 to `catalog.version.sha` (criterion 7; a test fails until both are
    /// done). Upgrades are additive: an id is never removed, reused or regenerated.
    public static let version = 1

    /// Every catalog exercise, in file order.
    ///
    /// - Throws: `CatalogError` for the first malformed entry (criterion 1). Nothing is skipped.
    public static func seed() throws -> [Exercise] {
        try exercises(from: resource("exercises", withExtension: "json"))
    }

    /// Decodes and checks a catalog document.
    static func exercises(from json: Data) throws -> [Exercise] {
        let entries = try entries(from: json)
        var ids: Set<ExerciseID> = []
        var names: Set<String> = []
        for entry in entries {
            guard ids.insert(entry.id).inserted else {
                throw CatalogError.duplicateID(entry.id)
            }
            for name in [entry.name] + entry.aliases {
                guard names.insert(name.lowercased()).inserted else {
                    throw CatalogError.duplicateName(name)
                }
            }
        }
        let exercises = try entries.map { try $0.exercise() }
        let patterns = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.pattern) })
        for exercise in exercises {
            for alternative in exercise.curatedAlternatives {
                guard let pattern = patterns[alternative] else {
                    throw CatalogError.unknownAlternative(exercise.id, alternative: alternative)
                }
                guard pattern == exercise.pattern else {
                    throw CatalogError.alternativePatternMismatch(exercise.id, alternative: alternative)
                }
            }
        }
        return exercises
    }

    /// The document's entries, as written.
    static func entries(from json: Data) throws -> [CatalogEntry] {
        do {
            return try JSONDecoder().decode(Document.self, from: json).exercises
        } catch let error as DecodingError {
            throw CatalogError.unreadable(String(describing: error))
        }
    }

    /// A file from this module's resource bundle.
    static func resource(_ name: String, withExtension fileExtension: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            throw CatalogError.missingResource("\(name).\(fileExtension)")
        }
        return try Data(contentsOf: url)
    }

    /// The top level of `exercises.json`. Its `contributing` notes are for people and not decoded.
    private struct Document: Decodable {
        let exercises: [CatalogEntry]
    }
}
