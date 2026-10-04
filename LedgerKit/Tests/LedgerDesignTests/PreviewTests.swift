#if DEBUG // the registries are Debug-only, like the previews; the test plans build Debug
    import Dependencies
    import LedgerDependencies
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F07 criterion 8 for LedgerDesign: every `#Preview` is a case of `DesignPreview`, and every case renders. Also
    /// the
    /// scan itself, and the package-wide rule that every module with a `#Preview` has a registry its tests check.
    extension RenderingSuites {
        @Suite("Previews (LedgerDesign)", .tags(.design))
        struct PreviewTests {
            @Test("Every #Preview in LedgerDesign is a DesignPreview case, by name, and every case has its #Preview")
            func registry_listsEveryPreview() throws {
                let names = try PreviewScan.previews(inModule: "LedgerDesign")
                #expect(!names.contains(nil), "a #Preview without a name cannot be listed")
                #expect(names.count == Set(names).count, "a name appears twice: \(names)")
                #expect(Set(names.compactMap(\.self)) == Set(DesignPreview.allCases.map(\.rawValue)))
            }

            @Test("Every preview renders", arguments: DesignPreview.allCases)
            func preview_renders(_ preview: DesignPreview) {
                #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 874)) { preview.content })
            }

            /// A view that reads a store key, as F08–F15's store-driven previews will: drawn as Xcode draws a preview,
            /// it
            /// gets the key's seeded preview value. In the test context the read would fail the test, naming the key.
            @Test("A preview that reads a store key renders with its preview value")
            func preview_readingAStoreKey_getsItsPreviewValue() {
                let seen = Seen()
                #expect(renderPreview(size: CGSize(width: SnapshotConfig.phoneWidth, height: 200)) {
                    ReadsAStore(seen: seen)
                })
                #expect(seen.repository.contains("InMemoryProgramRepository"), "\(seen.repository)")
            }

            @Test("Every module with a #Preview has a registry that its tests check")
            func everyModuleWithPreviews_isRegistered() throws {
                let modules = try PreviewScan.modulesWithPreviews()
                #expect(modules.isSubset(of: PreviewScan.registeredModules), "unregistered: \(modules)")
                #expect(
                    modules.contains("LedgerDesign"),
                    "the scan found no preview: \(PreviewScan.sourcesDirectory.path)"
                )
            }

            #if DEBUG
                @Test("The Diagnostics page shows durations in whole milliseconds, and identifies each value")
                func diagnosticsLine_formats() {
                    #expect(DiagnosticsLine.milliseconds(.microseconds(312_400)) == "312 ms")
                    #expect(DiagnosticsLine.milliseconds(.microseconds(312_600)) == "313 ms")
                    #expect(DiagnosticsLine.milliseconds(nil) == "Not measured")
                    #expect(DiagnosticsLine("exercise", "224", key: "rows.exercise")
                        .id == "debug.diagnostics.rows.exercise")
                }
            #endif

            @Test("The scan finds named and unnamed previews, after attributes and in CRLF files, but no look-alike")
            func scan_parsesDeclarations() {
                let source = """
                #Preview("Named") {
                    #Preview(  "Indented", traits: .sizeThatFitsLayout) {}
                #Preview {
                #Preview(traits: .sizeThatFitsLayout) {
                // #Preview("In a comment")
                let text = "#Preview(\\"In a string\\")"
                #PreviewLike("Another macro")
                @available(iOS 18, *) @MainActor  #Preview("Attributed") {
                @available(iOS 18, *) let notAPreview = 1
                """
                #expect(PreviewScan.previews(in: source) == ["Named", "Indented", nil, nil, "Attributed"])
                let crlf = "#Preview(\"First\") {}\r\n}\r\n#Preview(\"Second\") {}\r\n"
                #expect(PreviewScan.previews(in: crlf) == ["First", "Second"])
            }
        }
    }

    /// What `ReadsAStore` read.
    @MainActor
    final class Seen {
        var repository = ""
    }

    /// Reads `programRepository` in its body, as a store-driven preview does.
    struct ReadsAStore: View {
        @Dependency(\.programRepository) private var programs
        let seen: Seen

        var body: some View {
            seen.repository = String(describing: type(of: programs))
            return Text(seen.repository)
        }
    }
#endif
