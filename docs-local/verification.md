# 派生hostの検証記録

Zaiko（在庫管理）を派生hostへ追加したときの検証と結果。個人データ（在庫の中身）は本文に書かない。

## ローカルで確認できる範囲（`docs-local/local-checks.sh`）

CIを回す前に、ここで落とせるものは落とす。実測結果は次のとおり。

| ゲート | コマンド | 結果 |
| --- | --- | --- |
| Feature の Linux テスト | `swift test --package-path Modules/Zaiko` | 26 tests / 0 failures（うち実データ検証4本は `ZAIKO_REAL_BACKUP` 未設定時はスキップ） |
| Feature の iOS ビルド | `swift build --package-path Modules/Zaiko --swift-sdk arm64-apple-ios` | complete（`#if os(iOS)` の store / RootView を含む） |
| ホスト接続の iOS ビルド | `swift build --target ZaikoIntegration --swift-sdk arm64-apple-ios` | complete |
| アプリ本体ソースの iOS 型検査 | `swiftc -typecheck … Sources/JibunKit/*.swift`（11ファイル） | エラーなし（Tuist生成物は含まない） |

## 実データでの移行確認

- 入力: 現行Zaikoのエクスポート（JSONは `docs-local/fixtures/` に置き、`.gitignore` 済み。リポジトリには入れない）
- 方法: `ZAIKO_REAL_BACKUP=<path> swift test --package-path Modules/Zaiko`
- 結果:
  - 形式（version 3）として受理され、9品目すべてを読み込めた
  - 残量・残日数を、独立に計算した値（`docs-local/calc_expected.py`）と 0.001 以内で一致
  - アラート判定は1件（在庫がマイナスになっている品目）のみで、ソート順の先頭に来る
  - エクスポート側の単位表示設定が組み込み既定より優先される
- 未確認（iOS側）: 取り込み時にホストが通知予約記録をクリアする挙動、通知の実配信、実機での表示

## 未検証（CI／実機の担当）

- Tuist生成とアプリtargetの組み立て（`Project.swift` に追加した `packages` / `dependencies` の解決）
- IPA生成とZIP検査
- SimulatorでのUI回帰
- 実機での SideStore 上書き、JSON移行、通知タップ

## 摩擦として記録したもの

`docs-local/friction-log.md`（F-001〜F-008）を参照。
