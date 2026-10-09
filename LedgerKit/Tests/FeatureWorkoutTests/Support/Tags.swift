import Testing

/// Tags live in the test target, as in every other one (F02 notes: tags in LedgerTestSupport would pull
/// swift-testing into the features, which link it).
extension Tag {
    /// Every FeatureWorkout suite (layer tag).
    @Tag static var feature: Self
    /// Suites that compare against committed reference images.
    @Tag static var snapshot: Self
}
