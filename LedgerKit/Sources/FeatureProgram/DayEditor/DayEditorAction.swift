import LedgerDomain

/// What a tap on the Day editor means, as a value: the store applies it and decides nothing.
nonisolated enum DayEditorAction: Hashable, Sendable {
    /// Open the panel of this slot, or close the open one for nil. Nothing is stored.
    case open(SlotID?)
    /// Queue `edit`; when `closesPanel`, close the open panel as well.
    case edit(DayEditorEdit, closesPanel: Bool = false)
    /// "+ Add exercise from library": present the exercise library.
    case openLibrary
    /// Emit the route.
    case route(ProgramRoute)

    /// The name field's text as the lifter typed it: the one action a view makes itself, and it names no edit.
    static func rename(_ text: String, day: DayTemplateID) -> DayEditorAction {
        .edit(.renameDay(text, day: day))
    }
}

/// One edit made in the Day editor, complete with its ids: exactly one `ProgramEditing` call. The store queues
/// these values and applies them to the stored program inside `ProgramRepository.update`.
nonisolated enum DayEditorEdit: Hashable, Sendable {
    /// The name as typed; a blank one changes nothing.
    case renameDay(String, day: DayTemplateID)
    /// The day goes, and every weekday that trained it rests.
    case deleteDay(DayTemplateID)
    /// One edit of the day's slots.
    case slot(SlotEdit, day: DayTemplateID)

    /// Whether this one edit, drawn again over a program that already has it, gives another program: the mark
    /// is about a single edit, not about a queue. No queued edit, marked or not, is safe to send twice (a
    /// superset edit names "the slot before", whoever that is by then): each reaches the stored program
    /// exactly once, and none is sent again after a failed save.
    var isRelative: Bool {
        switch self {
        case .renameDay, .deleteDay: false
        case let .slot(edit, _): edit.isRelative
        }
    }

    /// `program` after this edit. Nothing throws; an edit that names a day or a slot the program does not hold
    /// returns it unchanged, as `ProgramEditing` and `DayEditing` do.
    func applied(to program: Program) -> Program {
        switch self {
        case let .renameDay(name, day):
            ProgramEditing.renameDay(program, day: day, to: name)
        case let .deleteDay(day):
            ProgramEditing.deleteDay(program, day: day)
        case let .slot(edit, day):
            ProgramEditing.updateDay(program, day: day) { edit.applied(to: $0) }
        }
    }
}

/// One edit of a day's slots: exactly one `DayEditing` call.
///
/// A field is edited by the value it is set to, the drop set and the superset by the state they turn to, so
/// one of those drawn or applied twice gives what one application gives. A move carries a slot one place from
/// wherever it stands, and is marked relative. A removal is marked too, as the slice's criterion 10 lists it,
/// although it names its slot and a second one finds nothing: the mark follows that list, not the definition.
nonisolated enum SlotEdit: Hashable, Sendable {
    /// The field with the value it takes: the one `DayEditing.stepped` gave for the slot on screen. `set`
    /// holds it within the field's range.
    case set(SlotField, slot: SlotID)
    case setProgression(Progression, slot: SlotID)
    /// The slot has a drop set, or has none.
    case setDropSet(Bool, slot: SlotID)
    /// The slot is joined to the one before it, or is not. "Superset with next" names the next slot.
    case setSuperset(Bool, slot: SlotID)
    case move(MoveDirection, slot: SlotID)
    case remove(slot: SlotID)
    /// The exercise library's picks, as the slots `DayEditing.newSlot` built for them when "Add" was
    /// tapped, in the order picked: they go to the day's end. Each carries its id, so a slot the day
    /// already holds is left out and a second application adds nothing.
    case add([Slot])

    var isRelative: Bool {
        switch self {
        case .set, .setProgression, .setDropSet, .setSuperset, .add: false
        case .move, .remove: true
        }
    }

    /// `day` after this edit; a slot the day does not hold changes nothing.
    func applied(to day: DayTemplate) -> DayTemplate {
        switch self {
        case let .set(field, slot):
            DayEditing.set(field, slot: slot, in: day)
        case let .setProgression(progression, slot):
            DayEditing.setProgression(progression, slot: slot, in: day)
        case let .setDropSet(isOn, slot):
            DayEditing.setDropSet(isOn, slot: slot, in: day)
        case let .setSuperset(isOn, slot):
            DayEditing.setSuperset(isOn, slot: slot, in: day)
        case let .move(direction, slot):
            DayEditing.move(day, slot: slot, direction)
        case let .remove(slot):
            DayEditing.removeSlot(day, slot: slot)
        case let .add(slots):
            DayEditing.addSlots(day, slots)
        }
    }
}
