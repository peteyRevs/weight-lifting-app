#if os(iOS)
    @testable import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import UIKit

    /// `AccessibilityTreeTests`' tables for `ReceiptLayout` (F10 S7b): each tile one stop, the records line,
    /// "LOGGED" a heading, then each row one stop; the note beside "LOGGED" is no stop. The same at the
    /// largest size of the matrix, where everything stacks, and mirrored. With a row action (F12 S3), each row
    /// is a button.
    extension TreeTables {
        nonisolated static let receipts: [TreeCase] = [
            TreeCase("ReceiptLayout gallery", receiptGallery) { ReceiptLayoutGallery() },
            TreeCase(
                "ReceiptLayout gallery, stacked at accessibility3",
                at: SnapshotAppearance(.dark, .accessibility3),
                receiptGallery
            ) { ReceiptLayoutGallery() },
            TreeCase("ReceiptLayout gallery, right to left: the same order", receiptGallery) {
                ReceiptLayoutGallery().environment(\.layoutDirection, .rightToLeft)
            },
            TreeCase("ReceiptLayout with a row action: each row is one button (F12 S3)", receiptGalleryWithRowAction) {
                ReceiptLayoutGallery { _ in }
            },
            TreeCase(
                "ReceiptLayout with a row action, stacked at accessibility3",
                at: SnapshotAppearance(.dark, .accessibility3),
                receiptGalleryWithRowAction
            ) { ReceiptLayoutGallery { _ in } },
            TreeCase(
                "ReceiptLayout with no records line and no row",
                [.text("TIME, 0 seconds"), .text("0 of 0 sets logged"), .text("0 lb moved"), .text("LOGGED", .header)]
            ) {
                ReceiptLayout(model: ReceiptLayout.Model(
                    tiles: [
                        ReceiptLayout.Tile(label: "TIME", value: "0:00", spoken: "TIME, 0 seconds", isAccented: true),
                        ReceiptLayout.Tile(label: "SETS", value: "0/0", spoken: "0 of 0 sets logged"),
                        ReceiptLayout.Tile(label: "LB MOVED", value: "0", spoken: "0 lb moved")
                    ],
                    records: nil,
                    logged: "LOGGED",
                    note: "Prescribed on the right",
                    rows: []
                ))
            }
        ]

        /// The gallery's stops with a row action: the rows are buttons, read as before.
        nonisolated static let receiptGalleryWithRowAction: [TreeNode] = ReceiptLayoutGallery.model.tiles
            .map { .text($0.spoken) } + [.text("1 new PR this session"), .text("LOGGED", .header)]
            + ReceiptLayoutGallery.model.rows.map { .button($0.spoken) }

        /// The gallery's stops, in reading order.
        nonisolated static let receiptGallery: [TreeNode] = ReceiptLayoutGallery.model.tiles.map { .text($0.spoken) }
            + [.text("1 new PR this session"), .text("LOGGED", .header)]
            + ReceiptLayoutGallery.model.rows.map { .text($0.spoken) }
    }
#endif
