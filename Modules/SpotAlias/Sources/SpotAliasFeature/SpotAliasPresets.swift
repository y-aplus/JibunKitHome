import Foundation

public struct AppAliasPreset: Identifiable, Sendable, Equatable {
    public var id: String { title }
    public let title: String
    public let aliases: [String]
    public let urlScheme: String
    public let symbolName: String
    public let note: String

    public init(
        title: String,
        aliases: [String],
        urlScheme: String,
        symbolName: String,
        note: String
    ) {
        self.title = title
        self.aliases = aliases
        self.urlScheme = urlScheme
        self.symbolName = symbolName
        self.note = note
    }

    public func toItem() -> AppAliasItem {
        AppAliasItem(
            title: title,
            aliases: aliases,
            urlScheme: urlScheme,
            symbolName: symbolName,
            note: note,
            isEnabled: true
        )
    }
}

public enum SpotAliasPresets {
    public static let builtin: [AppAliasPreset] = [
        AppAliasPreset(
            title: "マクドナルド",
            aliases: ["マック", "mac", "マクド", "mcdonalds", "mcd", "まくどなるど", "ハンバーガー"],
            urlScheme: "mcdonaldsjp://",
            symbolName: "takeoutbag.and.cup.and.straw.fill",
            note: "マクドナルド公式モバイルオーダー"
        ),
        AppAliasPreset(
            title: "スターバックス",
            aliases: ["スタバ", "sbux", "starbucks", "すたば", "すたーばっくす", "コーヒー"],
            urlScheme: "starbucks://",
            symbolName: "cup.and.saucer.fill",
            note: "スターバックス公式アプリ"
        ),
        AppAliasPreset(
            title: "PayPay",
            aliases: ["ペイペイ", "paypay", "ぺいぺい", "QR決済", "コード決済"],
            urlScheme: "paypay://",
            symbolName: "qrcode.viewfinder",
            note: "PayPay決済"
        ),
        AppAliasPreset(
            title: "LINE",
            aliases: ["ライン", "line", "らいん", "トーク", "メッセージ"],
            urlScheme: "line://",
            symbolName: "bubble.left.and.bubble.right.fill",
            note: "LINEコミュニケーション"
        ),
        AppAliasPreset(
            title: "Amazon",
            aliases: ["amazon", "アマゾン", "あまぞん", "通販", "EC"],
            urlScheme: "amazon://",
            symbolName: "shippingbox.fill",
            note: "Amazon ショッピング"
        ),
        AppAliasPreset(
            title: "メルカリ",
            aliases: ["mercari", "フリマ", "めるかり", "メルペイ"],
            urlScheme: "mercari://",
            symbolName: "tag.fill",
            note: "フリマアプリ メルカリ"
        ),
        AppAliasPreset(
            title: "YouTube",
            aliases: ["youtube", "yt", "ユーチューブ", "ゆーちゅーぶ", "動画"],
            urlScheme: "youtube://",
            symbolName: "play.rectangle.fill",
            note: "YouTube動画視聴"
        ),
        AppAliasPreset(
            title: "X (Twitter)",
            aliases: ["twitter", "x", "ツイッター", "ついったー", "ポスト", "SNS"],
            urlScheme: "twitter://",
            symbolName: "message.fill",
            note: "X (旧Twitter)"
        ),
        AppAliasPreset(
            title: "Google マップ",
            aliases: ["googlemaps", "gmap", "グーグルマップ", "ぐーぐるまっぷ", "地図", "ナビ"],
            urlScheme: "comgooglemaps://",
            symbolName: "map.fill",
            note: "Google Maps"
        ),
        AppAliasPreset(
            title: "乗換案内",
            aliases: ["transit", "jorudan", "のりかえ", "ジョルダン", "電車", "路線"],
            urlScheme: "norikae://",
            symbolName: "tram.fill",
            note: "乗換案内・経路探索"
        ),
        AppAliasPreset(
            title: "Spotify",
            aliases: ["spotify", "スポティファイ", "すぽてぃふぁい", "音楽", "ポッドキャスト"],
            urlScheme: "spotify://",
            symbolName: "music.note",
            note: "Spotify 音楽ストリーミング"
        ),
        AppAliasPreset(
            title: "Discord",
            aliases: ["discord", "ディスコード", "でぃすこーど", "通話", "チャット"],
            urlScheme: "discord://",
            symbolName: "headphones",
            note: "Discord コミュニティ"
        ),
    ]
}
