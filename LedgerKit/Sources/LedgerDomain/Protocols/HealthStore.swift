import Foundation

/// HealthKit access (architecture §9). Shape only: the full contract lands in F16, implemented by
/// `LiveHealthStore` in LedgerHealth and `FakeHealthStore` in LedgerFakes.
public protocol HealthStore: Sendable {}
