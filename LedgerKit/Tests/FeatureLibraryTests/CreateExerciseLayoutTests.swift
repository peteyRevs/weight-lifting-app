#if os(iOS) && DEBUG
    @testable import FeatureLibrary
    import LedgerDesign
    import LedgerSnapshotTesting
    import SwiftUI
    import Testing
    import UIKit

    /// F12 S3, by measurement, as `LibraryLayoutTests` measures the Library: at every text size, with Bold Text and
    /// laid out right to left (`LibraryLayoutTests.Setting.all`, through `TestSweep`), every stop of every state of
    /// the exercise sheet has a size, stands inside the page, is over no other stop and, when it can be tapped, is a
    /// 44 pt target. The eleven muscle chips wrap onto many lines at the largest sizes (risk R4).
    @Suite("Exercise sheet layout", .serialized, .tags(.feature))
    struct CreateExerciseLayoutTests {
        typealias Setting = LibraryLayoutTests.Setting

        @Test(
            "In every state and setting no stop is empty, outside the page, under 44 points or over another",
            arguments: CreatePreview.allCases, Setting.all
        )
        func parts_layOutSanely(_ preview: CreatePreview, _ setting: Setting) {
            let stops = LibraryLayoutTests.placed(CreateParts(preview), setting)
            #expect(stops.count >= 40, "the parts were not read")
            let faults = LibraryLayoutTests.faults(in: stops.map { item in
                // A switch is a target too.
                item.stop.kind == .toggle
                    ? PlacedStop(stop: .button(item.stop.label), frame: item.frame) : item
            })
            #expect(faults.isEmpty, "\(faults.prefix(4).joined(separator: "\n"))")
        }

        @Test(
            "The title keeps its line beside Cancel, and Cancel stands under it at accessibility sizes",
            arguments: Setting.all
        )
        func header_titleAndCancel(_ setting: Setting) throws {
            let stops = LibraryLayoutTests.placed(CreateParts(.edit), setting)
            let title = try #require(stops.first { $0.stop == .heading("Edit exercise") }).frame
            let cancel = try #require(stops.first { $0.stop == .button("Cancel") }).frame
            if setting.size.isAccessibilitySize {
                #expect(cancel.minY >= title.maxY - 0.5, "Cancel stands under the title")
            } else {
                #expect(cancel.midY > title.minY && cancel.midY < title.maxY, "Cancel stands beside the title")
            }
        }

        /// F15-S2-11: at Accessibility XXXL the one-line field drew "Landmine Squ…". The name is drawn as text that
        /// wraps under the field, so the field grows by every line the name takes beyond its first. At the
        /// accessibility sizes, where one line and its padding are taller than the 44 pt target, which would
        /// otherwise take up some of the growth.
        @Test(
            "A long name is drawn whole: the field grows by the lines the name wraps onto",
            arguments: [DynamicTypeSize.accessibility3, .accessibility5]
        )
        func name_longerThanItsLine_isDrawnWhole(_ size: DynamicTypeSize) {
            let width: CGFloat = 353 // the iPhone 17's width inside the sheet's margins
            let inner = width - 2 * LedgerSpacing.m
            func height(_ view: some View, _ wide: CGFloat) -> CGFloat {
                let sized = view.frame(width: wide).environment(\.dynamicTypeSize, size)
                return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: wide, height: 5000)).height
            }
            func field(_ text: String) -> some View {
                CreateExerciseNameField(model: .init(label: "Name", text: text, problem: nil)) { _ in }
            }
            let name = "Landmine Squeeze Press with a Three-Second Pause"
            let lines = height(Text(name).ledgerFont(.body), inner) - height(Text("N").ledgerFont(.body), inner)
            let grows = height(field(name), width) - height(field("N"), width)
            #expect(lines > 0, "the name is longer than one line at \(size)")
            #expect(grows >= lines - 0.5, "the field grows \(grows) pt for \(lines) pt of further lines at \(size)")
        }

        /// As Program's `NameField`: a name of only spaces shows the placeholder over an unseen line of the label, so
        /// the field keeps an empty name's one line and nothing under it moves at the first space typed.
        @Test(
            "A name of only spaces keeps the field as high as an empty name",
            arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility5]
        )
        func blankName_keepsTheEmptyFieldsHeight(_ size: DynamicTypeSize) {
            let width: CGFloat = 353
            func height(_ text: String) -> CGFloat {
                let field = CreateExerciseNameField(model: .init(label: "Name", text: text, problem: nil)) { _ in }
                let sized = field.frame(width: width).environment(\.dynamicTypeSize, size)
                return UIHostingController(rootView: sized).sizeThatFits(in: CGSize(width: width, height: 5000)).height
            }
            let (empty, blank) = (height(""), height("   "))
            #expect(empty > 44, "the field was not measured at \(size): \(empty) pt")
            #expect(abs(blank - empty) < 0.5, "at \(size) a blank name is \(blank) pt high, an empty one \(empty) pt")
        }
    }
#endif
