# JibunKit 0.8.4 — 背景・BLE・window等の接続基盤

公開VERSIONは0.8.4/build14、PREVIOUSは0.8.3/build13。1.0.0の完成判定ではありません。

## この版の変更

- Featureごとの背景処理、位置、BLE、外部データidentity/APNsの接続と所有・終了・復帰の基盤。
- 複数windowの生成・配送・終了連携、単一前景ARの接続、任意採用の保存専用Action extension。
- 通常Widgetのen/ja文言、外観/画面点灯要求の接続例、BLEの接続・復元時通知の取りこぼし対策。

これらはFeature作者向け基盤です。通常IPAはCounter/Reminder、WidgetとShareを含み、診断FeatureやAction extensionは含めません。Actionは構成で明示採用した場合のみ追加します。

## 検証済みの範囲

- c66b624の統合native69件と、ARの実frame/離脱停止/再開/停止、ActionのURL/ファイル/取消/片側無効化、idle点灯維持/通常消灯復帰の実機結果。
- fe1a6e5の実BLE read/write/notify、両Feature同時受信、片側停止後の他方維持、scan停止/切断再接続後受信。
- 7e4c740/CI35325946663でnative73件（失敗/skipなし）と共有BLE/window24件。復元GATT索引、早着通知/旧世代拒否、起動待ちbuffer上限を追加自動検証。14分36秒。
- 41c97f1/CI35298791125の通常共有443件（既存Keychain skip2）・Records11件・選択Counter復元/取消/再起動・Reminder保持は当該sourceの証拠。c0eb6b2/CI35327736417の通常build/IPA/共有試験も成功。今回の通常IPAでCounter/Reminder保持とCounter JSON書き出し・読み込み・復元対象表示を実機確認しました。

- Filesの自動UIはOS FileProviderの参照解決エラーで失敗し、新規Simulator比較も選択操作で中断しました。自動試験の安定化は未解決です。今回実機では読込が成功していますが、実復元の再操作は依頼していません。

## 未確認・制約

- OSによるBLE/background URLSession等のcold起動・復元、通常schedulerの実配送、実移動/境界/iBeacon受信は未確認。単なるホーム復帰やnative fake成功で代用していません。
- iPad実機はsideload環境の準備を見送ったため未確認。実二window検証はiPad Simulatorのみです。
- CloudKit/APNsの実通信は対応署名・サービス条件が必要で未確認。無料署名で全capabilityが利用できるとはしません。
- 継続処理のOS開始はnative直接比較でも受付エラーがあり未確認。以前のLive B単発値差分など、未解明の観測は保持します。
- 同じBLE機器の両owner通信は修正版で成立しましたが、旧不具合の内部原因は併用時ログ不足のため未確定です。

[対象別の実機記録](https://github.com/y-aplus/JibunKit/blob/0878ede3799d732a511b6c507014f030ca50e858/docs/verification/2026-09-18-p2-combined-device.md)と[出荷記録](https://github.com/y-aplus/JibunKit/blob/main/docs/verification/2026-09-18-0.8.4-release.md)を参照。出荷source/runとSHAは以下に示します。旧release/tag/assetは変更しません。


出荷source: `0878ede3799d732a511b6c507014f030ca50e858`。CI35333186866成功（5分30秒）。実機確認したc0eb6b2から製品コード・版の差分なし。Filesの自動試験は再実行せず、上記の実機とsource別証拠を参照しています。

IPA: 4,746,203 bytes。SHA-256: `932463711a70ca97c34c3ed1b8f6213eec4b7853372a7d6c23d02ecf7dd76f54`。
