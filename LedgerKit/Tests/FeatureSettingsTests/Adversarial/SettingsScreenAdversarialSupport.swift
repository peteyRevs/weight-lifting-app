#if os(iOS) && DEBUG
    @testable import FeatureSettings
    import Foundation
    import LedgerDesign
    import LedgerDomain
    @testable import LedgerSnapshotTesting
    import LedgerTestSupport
    import Observation
    import SwiftUI
    import Testing
    import UIKit

    /// The page over a store, drawn again whenever the store's model changes: the screen without its scroll view,
    /// so the hosted reader can see every row while the store runs.
    struct LiveSettingsPage: View {
        let store: SettingsStore

        var body: some View {
            if let model = store.model {
                SettingsPage(model: model, send: store.send)
                    .background(LedgerColor.ground)
            }
        }
    }

    /// F14 S1b, G2: the words of a translation, drawn in place of the English (what a catalog with another
    /// language would hand the presentation), for `SettingsScreenAdversarialTests`.
    @MainActor
    enum SettingsWords {
        /// The words of a translation, drawn in place of the English: what a catalog with another language would
        /// hand the presentation.
        struct Words {
            var title, problem, training, units, unitsDetail: String
            var spoken: [String]
            var rest, restDetail, week, weekDetail, weekValue: String
            var days: [String]
            var switches: [(String, String)]
            var data, health, notConnected, diagnostics, about: String
            var options = ["LB", "KG"]
        }

        static let german = Words(
            title: "Einstellungen",
            problem: "Diese Änderung konnte nicht gespeichert werden.",
            training: "TRAINING",
            units: "Gewichtseinheiten",
            unitsDetail: "Gilt für jedes Trainingsprotokoll und jedes Diagramm",
            spoken: ["Pfund", "Kilogramm"],
            rest: "Standardpausenzeit",
            restDetail: "Wird für neu hinzugefügte Übungen verwendet",
            week: "Die Woche beginnt am",
            weekDetail: "Für die Wochenleiste und die Wochensummen",
            weekValue: "Donnerstag",
            days: ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"],
            switches: [
                ("Hantelscheibenrechner", "Zeigt bei jedem Satz die Scheiben pro Seite der Langhantel"),
                ("Automatischer Pausentimer", "Startet die Uhr, sobald ein Satz eingetragen wurde"),
                ("Haptisches Signal der Apple Watch bei null", "Lässt das Handgelenk vibrieren, wenn die Pause endet")
            ],
            data: "DATEN",
            health: "Apple Health",
            notConnected: "Nicht verbunden",
            diagnostics: "Diagnosedaten",
            about: "Ledger 0.15.0 · Build 74"
        )

        static let finnish = Words(
            title: "Asetukset",
            problem: "Muutosta ei voitu tallentaa.",
            training: "HARJOITTELU",
            units: "Painoyksiköt",
            unitsDetail: "Koskee jokaista harjoituskirjausta ja kaaviota",
            spoken: ["paunaa", "kilogrammaa"],
            rest: "Oletuslepoaika",
            restDetail: "Käytetään uusille liikkeille",
            week: "Viikko alkaa",
            weekDetail: "Viikkonauhaa ja viikon yhteismääriä varten",
            weekValue: "keskiviikko",
            days: ["sunnuntai", "maanantai", "tiistai", "keskiviikko", "torstai", "perjantai", "lauantai"],
            switches: [
                ("Levypainolaskuri", "Näyttää levyt tangon kummallekin puolelle jokaisessa sarjassa"),
                ("Automaattinen lepoajastin", "Käynnistää kellon, kun sarja kirjataan"),
                ("Apple Watchin tuntopalaute nollassa", "Värisyttää rannetta, kun lepoaika päättyy")
            ],
            data: "TIEDOT",
            health: "Apple Terveys",
            notConnected: "Ei yhdistetty",
            diagnostics: "Diagnostiikka",
            about: "Ledger 0.15.0 · koontiversio 74"
        )

        static let arabic = Words(
            title: "الإعدادات",
            problem: "تعذّر حفظ هذا التغيير.",
            training: "التدريب",
            units: "الوحدات",
            unitsDetail: "تنطبق على كل سجل ومخطط",
            spoken: ["رطل", "كيلوغرام"],
            rest: "الراحة الافتراضية",
            restDetail: "تُستخدم للتمارين الجديدة",
            week: "يبدأ الأسبوع يوم",
            weekDetail: "لشريط الأسبوع ومجاميعه",
            weekValue: "السبت",
            days: ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"],
            switches: [
                ("حساب الأقراص", "إظهار الأقراص لكل جانب في كل مجموعة"),
                ("مؤقت الراحة التلقائي", "بدء الساعة عند تسجيل مجموعة"),
                ("اهتزاز الساعة عند الصفر", "اهتزاز المعصم عند انتهاء الراحة")
            ],
            data: "البيانات",
            health: "Apple Health",
            notConnected: "غير متصل",
            diagnostics: "التشخيص",
            about: "Ledger 0.15.0 · الإصدار 74"
        )

        /// A Tamil lifter's week, whose Thursday is one of the longest weekday names any locale gives.
        static var tamil: Words {
            var words = german
            words.weekValue = "வியாழக்கிழமை"
            words.days = [
                "ஞாயிற்றுக்கிழமை",
                "திங்கட்கிழமை",
                "செவ்வாய்க்கிழமை",
                "புதன்கிழமை",
                "வியாழக்கிழமை",
                "வெள்ளிக்கிழமை",
                "சனிக்கிழமை"
            ]
            return words
        }

        /// The save-failed state of the previews, in `words`.
        static func model(_ words: Words) -> SettingsModel {
            let base = SettingsPreview.saveFailed.model()
            return SettingsModel(
                title: words.title,
                problem: words.problem,
                training: words.training,
                units: SettingsModel.Units(
                    title: words.units,
                    detail: words.unitsDetail,
                    options: base.units.options.enumerated().map { index, option in
                        SettingsModel.Option(
                            id: option.id, title: words.options[index], spokenLabel: words.spoken[index],
                            isSelected: option.isSelected, action: option.action
                        )
                    }
                ),
                rest: SettingsModel.Rest(
                    title: words.rest, detail: words.restDetail, value: base.rest.value,
                    spokenValue: base.rest.spokenValue, decrement: base.rest.decrement, increment: base.rest.increment
                ),
                weekStart: SettingsModel.WeekStart(
                    title: words.week, detail: words.weekDetail, value: words.weekValue,
                    days: base.weekStart.days.map { day in
                        SettingsModel.Day(id: day.id, title: words.days[day.id % 7], action: day.action)
                    },
                    selected: base.weekStart.selected
                ),
                switches: zip(base.switches, words.switches).map { row, text in
                    SettingsModel.Switch(
                        id: row.id, title: text.0, detail: text.1, isOn: row.isOn, action: row.action
                    )
                },
                data: words.data,
                health: SettingsModel.Status(title: words.health, value: words.notConnected),
                diagnostics: base.diagnostics.map { SettingsModel.Link(title: words.diagnostics, action: $0.action) },
                about: words.about
            )
        }

        static func page(_ words: Words) -> some View {
            SettingsPage(model: model(words), send: { _ in }).background(LedgerColor.ground)
        }
    }
#endif
