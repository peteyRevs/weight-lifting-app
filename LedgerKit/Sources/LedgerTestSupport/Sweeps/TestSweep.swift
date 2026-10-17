#if DEBUG
    import Foundation
    #if canImport(SwiftUI)
        import SwiftUI
    #endif

    /// How wide a test's sweep of settings runs (docs/ci-cd.md, "Sweeps on the runner"). Read from
    /// `LEDGER_SWEEP`: unset, as in the full local gate, the nightly and `swift test`, every sweep runs in full.
    /// `pr`, which only the hosted PR job sets (as `TEST_RUNNER_LEDGER_SWEEP`, which `xcodebuild` hands to the
    /// test runner without its prefix), keeps a representative part of each sweep that asks through here. Every
    /// reduced sweep is a subset of the full one, so nothing can fail on the runner that the full gate passes.
    public enum TestSweep {
        /// Whether this run keeps only a sweep's representatives (`LEDGER_SWEEP=pr`).
        public static let isReduced = ProcessInfo.processInfo.environment["LEDGER_SWEEP"] == "pr"

        /// `all`, or, in a reduced run, the elements `isRepresentative` keeps, in their order. A sweep with
        /// no representative keeps its first element, so no test loses all its cases.
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
            /// and the largest, where words wrap most. The four the suites already draw as their representatives
            /// (`DayEditorLayoutTests.fewSizes`, `ProgramViewsLayoutTests`).
            public static let representativeSizes: Set<DynamicTypeSize> = [
                .xSmall, .large, .xxxLarge, .accessibility5
            ]

            /// `sizes`, or, in a reduced run, those of them that are `representativeSizes`, `also`, or the
            /// first or the last of `sizes`: a sweep that starts or ends elsewhere keeps its own ends.
            public static func sizes(
                _ sizes: [DynamicTypeSize],
                also: Set<DynamicTypeSize> = []
            ) -> [DynamicTypeSize] {
                subset(sizes) { size in
                    representativeSizes.contains(size) || also.contains(size)
                        || size == sizes.first || size == sizes.last
                }
            }
        #endif
    }
#endif
