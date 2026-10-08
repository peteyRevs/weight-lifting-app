#if os(iOS)
    @testable import FeatureToday
    import Foundation
    import LedgerDesign
    import LedgerDomain
    import LedgerSnapshotTesting
    import LedgerTestSupport
    import SwiftUI
    import Testing

    /// F09 S4, gate G2: what VoiceOver finds on the page (criterion 7) and what each stop does (criterion 6).
    /// The expected tree is `TodayViews.expectedStops`, written from the specification before the views' bodies
    /// and the implementer's pinned trees were read; the literal lines below are the brief's worked examples.
    @Suite("Adversarial F09 S4 · the page's tree and actions", .tags(.feature))
    struct TodayViewsTreeAdversarialTests {
        @Test("The fixtures build: thirteen real states and seven inconsistent models")
        func fixtures_build() throws {
            #expect(try ViewsCases.real().count == 13)
            #expect(try ViewsCases.inconsistent().count == 7)
            #expect(ViewsCases.all.count == 13 && ViewsCases.odd.count == 7)
        }

        @Test("Every state reads exactly the tree the specification gives for its model", arguments: ViewsCases.all)
        func page_tree_isTheModels(_ item: ViewsCase) {
            let found = TodayViews.stops(of: TodayViews.page(item))
            let difference = TodayViews.difference(found: found, expected: TodayViews.expectedStops(for: item.state))
            #expect(difference.isEmpty, "\(item.name): \(difference.joined(separator: "\n"))")
        }

        @Test("The tree is the same at the largest accessibility size and in the dark", arguments: ViewsCases.all)
        func page_tree_isTheSameAtAccessibility5(_ item: ViewsCase) {
            let found = TodayViews.stops(of: TodayViews.page(item), at: SnapshotAppearance(.dark, .accessibility5))
            let difference = TodayViews.difference(found: found, expected: TodayViews.expectedStops(for: item.state))
            #expect(difference.isEmpty, "\(item.name): \(difference.joined(separator: "\n"))")
        }

        @Test("A model that contradicts itself is drawn as it stands, and nothing else", arguments: ViewsCases.odd)
        func page_inconsistentModel_isDrawnAsGiven(_ item: ViewsCase) {
            let found = TodayViews.stops(of: TodayViews.page(item))
            let difference = TodayViews.difference(found: found, expected: TodayViews.expectedStops(for: item.state))
            #expect(difference.isEmpty, "\(item.name): \(difference.joined(separator: "\n"))")
        }

        @Test(
            "No stop is read twice, is empty, or is both a button and a heading",
            arguments: ViewsCases.all
        )
        func page_stops_areDistinctAndNamed(_ item: ViewsCase) {
            let found = TodayViews.stops(of: TodayViews.page(item))
            let unnamed = found.filter { $0.label.trimmingCharacters(in: .whitespaces).isEmpty }
            #expect(unnamed.isEmpty, "\(item.name): \(unnamed.count) stops with nothing to read")
            #expect(!found.contains { $0.role == .buttonHeading }, "\(item.name)")
            // The seed program names no two things alike, so a label met twice is a part read twice.
            let labels = found.map { "\($0.label)|\($0.value)" }
            let repeated = Set(labels.filter { label in labels.count(where: { $0 == label }) > 1 })
            #expect(repeated.isEmpty, "\(item.name): read twice: \(repeated.sorted().prefix(4))")
        }

        @Test("The brief's first example reads as the brief words it (criteria 1 and 13)")
        func upNextWednesday_readsTheBriefsWords() throws {
            let item = try #require(ViewsCases.all.first { $0.name == "up next, no history" })
            let found = TodayViews.stops(of: TodayViews.page(item)).map(\.description)
            let expectedHead = [
                "text \"Wednesday, September 16\"", "heading \"Lower A\"", "button \"Settings\"",
                "text \"Monday, September 14\" = \"Planned\"", "text \"Tuesday, September 15\" = \"Rest day\"",
                "text \"Wednesday, September 16\" = \"Today\"", "text \"Thursday, September 17\" = \"Rest day\"",
                "text \"Friday, September 18\" = \"Planned\"", "text \"Saturday, September 19\" = \"Planned\"",
                "text \"Sunday, September 20\" = \"Rest day\"", "heading \"UP NEXT\""
            ]
            for (index, line) in expectedHead.enumerated() {
                #expect(index < found.count && found[index] == line, "stop \(index + 1): expected \(line)")
            }
            #expect(found.contains("text \"Lower A — Squat focus\""))
            #expect(found.contains("button \"Start workout\""))
            #expect(found.suffix(2) == [
                "heading \"RECENT\"",
                "text \"No sessions yet. Your first workout lands here.\""
            ])
            #expect(found.count(where: { $0.hasPrefix("button") }) == 2, "the gear and Start workout alone")
        }

        @Test("Each card stands under exactly one heading, and the screen has one title", arguments: ViewsCases.all)
        func page_headings_areTheTitleTheCardAndRecent(_ item: ViewsCase) throws {
            guard let model = item.model else {
                return
            }
            let headings = TodayViews.stops(of: TodayViews.page(item)).filter { $0.role == .heading }.map(\.label)
            let card = try #require(TodayViews.cardStops(model.card).first?.label)
            #expect(headings == [model.header.title, card, model.recent.eyebrow], "\(item.name): \(headings)")
        }
    }

    // MARK: - Actions

    extension TodayViewsTreeAdversarialTests {
        @Test(
            "Each button sends exactly its model's route or action, once; nothing else sends anything",
            arguments: ViewsCases.all + ViewsCases.odd
        )
        func page_activation_sendsTheModelsAction(_ item: ViewsCase) {
            let sent = TodayViews.Sent()
            let results = TodayViews.activations(of: TodayViews.page(item, sent: sent), sent: sent)
            let fromText = results.filter { $0.stop.role != .button && !$0.sent.isEmpty }.map(\.stop.description)
            #expect(fromText.isEmpty, "\(item.name): a stop that is no button sent an action: \(fromText)")
            let perButton = results.filter { $0.stop.role == .button }.map(\.sent.count)
            #expect(perButton.allSatisfy { $0 == 1 }, "\(item.name): actions per button \(perButton)")
            let expected = item.model.map(TodayViews.expectedActions(for:)) ?? []
            #expect(sent.actions.count == expected.count, "\(item.name): \(sent.actions.count) actions sent")
            for (index, action) in expected.enumerated() where index < sent.actions.count {
                #expect(sent.actions[index] == action, "\(item.name): button \(index + 1)")
            }
        }

        @Test("Start emits the brief's route for Lower A in week 1, and Resume emits resumeWorkout (criteria 2, 3)")
        func primaryButton_emitsTheBriefsRoutes() throws {
            let program = try TodayAdversarial.seed()
            let lowerA = try TodayAdversarial.day("LA", in: program)
            for (name, title, route) in [
                (
                    "up next",
                    "Start workout",
                    TodayRoute.startWorkout(program: program.id, weekIndex: 0, day: lowerA.id)
                ),
                ("live workout", "Resume · 3:00", TodayRoute.resumeWorkout)
            ] {
                let item = try #require(ViewsCases.all.first { $0.name == name })
                let sent = TodayViews.Sent()
                let results = TodayViews.activations(of: TodayViews.page(item, sent: sent), sent: sent)
                let button = try #require(results.first { $0.stop.label == title }, "\(name): no \(title)")
                #expect(button.sent == [.route(route)], "\(name)")
            }
        }

        @Test("Activating a button twice sends its action twice and no more: the view holds no state of its own")
        func page_secondActivation_sendsAgain() throws {
            let item = try #require(ViewsCases.all.first { $0.name == "up next" })
            let sent = TodayViews.Sent()
            TodayViews.page(item, sent: sent).withAccessibilityElements { elements in
                for element in elements where element.accessibilityLabel == "Start workout" {
                    _ = element.accessibilityActivate()
                    _ = element.accessibilityActivate()
                }
            }
            #expect(sent.actions.count == 2)
        }

        @Test("A disabled page sends nothing and says every button is dimmed", arguments: ViewsCases.all)
        func page_disabled_doesNothing(_ item: ViewsCase) {
            let sent = TodayViews.Sent()
            let results = TodayViews.activations(of: TodayViews.page(item, sent: sent).disabled(true), sent: sent)
            #expect(sent.actions.isEmpty, "\(item.name): \(sent.actions.count) actions from a disabled page")
            let bright = results.filter { $0.stop.role == .button && $0.stop.isEnabled }.map(\.stop.label)
            #expect(bright.isEmpty, "\(item.name): not dimmed: \(bright)")
        }
    }
#endif
