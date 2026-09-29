import CoreText
import Foundation
import OSLog

/// Makes the bundled Archivo variable font available to Core Text in this process.
///
/// The font ships once, in this target's resource bundle. The apps' `UIAppFonts` name that same
/// file (`LedgerKit_LedgerDesign.bundle/Archivo[wdth,wght].ttf`), so the system registers it at
/// launch; previews and package tests have no such key and register it here. Every Archivo font
/// is built through ``ArchivoFont``, which calls ``registerIfNeeded()`` first, so no caller can
/// forget it.
public nonisolated enum FontRegistration {
    /// Registers Archivo once per process and reports whether it is usable. Idempotent and cheap
    /// after the first call; a registration the system already made (the apps) counts as success.
    @discardableResult
    public static func registerIfNeeded() -> Bool {
        isArchivoAvailable
    }

    /// Evaluated once, on first use (a `static let` initializer runs exactly once).
    private static let isArchivoAvailable: Bool = register()

    private static let logger = Logger(subsystem: "com.petearevalo.Ledger", category: "LedgerDesign")

    private static func register() -> Bool {
        guard let url = Bundle.module.url(forResource: "Archivo[wdth,wght]", withExtension: "ttf") else {
            logger.error("Archivo[wdth,wght].ttf is missing from the LedgerDesign resource bundle")
            return false
        }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        let failure = error?.takeRetainedValue()
        if registered || ArchivoFont.isResolvable {
            return true
        }
        logger.error("Archivo could not be registered: \(String(describing: failure), privacy: .public)")
        return false
    }
}
