@testable import LedgerDomain
import Testing

@Suite("Loadable", .tags(.domain))
struct LoadableTests {
    private struct LoadFailure: Error, Equatable {
        let code: Int
    }

    /// A value that is not `Sendable`.
    private final class Draft {
        var text = "draft"
    }

    /// What a screen would say for each case. The switch has no `default`, so it compiles only while
    /// the cases are exactly the four of engineering-standards §5.
    private static func summary(of state: Loadable<Int>) -> String {
        switch state {
        case .idle: "idle"
        case .loading: "loading"
        case let .loaded(value): "loaded \(value)"
        case let .failed(error): "failed \(error)"
        }
    }

    /// Compiles only for a `Sendable` value, as a hand-over between isolations does.
    private static func handedOver<Value: Sendable>(_ value: Value) -> Value {
        value
    }

    /// Whether a type is `Sendable`: the compiler takes this overload when the type conforms,
    private static func isSendable(_: (some Sendable).Type) -> Bool {
        true
    }

    /// and this one when it does not.
    private static func isSendable(_: (some Any).Type) -> Bool {
        false
    }

    @Test("A load state is idle, loading, loaded with its value or failed with its error (standards §5)")
    func cases_carryTheirPayloads() {
        #expect(Self.summary(of: .idle) == "idle")
        #expect(Self.summary(of: .loading) == "loading")
        #expect(Self.summary(of: .loaded(8)) == "loaded 8")
        #expect(Self.summary(of: .failed(LoadFailure(code: 7))) == "failed LoadFailure(code: 7)")
        guard case let .failed(error) = Loadable<Int>.failed(LoadFailure(code: 7)) else {
            Issue.record("A failed state did not match .failed")
            return
        }
        #expect(error as? LoadFailure == LoadFailure(code: 7))
    }

    @Test("A load state is Sendable when its value is and only then, and holds a value that is not")
    func sendable_whenItsValueIs() {
        // The two overloads tell a Sendable type from one that is not.
        #expect(Self.isSendable(Int.self))
        #expect(!Self.isSendable(Draft.self))
        #expect(Self.isSendable(Loadable<Int>.self))
        #expect(Self.isSendable(Loadable<[String]>.self))
        #expect(!Self.isSendable(Loadable<Draft>.self))
        #expect(!Self.isSendable(Loadable<[Draft]>.self))
        #expect(Self.summary(of: Self.handedOver(.loaded(3))) == "loaded 3")
        #expect(Self.summary(of: Self.handedOver(.failed(LoadFailure(code: 1)))) == "failed LoadFailure(code: 1)")
        guard case let .loaded(draft) = Loadable.loaded(Draft()) else {
            Issue.record("A loaded state did not match .loaded")
            return
        }
        #expect(draft.text == "draft")
    }
}
