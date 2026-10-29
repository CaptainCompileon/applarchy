import Foundation

/// Logos to share, as a small JSON file: {"applarchyLogos": 1, "logos": [{"art": "…"}]}.
/// Reading also takes a plain text file of text art (one logo). What's read is checked:
/// only text, of a size a screen can show, and not too many logos at once.
enum LogoFile {
    static let version = 1
    static let maxLogos = 500
    static let maxLines = 120
    static let maxColumns = 200

    struct ReadError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private struct Contents: Codable {
        var applarchyLogos: Int
        var logos: [Entry]
        struct Entry: Codable { var art: String }
    }

    static func data(_ arts: [String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(Contents(applarchyLogos: version, logos: arts.map { .init(art: $0) }))
    }

    /// The logos in a file's contents, in order.
    static func logos(in data: Data) throws -> [String] {
        let arts: [String]
        if let contents = try? JSONDecoder().decode(Contents.self, from: data) {
            guard contents.applarchyLogos <= version else {
                throw ReadError("These logos are from a newer Applarchy. Update to import them.")
            }
            arts = contents.logos.map(\.art)
        } else if data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "[") {
            throw ReadError("This isn't an Applarchy logo file.")
        } else if let text = String(data: data, encoding: .utf8) {
            arts = [text]                                   // plain text art
        } else {
            throw ReadError("This file isn't text or an Applarchy logo file.")
        }
        let valid = arts.compactMap(clean)
        guard !valid.isEmpty else { throw ReadError("There are no logos in this file.") }
        guard valid.count <= maxLogos else { throw ReadError("That's more than \(maxLogos) logos in one file.") }
        return valid
    }

    /// Trailing spaces and blank lines above and below go (as the editor saves a logo);
    /// nil for nothing at all, or art too big for a screen.
    static func clean(_ art: String) -> String? {
        var rows = art.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while rows.first?.isEmpty == true { rows.removeFirst() }
        while rows.last?.isEmpty == true { rows.removeLast() }
        guard !rows.isEmpty, rows.count <= maxLines, rows.allSatisfy({ $0.count <= maxColumns }),
              !rows.joined().unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0 != "\t" })
        else { return nil }
        return rows.joined(separator: "\n") + "\n"
    }
}
