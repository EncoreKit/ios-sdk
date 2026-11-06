// Set only by Encore's demo app (SPI, not part of the integrator API): the SDUI variant the sheet's `/config` fetch
// asks for. Trigger surfaces (`TriggerConfigLoader`) build their own request and don't carry it.
// The server honours it on a test key or for Encore's own demo apps, and ignores it for every other app.

import Foundation

@_spi(EncoreDemo) public enum EncoreDemoVariant {
    private static let stored = Atomic<String?>(nil)

    /// A variant file stem (e.g. `instructionsHUOfferImages`); nil or blank sends nothing. Nothing caches by it, so
    /// identify with a different user id after changing it; the same id issues no new fetch.
    public static var name: String? {
        get { stored.value }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            stored.value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
    }
}
