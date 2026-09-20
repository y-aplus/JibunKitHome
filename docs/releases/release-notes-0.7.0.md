# JibunKit 0.7.0

Issue #5のP0全6単位を完成した版です。1.0は未達で、次はP1/0.8.0を進めます。

## 主な変更

- Featureの開始・終了・再開を、所有するTask・購読・通信・保存資源の寿命へ接続。
- Feature所有のsheet/full-screen/UIKit提示を、切替・取消・外部URL遷移・終了に接続。
- JSON/添付とSQLiteで、通常アクセスと復元・移行・リセットの調停、失敗時保持、他Feature保持を検証。
- アプリ内に利用同意、無効化・再有効化、確認付きの登録/所有データ削除、失敗後の再試行を追加。
- Swift Packageのpath/product/target/host依存診断と、実Registryの登録漏れ検査、互換更新・復旧の手順を整備。
- 終了が進まない所有処理の診断と、局所計算には補完を追加しない判断基準を整備。

## 検証と互換性

製品/IPA source: `baa041f2115d84ddb94ae4d8e6882c7eea29e9b7`。
[CI34705653297](https://github.com/y-aplus/JibunKit/actions/runs/34705653297)で共通244試験（既存skip2）、Records11、Notes単独/生成host、native診断6ケース、同じiOS hostへのAだけのPackage更新・再起動・破損拒否/修復とB/resource保持が成功しました。通常URLとRecords UIも成功。

通常UI13件/Filesの選択JSON復元は`d1adb8e`の[34702137986](https://github.com/y-aplus/JibunKit/actions/runs/34702137986)、P0-A/B生成8件は同sourceの[34700435807](https://github.com/y-aplus/JibunKit/actions/runs/34700435807)を参照。製品差分が任意Validator診断（既定空集合）と版番号だけであることを確認して再利用しました。今回の部分filterを全回帰実行と扱いません。

2026-09-13にユーザーが診断IPAで一括1〜8と提示中外部URL遷移を確認し、同じsourceの通常IPAへ上書き後もCounter/Reminderの変更内容を保持し、他の軽い確認も問題なしと報告しました。Widget更新遅延は観測されず、即時更新を保証する測定ではありません。Records/SQLiteは期待文字列との一致確認です。

本体/Widgetは0.7.0 build8。bundle ID、App Group、Counter/ReminderのID/保存先を維持。既存アプリへSideStoreで上書き更新できます。通常IPAはCounter/Reminderのみで、Recordsは参照ソース、Zaikoや診断Featureを通常IPAへ追加していません。

通常IPA SHA-256: `516bc3e85648ca75f4051de4367f20b98afa3c6b1f69ea1e6be8619adb813489`。
実機確認済みIPAをそのまま配布します。製品source以後の出荷commitは文書/証拠のみで、IPAは再ビルドしていません。

## 残る範囲

P1の通常OS入口の仕上げ、P2の用途拡張、P3の高度な共存は残ります。同一process内の強制隔離、任意DB/SDK/extensionの透過統合は提供しません。任意のFeatureが自動的に管理対象になるわけではなく、所有資源・保存・解除をIntegrationから接続する必要があります。

[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)の需要推定を受領しました。1.0の正式境界はユーザー判断により0.8.0完了時に確定するで、0.7.0公開を1.0完成と扱いません。

[出荷記録](../verification/2026-09-13-0.7-release.md) / [実機結果](../verification/2026-09-13-0.7-device-check.md) / [責任と制約](../compatibility.md)
