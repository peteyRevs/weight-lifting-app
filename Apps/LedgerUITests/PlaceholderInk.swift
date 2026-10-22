import UIKit

/// The placeholder's ink in a picture of the search field (F12-S1-5, review M1), against the colour of the pill's
/// ground on its middle row, inside its round end: the pill's strokes are the rows faintly inked across most of
/// its width; the placeholder is every other row and column that holds strong ink.
struct PlaceholderInk: CustomStringConvertible {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    let strokes: [Int]
    let rows: ClosedRange<Int>?
    let columns: ClosedRange<Int>?

    /// The least height for its width of a whole line of the placeholder drawn, by its text. Measured on the
    /// running app: "Search 224 exercises" 0.0744 at the default size and 0.0762 at Accessibility L, "Search"
    /// 0.236 at Accessibility XXXL (where the whole one does not fit). A third of either cut off falls under its
    /// floor; an unknown text has no floor and is a fault.
    static func leastAspect(of placeholder: String) -> Double? {
        switch placeholder {
        case "Search 224 exercises": 0.065
        case "Search": 0.2
        default: nil
        }
    }

    /// The field's trailing padding, `LedgerSpacing.l`, at the simulator's 3x.
    static let trailingPadding = 16 * 3

    init?(_ image: UIImage) {
        guard let picture = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var read = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
        let drawn = read.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: picture.width, height: picture.height, bitsPerComponent: 8,
                bytesPerRow: picture.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
            return true
        }
        guard drawn else {
            return nil
        }
        self.init(width: picture.width, height: picture.height, bytes: read)
    }

    private init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
        let base = Self.pixel(bytes, width, width / 40, height / 2)
        let span = (width / 8) ..< (width * 7 / 8)
        let differs = { (column: Int, row: Int, tolerance: Int) in
            zip(Self.pixel(bytes, width, column, row), base).contains { abs($0 - $1) > tolerance }
        }
        // The stroke is a faint hairline (`hairlineStrong`); the placeholder's grey stands well off the ground.
        var strokeRows: [Int] = []
        var inkRows: [Int] = []
        for row in 0 ..< height {
            if span.count(where: { differs($0, row, 8) }) > span.count * 4 / 5 {
                strokeRows.append(row)
            } else if span.contains(where: { differs($0, row, 40) }) {
                inkRows.append(row)
            }
        }
        strokes = strokeRows.enumerated()
            .filter { $0.offset == 0 || strokeRows[$0.offset - 1] != $0.element - 1 }
            .map(\.element)
        rows = inkRows.first.flatMap { first in inkRows.last.map { first ... $0 } }
        let inkColumns = (width / 40 ..< width - width / 40).filter { column in inkRows.contains { differs(
            column,
            $0,
            40
        ) } }
        columns = inkColumns.first.flatMap { first in inkColumns.last.map { first ... $0 } }
    }

    private static func pixel(_ bytes: [UInt8], _ width: Int, _ column: Int, _ row: Int) -> [Int] {
        (0 ..< 3).map { Int(bytes[(row * width + column) * 4 + $0]) }
    }

    var description: String {
        let ink = "ink rows \(String(describing: rows)), ink columns \(String(describing: columns))"
        return "strokes \(strokes), \(ink) of \(width)"
    }

    /// What is wrong with the ink of `placeholder`, the text drawn, a line each; none when it is drawn whole.
    func faults(of placeholder: String) -> [String] {
        guard let rows, let columns, strokes.count == 2, let top = strokes.first, let bottom = strokes.last else {
            return ["not read: \(self)"]
        }
        var faults: [String] = []
        if rows.lowerBound <= top + 2 || rows.upperBound >= bottom - 2 {
            faults.append("against a stroke: rows \(rows), strokes \(strokes)")
        }
        let aspect = Double(rows.count) / Double(columns.count)
        if let least = Self.leastAspect(of: placeholder) {
            if aspect < least {
                faults.append("too short for its width: \(rows.count) px tall, \(columns.count) px wide, \(aspect)")
            }
        } else {
            faults.append("an unknown placeholder: \"\(placeholder)\"")
        }
        if columns.upperBound >= width - Self.trailingPadding {
            faults.append("into the trailing padding: ink to column \(columns.upperBound) of \(width)")
        }
        return faults
    }

    /// This picture with the placeholder's lower third painted over with the pill's ground: a clipped placeholder.
    func clippingTheTextsLowerThird() -> UIImage {
        var doctored = bytes
        let base = Self.pixel(bytes, width, width / 40, height / 2)
        if let rows {
            for row in (rows.upperBound - rows.count / 3) ... rows.upperBound {
                for column in width / 40 ..< width - width / 40 {
                    for channel in 0 ..< 3 {
                        doctored[(row * width + column) * 4 + channel] = UInt8(base[channel])
                    }
                }
            }
        }
        return Self.image(doctored, width, height)
    }

    /// This picture with a column of the placeholder's ink drawn inside the trailing padding, where a placeholder
    /// cut short with "…" ends.
    func inkingTheTrailingPadding() -> UIImage {
        var doctored = bytes
        if let rows {
            for row in rows {
                for column in (width - Self.trailingPadding) ..< (width - Self.trailingPadding + 6) {
                    for channel in 0 ..< 3 {
                        doctored[(row * width + column) * 4 + channel] = 120
                    }
                }
            }
        }
        return Self.image(doctored, width, height)
    }

    private static func image(_ bytes: [UInt8], _ width: Int, _ height: Int) -> UIImage {
        var copy = bytes
        let context = copy.withUnsafeMutableBytes { buffer in
            CGColorSpace(name: CGColorSpace.sRGB).flatMap { space in
                CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            }?.makeImage()
        }
        return context.map { UIImage(cgImage: $0) } ?? UIImage()
    }
}
