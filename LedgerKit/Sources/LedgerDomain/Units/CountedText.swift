import Foundation

// The one place that decides the locale a counted text is looked up with (standards §7, "Localization").
//
// It is here, and not in a feature, because every feature that has a catalog needs it and features do not
// import one another; it is Foundation alone, and every feature already depends on this module. It formats
// nothing and names no text: the Domain's own strings stay locale-independent (`NumberText`). A module binds
// it to its own catalog once, in its copy file: `var forCountedText: Locale { forCountedText(in: .module) }`.

public extension Locale {
    /// The locale a counted text of `catalog` is looked up with: this locale with its language replaced by
    /// the language the catalog answers in. A lookup takes its words from the catalog and picks their plural
    /// form by its locale's language, so with the lifter's own locale an English text would take another
    /// language's form: "Add 1 exercises" in Japanese, which has no singular, "Add 21 exercise" in Russian,
    /// "0 rep" in French.
    ///
    /// It reads two things and nothing of the device: the languages the catalog holds
    /// (`catalog.localizations`), and this locale, the one the copy member was handed. Of those languages it
    /// takes the one that fits this locale best, which is English while the catalog holds only English. The
    /// region and the numbering system stay this locale's, so the number is still written as the lifter
    /// writes numbers: its digits, and its region's grouping.
    func forCountedText(in catalog: Bundle) -> Locale {
        let fitting = Bundle.preferredLocalizations(
            from: catalog.localizations,
            forPreferences: [identifier(.bcp47)]
        )
        var components = Locale.Components(locale: self)
        if let resolved = fitting.first {
            var language = Locale.Language.Components(identifier: resolved)
            language.region = language.region ?? region
            components.languageComponents = language
        }
        components.numberingSystem = numberingSystem
        return Locale(components: components)
    }
}
