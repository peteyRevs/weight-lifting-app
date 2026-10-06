import LedgerDesign
import SwiftUI

/// A screen whose feature has not landed yet: its title alone, where the real screen will draw its own. The
/// Program, Library and History tabs show one until F11–F13 replace them, and so does a pushed destination, so a
/// route always arrives somewhere a test can see. The UI tests find the title by `identifier`.
struct PlaceholderScreen: View {
    private let title: String
    private let identifier: String

    init(_ title: String, identifier: String) {
        self.title = title
        self.identifier = identifier
    }

    var body: some View {
        Text(title)
            .ledgerFont(.display)
            .foregroundStyle(LedgerColor.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
            .padding(LedgerSpacing.screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LedgerColor.ground)
    }
}
