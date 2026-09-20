import Testing
import Foundation
@testable import SpotAliasFeature

@Suite("SpotAlias Tests")
struct SpotAliasTests {
    @Test("AppAliasItem encodes and decodes losslessly")
    func itemEncoding() throws {
        let item = AppAliasItem(
            title: "ロピア",
            aliases: ["lopia", "ropia", "ろぴあ"],
            urlScheme: "lopia://",
            symbolName: "cart.fill",
            note: "スーパー"
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(AppAliasItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.title == item.title)
        #expect(decoded.aliases == item.aliases)
        #expect(decoded.urlScheme == item.urlScheme)
        #expect(decoded.symbolName == item.symbolName)
        #expect(decoded.note == item.note)
        #expect(decoded.isEnabled == item.isEnabled)
    }

    @Test("allKeywords includes title and aliases normalized")
    func keywordsNormalization() {
        let item = AppAliasItem(
            title: "マクドナルド",
            aliases: ["mcdonalds", "Mac", "マック "],
            urlScheme: "mcdonalds://"
        )
        let keywords = item.allKeywords
        #expect(keywords.contains("マクドナルド"))
        #expect(keywords.contains("mcdonalds"))
        #expect(keywords.contains("mac"))
        #expect(keywords.contains("マック"))
    }

    @Test("matches query correctly with case insensitivity")
    func matchingQuery() {
        let item = AppAliasItem(
            title: "スターバックス",
            aliases: ["starbucks", "スタバ", "SBUX"],
            urlScheme: "starbucks://"
        )
        #expect(item.matches(query: "starbucks"))
        #expect(item.matches(query: "STARBUCKS"))
        #expect(item.matches(query: "sbux"))
        #expect(item.matches(query: "スタバ"))
        #expect(item.matches(query: "スター"))
        #expect(!item.matches(query: "タリーズ"))
    }

    @Test("presets have valid titles and URL schemes")
    func presetsValidation() {
        let presets = SpotAliasPresets.builtin
        #expect(!presets.isEmpty)

        for preset in presets {
            #expect(!preset.title.isEmpty)
            #expect(!preset.aliases.isEmpty)
            #expect(preset.urlScheme.contains("://"))
            #expect(!preset.symbolName.isEmpty)
        }
    }

    @Test("Backup JSON roundtrip preserves items")
    func backupRoundtrip() throws {
        let items = [
            AppAliasItem(title: "ロピア", aliases: ["lopia"], urlScheme: "lopia://"),
            AppAliasItem(title: "LINE", aliases: ["ライン"], urlScheme: "line://"),
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)

        let decoded = try JSONDecoder().decode([AppAliasItem].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].title == "ロピア")
        #expect(decoded[1].title == "LINE")
    }
}
