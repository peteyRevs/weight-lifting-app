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

/// A button of the model as an outlined pill; one that carries no action is drawn disabled.
struct ControlPill: View {
    let control: ProgramBuilderModel.Control
    let send: (ProgramBuilderAction) -> Void

    var body: some View {
        PillButton(control.title) {
            if let action = control.action {
                send(action)
            }
        }
        .disabled(control.action == nil)
    }
}
