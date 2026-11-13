import XCTest

/// The appearance a UI test launches the app in (fix/tabs-audit), and the proof that the app drew in it.
///
/// The app's, not the device's: on the iOS 27.0 simulator (iPhone 17, on this Mac and on the nightly's runner)
/// `XCUIDevice.shared.appearance = .dark` and `simctl ui appearance dark` both read back dark while every app, the
/// system's Settings too, goes on drawing light, so a test that asked for dark that way audited and measured light
/// (the nightly's "Today-dark" tab bar picture, run 43364073342, is light). `-LEDGER_UITEST_APPEARANCE` makes the
/// app itself draw in the appearance asked for (`UITestAppearance` in LedgerAppKit, Debug builds only).
enum LaunchAppearance: String, CaseIterable {
    case light, dark

    /// What to add to the app's launch arguments.
    var launchArguments: [String] {
        ["-LEDGER_UITEST_APPEARANCE", rawValue]
    }

    /// Whether `level`, a mean of red, green and blue from 0 to 255, is this appearance's ground: paper, #EFEDE6
    /// (236), in light and #0B0B0D (11) in dark, with room for the status bar's ink over it.
    func isGround(_ level: Int) -> Bool {
        self == .dark ? level < 60 : level > 180
    }
}

extension XCTestCase {
    /// Fails unless the screen's top tenth, which is the ground under the status bar on every root and step, is
    /// `appearance`'s ground: a launch that did not take its appearance fails as that, not as what it measured.
    /// The level measured is kept with the result, as an activity named with it.
    ///
    /// Valid only on a screen whose top stands on the paper ground in light (the tab roots, onboarding). A screen
    /// that is dark by design, such as the workout cover, passes as "dark" in either appearance: its caller must
    /// sample a region that is paper in light, or prove the appearance another way.
    @MainActor
    func assertDrawn(
        in appearance: LaunchAppearance,
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let level = try app.screenshot().topTenthLevel()
        XCTContext.runActivity(named: "\(appearance): the ground's level is \(level)") { _ in }
        XCTAssertTrue(
            appearance.isGround(level),
            "\(appearance): the ground's level is \(level)",
            file: file,
            line: line
        )
    }
}

extension XCUIScreenshot {
    /// The picture's pixels as sRGB red, green, blue and alpha, row by row from the top.
    func rgbaPixels() throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context != nil
        }
        XCTAssertTrue(drawn, "the picture was not read")
        return bytes
    }

    /// The mean of red, green and blue over the picture's top tenth.
    func topTenthLevel() throws -> Int {
        let bytes = try rgbaPixels()
        let pixels = bytes.count / 4 / 10
        var sum = 0
        for pixel in 0 ..< pixels {
            sum += Int(bytes[pixel * 4]) + Int(bytes[pixel * 4 + 1]) + Int(bytes[pixel * 4 + 2])
        }
        return sum / max(pixels * 3, 1)
    }
}
