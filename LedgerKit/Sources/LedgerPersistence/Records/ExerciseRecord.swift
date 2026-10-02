import GRDB
import LedgerDomain

/// An `exercise` row: the exercise's content. `catalog_version` is not content: the seeder sets it on the rows
/// it inserts or refreshes, and a lifter's save clears it (`GRDBExerciseRepository`; product decision #24).
struct ExerciseRecord: SyncedRecord {
    static let databaseTableName = "exercise"

    let exercise: Exercise

    var rowID: String {
        ColumnCodec.text(exercise.id)
    }

    init(_ exercise: Exercise) {
        self.exercise = exercise
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        var startLoads: [Units: Weight] = [:]
        startLoads[.lb] = try read.weight("start_load_lb_e7g")
        startLoads[.kg] = try read.weight("start_load_kg_e7g")
        exercise = try Exercise(
            id: read.identifier("id"),
            name: read.text("name"),
            shortName: read.text("short_name"),
            equipment: read.enumeration("equipment"),
            primaryMuscle: read.enumeration("primary_muscle"),
            secondaryMuscles: read.array("secondary_muscles"),
            pattern: read.enumeration("pattern"),
            defaultStartLoad: startLoads,
            isCustom: read.flag("is_custom"),
            curatedAlternatives: read.array("curated_alternatives")
        )
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = rowID
        container["name"] = exercise.name
        container["short_name"] = exercise.shortName
        container["equipment"] = exercise.equipment.rawValue
        container["primary_muscle"] = exercise.primaryMuscle.rawValue
        container["secondary_muscles"] = JSONArray(exercise.secondaryMuscles)
        container["pattern"] = exercise.pattern.rawValue
        container["start_load_lb_e7g"] = try exercise.defaultStartLoad[.lb]?.e7g()
        container["start_load_kg_e7g"] = try exercise.defaultStartLoad[.kg]?.e7g()
        container["is_custom"] = exercise.isCustom
        container["curated_alternatives"] = JSONArray(exercise.curatedAlternatives)
    }
}
