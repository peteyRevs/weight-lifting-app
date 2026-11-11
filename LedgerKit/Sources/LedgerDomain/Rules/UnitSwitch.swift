import Foundation

/// What a switch of units does to a program's weights (F14 S2, criterion 1; Pete's question 1, A): each explicit
/// start load is rounded to the nearest default step of its exercise's equipment in the new unit (45 lb becomes
/// 20 kg, 135 lb becomes 60 kg), and each explicit step is converted and rounded the same way, never below one default
/// step (5 lb on a barbell becomes 2.5 kg). A slot that has no load or no step of its own keeps `nil`, which already
/// reads in whatever unit the lifter uses. Past workouts are never converted: this is for the program only.
///
/// **Idempotent:** a load or a step already on the new unit's grid is unchanged, so converting twice gives what
/// converting once gives. It is not undone by converting back: 135 lb becomes 60 kg, which comes back as 130 lb, one
/// step away (Pete's question 1 says so). So it is applied only when the units change
/// (`SettingsRepository.switchUnits(_:)`): a load set on purpose between two default steps in the unit it is in would
/// otherwise be rounded.
public enum UnitSwitch {
    /// The equipment of an exercise `equipment` does not list: one of those whose default step is the finest of the
    /// unit (1.25 kg, 2.5 lb), so its load moves as little as it can.
    static let unknownEquipment = Equipment.machine

    /// `program` with every explicit start load and step on the default grid of its exercise's equipment in `units`.
    /// `equipment` gives each exercise's equipment; one it lacks is rounded on the finest grid.
    ///
    /// The slots' fields are assigned, not rebuilt through `Slot.init`, as `DayEditing` assigns them: a rounded load of
    /// a non-negative load is non-negative, and a step is at least one default step, so every range still holds.
    public static func convert(_ program: Program, to units: Units, equipment: [ExerciseID: Equipment]) -> Program {
        var converted = program
        for day in converted.days.indices {
            for index in converted.days[day].slots.indices {
                let slot = converted.days[day].slots[index]
                let grid = (equipment[slot.exerciseID] ?? unknownEquipment).defaultStep(in: units)
                converted.days[day].slots[index].startLoad = slot.startLoad.map { $0.rounded(toStep: grid) }
                converted.days[day].slots[index].step = slot.step.map { max($0.rounded(toStep: grid), grid) }
            }
        }
        return converted
    }
}
