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
/// `defaultStartLoad` holds both units and follows one conservative, beginner-safe policy (Pete,
/// 2026-09-30, decision #21), by equipment and movement class:
///
/// | Equipment | Compound | Isolation and core | Small raises |
/// |---|---|---|---|
/// | Barbell (bar included) | 45 lb / 20 kg, the empty bar | 25 lb / 10 kg, an EZ or fixed bar | — |
/// | Specialty bar (empty) | safety squat bar 65 lb / 30 kg; trap bar 55 lb / 25 kg | — | — |
/// | Dumbbell (per hand) | 15 lb / 7.5 kg | 10 lb / 5 kg | 5 lb / 2.5 kg |
/// | Cable (per stack) | 30 lb / 15 kg | 20 lb / 10 kg | 10 lb / 5 kg |
/// | Machine | 40 lb / 20 kg | 20 lb / 10 kg | 10 lb / 5 kg |
/// | Kettlebell (per bell) | 25 lb / 12 kg | — | — |
/// | Band (rated resistance) | 20 lb / 10 kg | 10 lb / 5 kg | 5 lb / 2.5 kg |
/// | Bodyweight | 0 | 0 | — |
///
/// Some lifts take their own value:
/// - specialty bars start at their own empty weight (the row above), whatever the lift's class;
/// - deadlift-family floor pulls (deadlift, sumo deadlift, rack pull) start at 95 lb / 40 kg, the
///   bar with two small plates at pulling height;
/// - isolation done with a straight bar from a rack (shrug, calf raise, behind-the-back wrist curl)
///   starts at the empty bar, 45 lb / 20 kg;
/// - landmine lifts count plates only, 10 lb / 5 kg;
/// - kettlebell upper-body, overhead, clean and get-up work takes the lighter 15 lb / 8 kg bell;
/// - weighted dips and pull-ups add 10 lb / 5 kg.
///
/// "Small raises" are delt raises and flies, rotator-cuff rotations, kickbacks, cable hip abduction
/// and adduction, and dumbbell wrist curls.
///
/// Each value is a multiple of the equipment's default step in that unit. The kg column is chosen
/// in kg — the same setup with kg equipment (a 20 kg bar, 2.5 kg dumbbell and 5 kg stack steps,
/// the 8, 12 and 16 kg bells beginners start on; kettlebells then step 2 kg, decision #22) — not
/// converted from lb. Dumbbell and kettlebell loads are per implement; band loads are the band's
/// rated resistance; carries count lengths as reps.
public enum ExerciseCatalog {
    /// The catalog's content version. A change to `exercises.json` must raise it above `main`'s
    /// (`scripts/check-catalog-version.sh`) and record the file's SHA-256 against it in
    /// `catalog.version.sha` (criterion 7). Upgrades refresh in place (F05): an install that already
    /// has the catalog receives the new entries and the corrected content of existing ones, keyed by
    /// id; custom exercises and deleted rows are never touched. An id is never removed, reused or
    /// regenerated; the script fails if one main has is gone or moved to another entry.
    public static let version = 3

    /// Every catalog exercise, in file order.
    ///
    /// - Throws: `CatalogError` for the first malformed entry (criterion 1); nothing is skipped.
    ///   `missingResource` covers a file missing from the module's bundle. Reading the file can also
    ///   throw Foundation's own error, and `Bundle.module` itself traps if the whole bundle is missing
    ///   (SwiftPM's generated accessor).
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
