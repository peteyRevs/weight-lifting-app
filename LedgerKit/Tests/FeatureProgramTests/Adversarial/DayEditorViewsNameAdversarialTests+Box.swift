#if os(iOS) && DEBUG
    import LedgerSnapshotTesting
    import SwiftUI

    extension DayEditorViewsNameAdversarialTests.Shown {
        /// The box of `box(_:)` in a drawing already made, so that one drawing can be measured twice. Row by
        /// row through the buffer's storage: the tests run unoptimized, where walking the 1.9 million pixels of
        /// a drawing at 3× by index and division took about 150 ms a box (110 ms this way; 2026-10-20).
        func box(in drawn: PixelBuffer, _ isIncluded: (Pixel) -> Bool) -> CGRect {
            var (minX, minY, maxX, maxY) = (Int.max, Int.max, -1, -1)
            drawn.pixels.withUnsafeBufferPointer { pixels in
                for down in 0 ..< drawn.height {
                    let row = down * drawn.width
                    for across in 0 ..< drawn.width where isIncluded(pixels[row + across]) {
                        (minX, maxX) = (min(minX, across), max(maxX, across))
                        (minY, maxY) = (min(minY, down), max(maxY, down))
                    }
                }
            }
            guard maxX >= 0 else {
                return .null
            }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                .applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
        }

        /// `letters()` in a drawing already made.
        func letters(in drawn: PixelBuffer) -> CGRect {
            box(in: drawn) { $0.red > 150 && $0.green > 150 }
        }
    }
#endif
