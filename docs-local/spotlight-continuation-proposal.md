# Core Spotlight Search Continuation サポート改善提案

## 概要
iOS の Spotlight 検索最下部にある「アプリで検索（Search in App）」をタップした際、OS からアプリへ検索クエリ文字列が引き渡される機能（**Core Spotlight Search Continuation**）を JibunKit 基盤（`JibunKitCore` およびホスト）でサポートするための設計提案です。

---

## 背景と課題
現在、JibunKit は `CSSearchableItemActionType`（Spotlight 上で特定アイテムがタップされたイベント）を以下のように受け取り、`MiniAppSpotlightNamespace` 経由で対象の Feature にルーティングしています：

```swift
// JibunKitApp.swift
.onContinueUserActivity(CSSearchableItemActionType) { userActivity in
    if let route = MiniAppSpotlightRoute.resolve(userActivity, registeredIDs: MiniAppRegistry.registeredIDs) {
        navigation.open(route)
    }
}
```

しかし、ユーザーが Spotlight の最下部にある「JibunKit（または組み込みミニアプリ）で検索」を押した場合は、**`CSQueryContinuationActionType`** という別の Activity Type が渡され、`userActivity.userInfo?[CSSearchQueryString]` に検索キーワードが入ります。

現在の JibunKit には：
1. `Project.swift` の `NSUserActivityTypes` に `CSQueryContinuationActionType` の宣言がない
2. `JibunKitApp.swift` に `.onContinueUserActivity(CSQueryContinuationActionType)` のハンドラがない
3. `MiniAppDefinition` にクエリ検索を受け取る契約（例: `onSearchContinuation: (String) -> Void`）がない

ため、このクエリが無視されてしまいます。

---

## 提案する設計

### 1. `Project.swift`
`appBuild` の `NSUserActivityTypes` に `CSQueryContinuationActionType` を追加：
```swift
"NSUserActivityTypes": [
    .string(CSSearchableItemActionType),
    .string(CSQueryContinuationActionType),
],
```

### 2. `JibunKitCore` への追加
`MiniAppDefinition` に、クエリを受け取れるオプショナルなハンドラを追加：
```swift
public struct MiniAppDefinition {
    // ...
    /// Spotlight の「アプリで検索」から渡された検索文字列を受け取る
    public var onSearchQuery: (@MainActor (String) -> Void)?
}
```

### 3. `JibunKitApp.swift` での配送
```swift
.onContinueUserActivity(CSQueryContinuationActionType) { userActivity in
    guard let query = userActivity.userInfo?[CSSearchQueryString] as? String else { return }
    // 検索機能を提供するミニアプリ（例: SpotAlias や Notes）へ query を通知
    MiniAppRegistry.dispatchSearchContinuation(query: query, navigation: navigation)
}
```

これにより、SpotAlias のような辞書・ランチャー系ミニアプリや、メモ・検索系ミニアプリが、Spotlight で見つからなかった入力文字列をアプリ側で即座に受け取って曖昧検索できるようになります。
