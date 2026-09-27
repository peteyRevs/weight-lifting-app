import Foundation
@testable import LedgerDomain
import Testing

@Suite("Volume", .tags(.domain))
struct VolumeTests {
    @Test("A set's volume is weight × reps in gram·reps (rule 34)")
    func init_weightTimesReps() throws {
        let volume = try Volume(weight: .pounds(185), reps: Fixtures.reps(5))
        #expect(volume.gramReps == dec("83914.58845") * 5)
        #expect(volume.formatted(in: .lb) == "925")
    }

    @Test("Formatted volume is whole units with thousands separators (rule 34)")
    func formatted_thousandsSeparators() {
        let volume = Volume(gramReps: Weight.pounds(24180).grams)
        #expect(volume.formatted(in: .lb) == "24,180")
        #expect(Volume(gramReps: 1_000_000_000).formatted(in: .kg) == "1,000,000")
        #expect(Volume.zero.formatted(in: .lb) == "0")
        #expect(Volume(gramReps: -Weight.pounds(1500).grams).formatted(in: .lb) == "-1,500")
    }

    @Test("Compact volume is thousands to one decimal plus k (rule 34)")
    func compact_oneDecimalK() {
        #expect(Volume(gramReps: Weight.pounds(24180).grams).compact(in: .lb) == "24.2k")
        #expect(Volume(gramReps: Weight.pounds(41200).grams).compact(in: .lb) == "41.2k")
        #expect(Volume(gramReps: Weight.pounds(24000).grams).compact(in: .lb) == "24.0k")
        #expect(Volume(gramReps: Weight.pounds(460).grams).compact(in: .lb) == "0.5k")
        #expect(Volume(gramReps: 1_234_500_000).compact(in: .kg) == "1,234.5k")
    }

    @Test("Volume is exact at any horizon: 1,000 reps of 185 lb is 185,000 lb moved (ADR-007)")
    func sum_isExact_noDrift() throws {
        let set = try Volume(weight: .pounds(185), reps: Fixtures.reps(1))
        let lifetime = (0 ..< 1000).reduce(Volume.zero) { total, _ in total + set }
        #expect(lifetime.formatted(in: .lb) == "185,000")
        #expect(lifetime == Volume(weight: .pounds(185_000), reps: .one))
    }

    @Test("Volumes add, subtract and order by gram·reps")
    func arithmetic_andOrder() {
        let small = Volume(gramReps: 100)
        let large = Volume(gramReps: 350)
        #expect(small + large == Volume(gramReps: 450))
        #expect(large - small == Volume(gramReps: 250))
        #expect(small < large)
        #expect([small, large].reduce(.zero, +) == Volume(gramReps: 450))
    }

    @Test("Volume encodes as gram·reps and decodes back")
    func codable_roundTrips() throws {
        let volume = Volume(gramReps: 419_575)
        let data = try JSONEncoder().encode(volume)
        #expect(try Fixtures.json(volume) == #"{"gramReps":"419575"}"#)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Volume.self, from: Data(#"{"gramReps":419575}"#.utf8))
        }
        #expect(try JSONDecoder().decode(Volume.self, from: data) == volume)
    }
}
