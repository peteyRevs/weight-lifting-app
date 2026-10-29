#if DEBUG
    import LedgerDomain
    import LedgerFakes
    import SwiftUI

    /// Every preview in FeatureSettings, one case each: the states of Settings. Each is drawn from the model its
    /// presentation makes of a fixed input, so a preview shows the words the app would. `PreviewTests` render every
    /// case and fail on a `#Preview` that is not a case here; the snapshot and accessibility tests draw the same
    /// states' pages. None runs a task: the screen only draws.
    ///
    /// The About line is a stand-in's, never the app's own name or version, which only the app's bundle holds (N6).
    enum SettingsPreview: String, CaseIterable {
        /// A US lifter's: pounds, weeks from Sunday, and every switch on (`Settings.regional`'s for en_US).
        case pounds = "Settings"
        /// A lifter in kilograms, with a longer rest, weeks from Monday and two switches off.
        case kilograms = "Kilograms"
        /// The shortest rest, whose "−" is switched off, and the line of a save that failed.
        case saveFailed = "Couldn't save"

        func model() -> SettingsModel {
            SettingsPresentation.make(SettingsPreviewData.input(for: self))
        }

        /// The screen in this state.
        var content: some View {
            SettingsScreen(model: model()) { _ in }
        }
    }

    /// The fixed inputs of the previews.
    nonisolated enum SettingsPreviewData {
        static let about = AppAbout(name: "App", version: "1.2.3", build: "45")

        static func input(for preview: SettingsPreview) -> SettingsInput {
            var settings = Settings.regional(locale: Fixtures.locale, calendar: Fixtures.calendar)
            switch preview {
            case .pounds:
                break
            case .kilograms:
                settings.units = .kg
                settings.defaultRest = RestDuration(clampingSeconds: 150)
                settings.weekStart = .monday
                settings.plateMathEnabled = false
                settings.watchBuzz = false
            case .saveFailed:
                settings.defaultRest = RestDuration(clampingSeconds: 30)
            }
            return SettingsInput(
                settings: settings,
                about: about,
                saveFailed: preview == .saveFailed,
                locale: Fixtures.locale,
                calendar: Fixtures.calendar
            )
        }
    }

    #Preview("Settings") {
        SettingsPreview.pounds.content
    }

    #Preview("Kilograms") {
        SettingsPreview.kilograms.content
    }

    #Preview("Couldn't save") {
        SettingsPreview.saveFailed.content
    }
#endif
