import LedgerDesign
import SwiftUI

/// "Delete all data"'s sheet (criterion 6.2), drawn from its model and nothing else: the design system's sheet frame,
/// with "Cancel" at its title, the page between, and "Delete everything", dimmed until the typed word matches, pinned
/// at the foot. A sheet whose content scrolls is a screen that scrolls (the M1 convention): `DeleteAllPage` is what
/// scrolls, its one layout at every text size. While the erase runs the sheet cannot be swiped away. Nothing on it
/// wears the accent (C28).
struct DeleteAllSheet: View {
    let model: DeleteAllSheetModel
    let send: (SettingsAction) -> Void

    var body: some View {
        DeleteAllChrome(model: model, send: send) {
            ScrollView {
                DeleteAllPage(model: model, send: send)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isErasing)
    }
}

/// The sheet's frame around `page`: the title with "Cancel", which sends `cancelDeleteAll`, then the page, then the
/// pinned foot. The sheet puts the page in its scroll view; the tests read the frame around the page alone.
struct DeleteAllChrome<Page: View>: View {
    let model: DeleteAllSheetModel
    let send: (SettingsAction) -> Void
    @ViewBuilder let page: Page

    var body: some View {
        SheetChrome(
            model.title,
            cancel: model.cancel,
            cancelIdentifier: "settings.deleteAll.cancel",
            cancelEnabled: !model.isErasing,
            onCancel: cancel
        ) {
            page
            DeleteAllFoot(model: model, send: send)
        }
    }

    private func cancel() {
        send(.cancelDeleteAll)
    }
}

/// The sheet's pinned foot: a rule, the system's spinner named "Deleting…" while the erase runs, then "Delete
/// everything", full width and ink, dimmed while it does nothing.
struct DeleteAllFoot: View {
    let model: DeleteAllSheetModel
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(spacing: LedgerSpacing.m) {
            HairlineRule()
            if let progress = model.progress {
                ProgressView()
                    .accessibilityLabel(progress)
            }
            PillButton(model.confirmTitle, fillsWidth: true) {
                if let confirm = model.confirm {
                    send(confirm)
                }
            }
            .disabled(model.confirm == nil)
            .accessibilityIdentifier("settings.deleteAll.confirm")
        }
    }
}

/// What the sheet scrolls, and never a scroll view: "This can't be undone.", the field for the typed word, under its
/// label, and the line of an erase that failed.
struct DeleteAllPage: View {
    let model: DeleteAllSheetModel
    let send: (SettingsAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.l) {
            Text(model.message)
                .ledgerFont(.body)
                .foregroundStyle(LedgerColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            DeleteAllField(model: model, send: send)
            if let problem = model.problem {
                Text(problem)
                    .ledgerFont(.caption)
                    .foregroundStyle(LedgerColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, LedgerSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The typed word: its label over a one-line field in an outlined box, at least 44 pt high, whose placeholder is the
/// word and whose spoken label is the label. It takes capitals and no corrections, and hands each change on as typed.
struct DeleteAllField: View {
    let model: DeleteAllSheetModel
    let send: (SettingsAction) -> Void
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
            Text(model.prompt)
                .ledgerFont(.label)
                .foregroundStyle(LedgerColor.inkMuted)
                .accessibilityHidden(true)
            TextField(text: binding, prompt: Text(model.word).foregroundStyle(LedgerColor.inkFaint)) {
                Text(model.prompt)
            }
            .ledgerFieldFont(.body)
            .foregroundStyle(LedgerColor.ink)
            .autocorrectionDisabled()
            .characterCapitalization()
            .submitLabel(.done)
            .focused($isEditing)
            .disabled(model.isErasing)
            // A field with a placeholder is not named by its label view: say what to type (found on the simulator,
            // F14-S3 G3 SF3).
            .accessibilityLabel(model.prompt)
            .accessibilityIdentifier("settings.deleteAll.field")
            .padding(.horizontal, LedgerSpacing.m)
            .padding(.vertical, LedgerSpacing.s)
            .ledgerHitTarget(alignment: .leading)
            .onTapGesture { isEditing = true }
            .background {
                RoundedRectangle(cornerRadius: LedgerRadius.row)
                    .strokeBorder(LedgerColor.hairlineStrong, lineWidth: LedgerHairline.width)
            }
        }
    }

    /// The text as given, and a text that differs from it handed on as typed.
    private var binding: Binding<String> {
        Binding { model.text } set: {
            if $0 != model.text {
                send(.setDeleteText($0))
            }
        }
    }
}

private extension View {
    /// The keyboard starts in capitals, as the word is written; the Mac host's build, which has no such keyboard,
    /// leaves the field as it is.
    @ViewBuilder func characterCapitalization() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.characters)
        #else
            self
        #endif
    }
}
