import Testing

/// Tags live in the test target, not LedgerTestSupport (F00 implementation notes #6).
extension Tag {
    /// Every LedgerDesign suite (layer tag).
    @Tag static var design: Self
    /// Suites that compare against committed `__Snapshots__` references.
    @Tag static var snapshot: Self
}
