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

- ~~Tuist生成とアプリtargetの組み立て~~ → CIで成功（下記）
- ~~IPA生成とZIP検査~~ → CIで成功（下記）
- SimulatorでのUI回帰（`simulator_tests=true` は今回未指定）
- 実機での SideStore 上書き、JSON移行、通知タップ

## CI（派生側のActions）

- 実行: https://github.com/y-aplus/JibunKitHome/actions/runs/35237198657（workflow_dispatch、main、`9746838`）
- 結果: **success**（jobは `Xcode 26.6 (combined)` のみ。native比較系は既定入力のためskipped）
- 成果物: `JibunKit-ad-hoc`（`JibunKit.ipa`、3,685,328 bytes）
- IPA検査: ZIPのCRCエラーなし、bundle `com.jibunkit.app`、`0.8.3` / build `13`、App Group `group.com.jibunkit.shared`（既存JibunKitの上書き更新になる）
- **Zaikoが製品バイナリに入っていることの確認**: 本体実行ファイル `JibunKit_App`（6,419,040 bytes）に「在庫管理」1件、「補充タイミングです」1件、`ZaikoRootView` 4件を検出。Widget／Share Extension側には含まれない（ZaikoはWidgetを持たないため仕様どおり）
- 配布用: prerelease `zaiko-check-20260918` にこのIPAを添付（SideStoreで導入するため）

## 摩擦として記録したもの

`docs-local/friction-log.md`（F-001〜F-009）を参照。
