import LedgerDomain
import SwiftUI

/// The iPhone's announcements (F10 S7): each text is posted as one accessibility announcement, which
/// VoiceOver speaks when it is running and nobody hears otherwise.
struct LiveAnnouncements: AnnouncementsClient {
    func announce(_ text: String) async {
        await MainActor.run {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
