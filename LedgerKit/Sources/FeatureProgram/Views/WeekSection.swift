import LedgerDesign
import SwiftUI

/// The selected week: its title with "Tap to assign" beside it, the schedule strip, and the week's three
/// actions as pills that wrap: "Copy week 2" (on the first week "First week", disabled), "Apply to later
/// weeks" (not drawn on the last week, which has none after it) and "Deload", filled while the week is one.
///
/// The title of a deload week, "WEEK 8 · DELOAD", is orange: it is one string of the model and is tinted
/// whole, never split here.
struct WeekSection: View {
    let model: ProgramBuilderModel.SelectedWeek
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.m) {
            SectionLine(eyebrow: model.title, tint: model.deload.isOn ? .accent : .muted, note: model.hint)
            ScheduleStrip(cells: model.cells, send: send)
            WrapLayout {
                ControlPill(control: model.copyPrevious, send: send)
                if let applyToLater = model.applyToLater {
                    ControlPill(control: applyToLater, send: send)
                }
                PillButton(model.deload.title, style: model.deload.isOn ? .filled : .outline) {
                    send(model.deload.action)
                }
            }
        }
    }
}

/// A button of a model as an outlined pill, on either screen; one that carries no action is drawn disabled.
struct ControlPill<Action>: View {
    let title: String
    let action: Action?
    let send: (Action) -> Void

    var body: some View {
        PillButton(title) {
            if let action {
                send(action)
            }
        }
        .disabled(action == nil)
    }
}

extension ControlPill where Action == ProgramBuilderAction {
    init(control: ProgramBuilderModel.Control, send: @escaping (ProgramBuilderAction) -> Void) {
        self.init(title: control.title, action: control.action, send: send)
    }
}

extension ControlPill where Action == DayEditorAction {
    /// A control of the Day editor always carries its action.
    init(control: DayEditorModel.Control, send: @escaping (DayEditorAction) -> Void) {
        self.init(title: control.title, action: control.action, send: send)
    }
}
