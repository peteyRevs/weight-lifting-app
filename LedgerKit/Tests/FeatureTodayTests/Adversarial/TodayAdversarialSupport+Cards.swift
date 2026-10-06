@testable import FeatureToday
import Foundation

// MARK: - Reading a model's card

nonisolated extension TodayAdversarial {
    /// The model shows another card than the test is about.
    struct WrongCard: Error, CustomStringConvertible {
        let description: String

        init(_ card: TodayModel.Card, expected: String) {
            description = "the card is \(TodayOracle.name(of: card)), expected \(expected)"
        }
    }

    static func upNext(_ model: TodayModel) throws -> TodayModel.UpNext {
        guard case let .upNext(card) = model.card else {
            throw WrongCard(model.card, expected: "Up next")
        }
        return card
    }

    static func logged(_ model: TodayModel) throws -> TodayModel.Logged {
        guard case let .logged(card) = model.card else {
            throw WrongCard(model.card, expected: "Logged")
        }
        return card
    }

    static func rest(_ model: TodayModel) throws -> TodayModel.RestDay {
        guard case let .restDay(card) = model.card else {
            throw WrongCard(model.card, expected: "Rest day")
        }
        return card
    }

    static func blockComplete(_ model: TodayModel) throws -> TodayModel.Message {
        guard case let .blockComplete(card) = model.card else {
            throw WrongCard(model.card, expected: "Block complete")
        }
        return card
    }

    static func noProgram(_ model: TodayModel) throws -> TodayModel.Message {
        guard case let .noProgram(card) = model.card else {
            throw WrongCard(model.card, expected: "No program")
        }
        return card
    }
}

// MARK: - Every text of a model

nonisolated extension TodayAdversarial {
    /// Every `String` a value holds, however deep: what a model draws or speaks.
    static func texts(in value: Any) -> [String] {
        if let text = value as? String {
            return [text]
        }
        return Mirror(reflecting: value).children.flatMap { texts(in: $0.value) }
    }

    /// `LedgerKit/Sources/FeatureToday`, from this file's place in the repository.
    static let sources = URL(filePath: #filePath)
        .deletingLastPathComponent() // Adversarial
        .deletingLastPathComponent() // FeatureTodayTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // LedgerKit
        .appending(path: "Sources/FeatureToday")
}
