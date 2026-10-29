#if os(iOS) && DEBUG
    // A copy of FeatureLibraryTests' `ViewStop`, itself FeatureProgramTests' (test targets cannot share a helper
    // outside LedgerTestSupport).
    import LedgerSnapshotTesting
    import SwiftUI
    import UIKit

    /// One VoiceOver stop of a hosted view, as the views' tests compare it: what kind of stop it is, what is
    /// read, its value and its hint, whether it is selected or dimmed, and whether it says that it is expanded
    /// or collapsed. Printed on one line, so a failure shows a line and never a tree.
    nonisolated struct ViewStop: Equatable, Sendable, CustomStringConvertible {
        enum Kind: String, Sendable {
            case text, heading, button, adjustable
            /// A switch: its value is "1" when on and "0" when off.
            case toggle
            /// A text field: neither a button nor static text.
            case field
        }

        let kind: Kind
        let label: String
        var value = ""
        var hint = ""
        var isSelected = false
        var isEnabled = true
        /// What a disclosure says of itself; `none` for every other stop.
        var disclosure = Disclosure.none

        enum Disclosure: Sendable {
            case none, expanded, collapsed
        }

        static func text(_ label: String, value: String = "") -> Self {
            Self(kind: .text, label: label, value: value)
        }

        static func heading(_ label: String, value: String = "") -> Self {
            Self(kind: .heading, label: label, value: value)
        }

        static func button(_ label: String, value: String = "", hint: String = "", selected: Bool = false) -> Self {
            Self(kind: .button, label: label, value: value, hint: hint, isSelected: selected)
        }

        static func dimmedButton(_ label: String) -> Self {
            Self(kind: .button, label: label, isEnabled: false)
        }

        static func adjustable(_ label: String, value: String) -> Self {
            Self(kind: .adjustable, label: label, value: value)
        }

        static func field(_ label: String, value: String = "") -> Self {
            Self(kind: .field, label: label, value: value)
        }

        /// A row that opens a panel under itself: a button that says whether it is expanded.
        static func row(_ label: String, value: String, isOpen: Bool = false) -> Self {
            Self(kind: .button, label: label, value: value, disclosure: isOpen ? .expanded : .collapsed)
        }

        /// The chosen one of a row of chips, where the model gives it no action: selected, and no button.
        static func chosen(_ label: String) -> Self {
            Self(kind: .text, label: label, isSelected: true)
        }

        static func toggle(_ label: String, isOn: Bool, hint: String) -> Self {
            Self(kind: .toggle, label: label, value: isOn ? "1" : "0", hint: hint)
        }

        var description: String {
            "\(kind.rawValue) \"\(label)\"" + (value.isEmpty ? "" : " = \"\(value)\"")
                + (hint.isEmpty ? "" : " hint \"\(hint)\"") + (isSelected ? " (selected)" : "")
                + (isEnabled ? "" : " (dimmed)") + (disclosure == .none ? "" : " (\(disclosure))")
        }
    }

    extension ViewStop {
        /// The stop UIKit hands VoiceOver for `element`. A stop that is a heading, a switch, a button or
        /// adjustable is that; of the rest, static text is text and anything else a field.
        init(reading element: NSObject) {
            let traits = element.accessibilityTraits
            let kind: Kind =
                if traits.contains(.header) {
                    .heading
                } else if traits.contains(.adjustable) {
                    .adjustable
                } else if traits.contains(.toggleButton) {
                    .toggle
                } else if traits.contains(.button) {
                    .button
                } else if traits.contains(.staticText) {
                    .text
                } else {
                    .field
                }
            self.init(
                kind: kind,
                label: element.accessibilityLabel ?? "",
                value: element.accessibilityValue ?? "",
                hint: element.accessibilityHint ?? "",
                isSelected: traits.contains(.selected),
                isEnabled: !traits.contains(.notEnabled),
                disclosure: Self.disclosure(of: element)
            )
        }
    }

    extension ViewStop {
        private static func disclosure(of element: NSObject) -> Disclosure {
            switch element.accessibilityExpandedStatus {
            case .expanded: .expanded
            case .collapsed: .collapsed
            default: .none
            }
        }
    }

    /// A stop with where it stands in the hosting window.
    nonisolated struct PlacedStop {
        let stop: ViewStop
        let frame: CGRect
    }

    extension View {
        /// The view's VoiceOver stops, in order.
        func stops(_ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large)) -> [ViewStop] {
            withAccessibilityElements(appearance) { $0.map(ViewStop.init(reading:)) }
        }

        /// The view's VoiceOver stops with their frames.
        func placedStops(_ appearance: SnapshotAppearance = SnapshotAppearance(.light, .large)) -> [PlacedStop] {
            withAccessibilityElements(appearance) { elements in
                elements.map { PlacedStop(stop: ViewStop(reading: $0), frame: $0.accessibilityFrame) }
            }
        }
    }

    /// The first place two trees differ, as one short line, or nil when they are the same. A test expects this
    /// to be nil and so never hands a whole tree to `#expect`.
    nonisolated func firstDifference(found: [ViewStop], expected: [ViewStop]) -> String? {
        for (index, pair) in zip(found, expected).enumerated() where pair.0 != pair.1 {
            return "stop \(index + 1): found \(pair.0), expected \(pair.1)"
        }
        guard found.count != expected.count else {
            return nil
        }
        let extra = found.count > expected.count ? found[expected.count] : expected[found.count]
        return "found \(found.count) stops, expected \(expected.count); the first one more is \(extra)"
    }
#endif
