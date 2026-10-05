import Testing

/// The tags live in the test target, not LedgerTestSupport, as in `LedgerDomainTests` (F02 notes): tags there
/// would pull swift-testing into every target that links it.
extension Tag {
    /// Every LedgerSync suite (layer tag, testing-strategy §6).
    @Tag static var sync: Self
    /// Seeded property-style tests; the case count comes from `LEDGER_PROPERTY_SEED_COUNT`.
    @Tag static var property: Self
}
