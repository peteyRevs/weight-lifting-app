import CoreText
import Foundation

/// Builds Archivo instances at arbitrary points on its `wght` and `wdth` axes.
///
/// The axes are set with a Core Text variation attribute (`kCTFontVariationAttribute`) on a
/// descriptor for the variable font's default instance. That path renders both axes on iOS 26.5
/// and watchOS 26.5 (the F06 spike, `ArchivoFontTests`), so no static-instance fallback exists.
/// `CTFontDescriptor` is the Core Text type `UIFontDescriptor` bridges to; using it directly keeps
/// UIKit out of font code and works on every platform the package builds for.
nonisolated enum ArchivoFont {
    /// PostScript name of the variable font's default instance (wght 600, wdth 100).
    static let postScriptName = "Archivo-SemiBold"
    /// OpenType axis tags as Core Text identifiers: 'wght' and 'wdth'.
    static let weightAxis = 0x7767_6874
    static let widthAxis = 0x7764_7468
    /// The ranges in the font's `fvar` table; requests outside them are clamped.
    static let weightRange: ClosedRange<CGFloat> = 100 ... 900
    static let widthRange: ClosedRange<CGFloat> = 62 ... 125
    /// Half of ascent minus descent in em (.878 and .210 at every axis position): how far below the
    /// middle of a CSS line box a lone line's baseline sits.
    static let baselineBelowMiddle: CGFloat = {
        let font = make(size: 1, weight: 400, width: 100)
        return (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2
    }()

    static func make(size: CGFloat, weight: CGFloat, width: CGFloat, tabularDigits: Bool = false) -> CTFont {
        FontRegistration.registerIfNeeded()
        var attributes: [CFString: Any] = [
            kCTFontNameAttribute: postScriptName,
            kCTFontVariationAttribute: [
                weightAxis: min(max(weight, weightRange.lowerBound), weightRange.upperBound),
                widthAxis: min(max(width, widthRange.lowerBound), widthRange.upperBound)
            ]
        ]
        if tabularDigits {
            attributes[kCTFontFeatureSettingsAttribute] = [[
                kCTFontFeatureTypeIdentifierKey: kNumberSpacingType,
                kCTFontFeatureSelectorIdentifierKey: kMonospacedNumbersSelector
            ]]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Whether Core Text resolves the name to Archivo rather than silently substituting a
    /// fallback face.
    static var isResolvable: Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == postScriptName
    }
}
