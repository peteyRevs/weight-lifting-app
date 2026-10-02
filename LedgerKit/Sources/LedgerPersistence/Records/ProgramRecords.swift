import GRDB
import LedgerDomain

/// A `program` row: the block's own fields. Its weeks and days are rows of their own.
struct ProgramRecord: SyncedRecord {
    static let databaseTableName = "program"

    let id: ProgramID
    let name: String
    let startDate: CivilDate
    let goal: TrainingGoal?
    let daysPerWeek: Int?
    let isActive: Bool

    var rowID: String {
        ColumnCodec.text(id)
    }

    init(_ program: Program) {
        id = program.id
        name = program.name
        startDate = program.startDate
        goal = program.goal
        daysPerWeek = program.daysPerWeek
        isActive = program.isActive
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        id = try read.identifier("id")
        name = try read.text("name")
        guard let civilDate = try CivilDate(iso8601: read.text("start_date")) else {
            throw LedgerPersistenceError.malformedColumn("program.start_date")
        }
        startDate = civilDate
        goal = try read.optionalEnumeration("goal")
        daysPerWeek = try read.optionalInteger("days_per_week")
        isActive = try read.flag("is_active")
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = rowID
        container["name"] = name
        container["start_date"] = startDate.description // ADR-007: "YYYY-MM-DD"
        container["goal"] = goal?.rawValue
        container["days_per_week"] = daysPerWeek
        container["is_active"] = isActive
    }
}

/// A `program_week` row: one week and its schedule, a day template id (or `NULL`, a rest day) per weekday.
struct WeekRecord: SyncedRecord {
    static let databaseTableName = "program_week"

    let week: Week
    let programID: ProgramID

    var rowID: String {
        ColumnCodec.text(week.id)
    }

    init(_ week: Week, programID: ProgramID) {
        self.week = week
        self.programID = programID
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        var schedule: [Weekday: DayTemplateID] = [:]
        for weekday in Weekday.allCases {
            schedule[weekday] = try read.optionalIdentifier(Self.column(weekday))
        }
        week = try Week(
            id: read.identifier("id"),
            index: read.integer("week_index"),
            isDeload: read.flag("is_deload"),
            schedule: schedule
        )
        programID = try read.identifier("program_id")
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = rowID
        container["program_id"] = ColumnCodec.text(programID)
        container["week_index"] = week.index
        container["is_deload"] = week.isDeload
        for weekday in Weekday.allCases {
            container[Self.column(weekday)] = week.schedule[weekday].map(ColumnCodec.text)
        }
    }

    /// The column that holds `weekday`'s day template.
    static func column(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: "mon"
        case .tuesday: "tue"
        case .wednesday: "wed"
        case .thursday: "thu"
        case .friday: "fri"
        case .saturday: "sat"
        case .sunday: "sun"
        }
    }
}

/// A `day_template` row: a training day's name and tag, and its place in `Program.days`. Its slots are rows
/// of their own.
struct DayTemplateRecord: SyncedRecord {
    static let databaseTableName = "day_template"

    let id: DayTemplateID
    let programID: ProgramID
    let position: Int
    let name: String
    let tag: String

    var rowID: String {
        ColumnCodec.text(id)
    }

    init(_ day: DayTemplate, programID: ProgramID, position: Int) {
        id = day.id
        self.programID = programID
        self.position = position
        name = day.name
        tag = day.tag
    }

    init(row: Row) throws {
        let read = ColumnReader(row: row, table: Self.databaseTableName)
        id = try read.identifier("id")
        programID = try read.identifier("program_id")
        position = try read.integer("position")
        name = try read.text("name")
        tag = try read.text("tag")
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = rowID
        container["program_id"] = ColumnCodec.text(programID)
        container["position"] = position
        container["name"] = name
        container["tag"] = tag
    }
}
