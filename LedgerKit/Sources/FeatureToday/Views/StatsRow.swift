import LedgerDesign
import SwiftUI

/// The week in two numbers (v2: "3/4 sessions this week", "41.2k lb moved · +8%") over a rule. Each tile is
/// F06's `StatTile`, handed the model's tile field for field, its spoken text included; at accessibility text
/// sizes `StatTileRow` stands them one under the other.
struct StatsRow: View {
    let model: TodayModel.Stats

    var body: some View {
        VStack(spacing: LedgerSpacing.xl) {
            StatTileRow {
                tile(model.sessions)
                tile(model.volume)
            }
            HairlineRule()
        }
    }

    private func tile(_ tile: TodayModel.Tile) -> StatTile {
        StatTile(
            value: tile.value,
            unit: tile.unit,
            caption: tile.caption,
            delta: tile.delta,
            accessibilitySummary: tile.accessibilitySummary
        )
    }
}
