import Foundation
@testable import LedgerDomain
import Testing

/// F09 S2 criterion 4 and engineering-standards §5: `Loadable<Value>` has exactly the cases `idle`,
/// `loading`, `loaded(Value)` and `failed(any Error)`, and is `Sendable` when its value is. Neither
/// text promises equality or accessors, so none is asserted.
@Suite("Loadable (adversarial, F09 S2)", .tags(.domain))
struct LoadableAdversarialTests {
    struct Model: Equatable {
        var title: String
        var rows: [Int]
    }

    /// A value that is not `Sendable`.
    final class Reference {
        var count = 0
    }

    enum Failure: Error, Equatable {
        case offline
        case corrupt(row: Int)
    }

    /// Exhaustive with no `default`: a fifth case, a missing one or a renamed one stops this file compiling.
    static func name(_ state: Loadable<some Any>) -> String {
        switch state {
        case .idle: "idle"
        case .loading: "loading"
        case .loaded: "loaded"
        case .failed: "failed"
        }
    }

    static func value<T>(of state: Loadable<T>) -> T? {
        if case let .loaded(value) = state {
            return value
        }
        return nil
    }

    static func error(of state: Loadable<some Any>) -> (any Error)? {
        if case let .failed(error) = state {
            return error
        }
        return nil
    }

    static func isSendable(_: (some Sendable).Type) -> Bool {
        true
    }

    static func isSendable(_: (some Any).Type) -> Bool {
        false
    }
}

extension LoadableAdversarialTests {
    @Test("The four states of standards §5 exist, are distinct, and are the only ones.")
    func loadable_fourCases_areDistinctAndExhaustive() {
        let states: [Loadable<Model>] = [
            .idle, .loading, .loaded(Model(title: "Today", rows: [1])), .failed(Failure.offline)
        ]
        #expect(states.map(Self.name) == ["idle", "loading", "loaded", "failed"])
        #expect(states.compactMap(Self.value(of:)) == [Model(title: "Today", rows: [1])])
        #expect(states.compactMap(Self.error(of:)).count == 1)
    }

    @Test("loaded carries the value it was given, whatever the value's type.")
    func loadable_loaded_carriesItsValue() throws {
        let model = Model(title: "Lower A", rows: [5, 5, 5, 5])
        #expect(Self.value(of: Loadable.loaded(model)) == model)
        #expect(Self.value(of: Loadable.loaded([1, 2, 3])) == [1, 2, 3])
        // An optional value stays apart from the states: loaded(nil) is loaded, not idle.
        let nothing: Loadable<Int?> = .loaded(nil)
        #expect(Self.name(nothing) == "loaded")
        #expect(try #require(Self.value(of: nothing)) == nil)
        let unit: Loadable<Void> = .loaded(())
        #expect(Self.name(unit) == "loaded")
        let nested: Loadable<Loadable<Int>> = .loaded(.loading)
        #expect(try Self.name(#require(Self.value(of: nested))) == "loading")
        let reference = Reference()
        #expect(Self.value(of: Loadable.loaded(reference)) === reference)
        #expect(Self.value(of: Loadable<Model>.idle) == nil)
        #expect(Self.value(of: Loadable<Model>.loading) == nil)
        #expect(Self.value(of: Loadable<Model>.failed(Failure.offline)) == nil)
    }

    @Test("failed carries the error it was given, of any error type, and no value.")
    func loadable_failed_carriesItsError() throws {
        let state: Loadable<Model> = .failed(Failure.corrupt(row: 7))
        #expect(try #require(Self.error(of: state)) as? Failure == .corrupt(row: 7))
        #expect(Self.name(state) == "failed")
        let cancelled: Loadable<Int> = .failed(CancellationError())
        #expect(try #require(Self.error(of: cancelled)) is CancellationError)
        let foreign: Loadable<Int> = .failed(NSError(domain: "adversarial", code: 42))
        #expect(try (#require(Self.error(of: foreign)) as NSError).code == 42)
        let existential: any Error = Failure.offline
        #expect(Self.error(of: Loadable<Int>.failed(existential)) as? Failure == .offline)
        #expect(Self.error(of: Loadable<Int>.idle) == nil)
        #expect(Self.error(of: Loadable<Int>.loaded(1)) == nil)
    }

    @Test("Loadable is Sendable when its value is, and only then.")
    func loadable_sendable_followsItsValue() async {
        #expect(Self.isSendable(Loadable<Int>.self))
        #expect(Self.isSendable(Loadable<String?>.self))
        #expect(Self.isSendable(Loadable<[ScheduledDay]>.self))
        #expect(Self.isSendable(Loadable<Loadable<Volume>>.self))
        #expect(Self.isSendable(Loadable<Void>.self))
        #expect(!Self.isSendable(Loadable<Reference>.self))
        #expect(!Self.isSendable(Loadable<[Reference]>.self))
        #expect(!Self.isSendable(Loadable<Loadable<Reference>>.self))
        // A Sendable state crosses a task boundary whole.
        let state: Loadable<Volume> = .loaded(Volume(gramReps: 5))
        let crossed = await Task { state }.value
        #expect(Self.value(of: crossed) == Volume(gramReps: 5))
        let failed: Loadable<Volume> = .failed(Failure.corrupt(row: 3))
        let error = await Task { failed }.value
        #expect(Self.error(of: error) as? Failure == .corrupt(row: 3))
    }
}
