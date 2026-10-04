#if DEBUG
    import SwiftUI

    /// One line of the Diagnostics page: a label and its value. The value carries the accessibility identifier
    /// `debug.diagnostics.<key>`, which the UI tests read.
    public struct DiagnosticsLine: Identifiable, Equatable, Sendable {
        public let label: String
        public let value: String
        public let id: String

        public init(_ label: String, _ value: String, key: String) {
            self.label = label
            self.value = value
            id = "debug.diagnostics.\(key)"
        }

        /// A duration in whole milliseconds ("312 ms"), or "Not measured".
        public static func milliseconds(_ duration: Duration?) -> String {
            duration.map { "\(Int(($0 / .milliseconds(1)).rounded())) ms" } ?? "Not measured"
        }
    }

    /// A titled group of lines.
    public struct DiagnosticsSection: Identifiable, Equatable, Sendable {
        public let title: String
        public let lines: [DiagnosticsLine]

        public var id: String {
            title
        }

        public init(_ title: String, lines: [DiagnosticsLine]) {
            self.title = title
            self.lines = lines
        }
    }

    /// The app's Diagnostics page (F07 criterion 7): each section under its eyebrow, in the phone's or the watch's
    /// type. Its colours are the phone palette's, which the watch's dark appearance resolves to light on dark.
    /// `DebugMenu` reads the sections when the page opens (`DiagnosticsLoader`); this view only draws them.
    public struct DiagnosticsPage: View {
        private let sections: [DiagnosticsSection]

        public init(sections: [DiagnosticsSection]) {
            self.sections = sections
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: LedgerSpacing.xl) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: LedgerSpacing.s) {
                            Eyebrow(section.title)
                            HairlineList { ForEach(section.lines, content: lineView) }
                        }
                    }
                }
                .padding(Self.inset)
            }
            .background(LedgerColor.ground)
            .navigationTitle("Diagnostics")
        }

        private func lineView(_ line: DiagnosticsLine) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                HairlineRule()
                VStack(alignment: .leading, spacing: LedgerSpacing.xs) {
                    Text(line.label).ledgerFont(Self.labelRole).foregroundStyle(LedgerColor.inkMuted)
                    Text(line.value)
                        .ledgerFont(Self.valueRole)
                        .foregroundStyle(LedgerColor.ink)
                        .accessibilityIdentifier(line.id)
                }
                .padding(.vertical, LedgerSpacing.s)
            }
        }

        #if os(watchOS)
            private static let inset = LedgerSpacing.m
            private static let labelRole = LedgerFont.Role.watchCaption
            private static let valueRole = LedgerFont.Role.watchTitle
        #else
            private static let inset = LedgerSpacing.screen
            private static let labelRole = LedgerFont.Role.label
            private static let valueRole = LedgerFont.Role.body
        #endif
    }

    /// Reads the sections when it appears, then shows them: the Diagnostics destination of `DebugMenu`. Apart from
    /// the page so that previews and their smoke tests draw the page with no appearance action (an `ImageRenderer`
    /// that drew one inside a scroll view traps when released, measured on the iOS and watchOS 27.0 simulators).
    struct DiagnosticsLoader: View {
        let load: () async -> [DiagnosticsSection]
        @State private var sections: [DiagnosticsSection] = []

        var body: some View {
            DiagnosticsPage(sections: sections)
                .task {
                    sections = await load()
                }
        }
    }
#endif
