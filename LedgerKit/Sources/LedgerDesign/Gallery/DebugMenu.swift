#if DEBUG
    import SwiftUI

    /// The debug menu (F07 criterion 7), which a long press on Today's title opens on either device: `DesignGallery`
    /// and the app's `DiagnosticsPage`, whose sections the caller reads, then the rows the composition root adds
    /// (`actions`). Debug builds only, like the gallery.
    ///
    /// The UI tests find its rows by their identifiers, `debug.menu.designGallery` and `debug.menu.diagnostics`,
    /// and an added row by the identifier its action names.
    public struct DebugMenu: View {
        enum Page: Hashable {
            case designGallery, diagnostics
        }

        /// A row a composition root adds under the menu's own: a title, the identifier the UI tests find it
        /// by, and what a tap does. The menu does not close itself; the caller's `perform` does that when the
        /// row leads somewhere else.
        public struct Action {
            let title: String
            let identifier: String
            let perform: @MainActor () -> Void

            public init(_ title: String, identifier: String, perform: @escaping @MainActor () -> Void) {
                self.title = title
                self.identifier = identifier
                self.perform = perform
            }
        }

        // The screen's inset and ground: the watch's, or the phone's.
        #if os(watchOS)
            private let page = (inset: LedgerSpacing.m, ground: LedgerColor.watchGround)
        #else
            private let page = (inset: LedgerSpacing.screen, ground: LedgerColor.ground)
        #endif

        private let actions: [Action]
        private let diagnostics: () async -> [DiagnosticsSection]
        @State private var path: [Page] = []

        public init(actions: [Action] = [], diagnostics: @escaping () async -> [DiagnosticsSection]) {
            self.actions = actions
            self.diagnostics = diagnostics
        }

        public var body: some View {
            NavigationStack(path: $path) {
                ScrollView {
                    HairlineList {
                        HairlineRow("Design gallery", action: { path.append(.designGallery) })
                            .accessibilityIdentifier("debug.menu.designGallery")
                        HairlineRow("Diagnostics", action: { path.append(.diagnostics) })
                            .accessibilityIdentifier("debug.menu.diagnostics")
                        ForEach(actions, id: \.identifier) { action in
                            HairlineRow(action.title, action: action.perform)
                                .accessibilityIdentifier(action.identifier)
                        }
                    }
                    .padding(.horizontal, page.inset)
                }
                .background(page.ground)
                .navigationTitle("Debug")
                .navigationDestination(for: Page.self) { destination in
                    switch destination {
                    case .designGallery: DesignGallery()
                    case .diagnostics: DiagnosticsLoader(load: diagnostics)
                    }
                }
            }
        }
    }
#endif
