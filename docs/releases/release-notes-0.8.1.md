# JibunKit 0.8.1

build11。0.8.0に続く、操作Widget/Controlと共有状態の実機確認を終えた中間版です。1.0は未達です。

- Feature所有の設定可能/操作WidgetとControlを標準WidgetKit/App Intentsで接続する例とガイドを追加。
- 小さな共有状態を本体・extensionの複数processから安全に更新するMiniAppSharedStateを追加。owner分離、原子的保存、削除/復元後の古い操作の拒否を扱います。
- 通常管理・バックアップ復元へoptionalのexternalAccessを接続。無効化中の更新を止め、他Featureの状態を保ちます。

診断A/BでOS設定・加算、再起動/上書き/Refresh保持、削除/無効化/選択復元と他owner保持を実機確認しました。通常IPAはCounter/ReminderとShare Extensionの構成で、診断Featureは含みません。

既存bundle ID/App Group・Counter Widget/Shortcutを維持します。共有状態への既存DB移行は必須ではありません。削除/復元後は古いWidget/Controlの項目を選び直してください。OS表示の即時更新は保証しません。

Simulator初回管理でSpotlightサービスの遅延/接続中断を観測しました。今回の実機無効化はほぼ即時でしたが、OS内部の遅延原因は未解明です。Live Activities/AlarmKit、撮影/音声、背景/位置、外部identity等の採用P2範囲は引き続き開発中です。

[検証・source・配布物の記録](../verification/2026-09-16-0.8.1-release.md) ／ [操作Widget/Control接続](../guides/interactive-widgets.md)

IPA source: `88ab7cbe9f41a7eb102fed9444923c8ff8812bfd`。CI35038442208成功。SHA-256: `6498605839402ae79c3dbc41395abd650e60d3b1c2d10a7303f20311ca88b987`。実機確認は版更新前e984d44/通常4eb784dで行い、版だけの差分を照合して再利用しました。
