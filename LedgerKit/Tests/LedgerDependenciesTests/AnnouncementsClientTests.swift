import Dependencies
import Foundation
@testable import LedgerDependencies
import LedgerDomain
import LedgerTestSupport
import Testing

/// F10 S7a, criterion 20: the announcements client. Its stub cannot throw, so it logs and returns; its
/// fake records; a preview gets the fake; and `withTestDependencies` gives the key a recording fake, a new
/// one for each call, as it does for `haptics`.
@Suite("Device clients: announcements")
struct AnnouncementsClientTests {
    @Test("The stub returns from its call, having said nothing, under the key's name")
    func stub_returns() async {
        await AnnouncementsKey.liveValue.announce("Rest over")
        #expect(AnnouncementsKey.liveValue is UnimplementedAnnouncements)
        #expect(UnimplementedAnnouncements().stub.key == "announcements")
    }

    @Test("The fake keeps what it was asked to say, in order")
    func fake_records() async {
        let announcements = FakeAnnouncements()
        #expect(await announcements.announced == [])
        await announcements.announce("Rest, 1 minute, 30 seconds remaining")
        await announcements.announce("Rest over")
        #expect(await announcements.announced == ["Rest, 1 minute, 30 seconds remaining", "Rest over"])
    }

    @Test("In a preview the key is the fake")
    func preview_isTheFake() {
        withDependencies {
            $0.context = .preview
        } operation: {
            @Dependency(\.announcements) var announcements
            #expect(announcements is FakeAnnouncements)
        }
    }

    @Test("withTestDependencies gives announcements a fake of its own for each call; without it the key fails")
    func announcements_defaultToAFreshFake() async {
        let first = withTestDependencies {
            @Dependency(\.announcements) var announcements
            return announcements
        }
        let second = withTestDependencies {
            @Dependency(\.announcements) var announcements
            return announcements
        }
        let fake = first as? FakeAnnouncements
        #expect(fake != nil)
        #expect(fake !== (second as? FakeAnnouncements), "no fake is shared between two tests")
        await first.announce("Rest over")
        #expect(await fake?.announced == ["Rest over"])
        #expect(await (second as? FakeAnnouncements)?.announced == [])
        withKnownIssue {
            @Dependency(\.announcements) var announcements
            _ = announcements
        } matching: { issue in
            issue.description.contains("@Dependency(\\.announcements)")
        }
    }
}
