// Resolves a sheet text's role marker (`encore:heading`, `encore:body`) to the app's family when the skinned
// sheet decodes, so each layout carries the fonts it opened with. A role with no app family draws the system font.

import Foundation

extension CodingUserInfoKey {
    /// The app's font family per role for one skinned sheet's decode, set by `SheetSkinPresentation`.
    static let sheetFontRoles = CodingUserInfoKey(rawValue: "encore.sheetFontRoles")!
}

extension Decoder {
    var sheetFontRoles: [SheetComponentStyle.FontRole: String] {
        userInfo[.sheetFontRoles] as? [SheetComponentStyle.FontRole: String] ?? [:]
    }
}

enum SheetFontRoles {
    static func isMarker(_ family: String) -> Bool { family.hasPrefix("encore:") }

    /// The app family in `fonts` for a marker's role, else nil (the system font).
    static func family(for marker: String, in fonts: [SheetComponentStyle.FontRole: String]) -> String? {
        guard let role = SheetComponentStyle.FontRole(rawValue: String(marker.dropFirst("encore:".count))) else { return nil }
        return fonts[role]
    }
}
