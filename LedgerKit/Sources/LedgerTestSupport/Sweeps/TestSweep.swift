#if DEBUG
    import Foundation
    #if canImport(SwiftUI)
        import SwiftUI
    #endif

    /// How wide a test's sweep of settings runs (docs/ci-cd.md, "Sweeps on the runner"). Read from
    /// `LEDGER_SWEEP`: unset, as in the full local gate, the nightly and `swift test`, every sweep runs in full.
    /// `pr`, which only the hosted PR job sets (as `TEST_RUNNER_LEDGER_SWEEP`, which `xcodebuild` hands to the
    /// test runner without its prefix), keeps a representative part of each sweep that asks through here. Every
    /// reduced sweep is a subset of the full one, so nothing can fail on the runner that the full gate passes,
    /// unless a test reads a swept list's count or the positions of its elements.
    public enum TestSweep {
        /// Whether this run keeps only a sweep's representatives (`LEDGER_SWEEP=pr`).
        public static let isReduced = ProcessInfo.processInfo.environment["LEDGER_SWEEP"] == "pr"

        /// `all`, or, in a reduced run, the elements `isRepresentative` keeps, in their order. A sweep with
        /// no representative keeps its first element: a test given no argument would pass with no case run.
        public static func subset<Element>(
            _ all: [Element],
            keeping isRepresentative: (Element) -> Bool
        ) -> [Element] {
            guard isReduced else {
                return all
            }
            let kept = all.filter(isRepresentative)
            return kept.isEmpty ? Array(all.prefix(1)) : kept
        }

        #if canImport(SwiftUI)
            /// The text sizes a reduced sweep keeps: the smallest, where targets fall under 44 pt; the default;
            /// the largest that is not an accessibility size, where a row still lays its parts side by side;
            /// and the largest, where words wrap most. `DayEditorLayoutTests.fewSizes` already draws these four
            /// as its representatives.
            public static let representativeSizes: Set<DynamicTypeSize> = [
                .xSmall, .large, .xxxLarge, .accessibility5
            ]

            /// `sizes`, or, in a reduced run, those of them that are `representativeSizes` or `also`: a test
            /// pinned to a finding at another size names it in `also`.
            public static func sizes(
                _ sizes: [DynamicTypeSize],
                also: Set<DynamicTypeSize> = []
            ) -> [DynamicTypeSize] {
                subset(sizes) { representativeSizes.contains($0) || also.contains($0) }
            }
        #endif
    }
#endif
