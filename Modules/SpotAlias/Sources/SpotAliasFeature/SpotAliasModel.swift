import Foundation

public struct AppAliasItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    public var id: UUID
    public var title: String
    public var aliases: [String]
    public var urlScheme: String
    public var symbolName: String
    public var note: String
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        aliases: [String] = [],
        urlScheme: String,
        symbolName: String = "app.fill",
        note: String = "",
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.urlScheme = urlScheme
        self.symbolName = symbolName
        self.note = note
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// All searchable terms including title, aliases, and JibunKit context
    public var allKeywords: [String] {
        var terms: Set<String> = [
            "JibunKit",
            "jibunkit",
            "ジブンキット",
            "SpotAlias",
            "ショートカット"
        ]
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            terms.insert(cleanTitle)
            terms.insert(cleanTitle.lowercased())
        }
        for alias in aliases {
            let clean = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                terms.insert(clean)
                terms.insert(clean.lowercased())
            }
        }
        return Array(terms)
    }

    /// Diagnostic item for verifying Spotlight connectivity
    public static func makeDiagnosticTestItem() -> AppAliasItem {
        AppAliasItem(
            id: UUID(),
            title: "JibunKit 疎通テスト",
            aliases: ["jibunkit", "ジブンキット", "テスト", "test", "spotlight"],
            urlScheme: "jibunkit://",
            symbolName: "checkmark.shield.fill",
            note: "Spotlight インデックス疎通確認用のテストアイテムです",
            isEnabled: true
        )
    }

    /// Checks if this item matches a search query
    public func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        if title.lowercased().contains(trimmed) { return true }
        for alias in aliases {
            if alias.lowercased().contains(trimmed) { return true }
        }
        return false
    }
}
