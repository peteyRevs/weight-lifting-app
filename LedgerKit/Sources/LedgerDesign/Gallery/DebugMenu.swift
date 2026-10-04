#if DEBUG
    import SwiftUI

    /// The debug menu (F07 criterion 7), which a long press on Today's title opens on either device: `DesignGallery`
    /// and the app's `DiagnosticsPage`, whose sections the caller reads. Debug builds only, like the gallery.
    ///
    /// The UI tests find its rows by their identifiers, `debug.menu.designGallery` and `debug.menu.diagnostics`.
    public struct DebugMenu: View {
        enum Page: Hashable {
            case designGallery, diagnostics
        }

        // The screen's inset and ground: the watch's, or the phone's.
        #if os(watchOS)
            private let page = (inset: LedgerSpacing.m, ground: LedgerColor.watchGround)
        #else
            private let page = (inset: LedgerSpacing.screen, ground: LedgerColor.ground)
        #endif

        private let diagnostics: () async -> [DiagnosticsSection]
        @State private var path: [Page] = []

        public init(diagnostics: @escaping () async -> [DiagnosticsSection]) {
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
