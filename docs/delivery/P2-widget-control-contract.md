# P2-7 操作Widget／Controlの実装境界

> 履歴注記: 本文は未実装時に固定した開始契約である。操作Widget/Controlの採用範囲は後段で実装・検証され0.8.1で公開済み。現在状態は[plan.json](plan.json)と[status](../status.md)、現行接続は[ガイド](../guides/interactive-widgets.md)を優先する。

2026-09-15開始。共通製品baselineは0.8.0のsource71ef1ff、統合開始点はmain25ded31。Issue #6の正式採用に従い、設定・操作・別process保存・管理・通常接続・OS試験・ガイドを一つの境界として扱う。

## 補う差分と契約

独立アプリでは各app/extensionの組が別の保存先と管理主体を持つ。統合後は同じApp Groupと管理画面を共有する。既存のMiniAppStorageのNSLockとMiniAppRestoreCoordinatorはprocess内のみで、WidgetのsavedStatusは時点読込みである。これらを別processのread-modify-writeや削除中の予約へ拡大解釈しない。

標準のAppIntentConfiguration/AppIntentTimelineProvider、Button(intent:)/Toggle(intent:)、AppIntentControlConfigurationを使用する。Featureは自身の型・永続識別子・entity/query・保存モデルを所有し、hostは標準WidgetBundleへ登録する。CoreにCounter等の業務モデルやFeature別switchを置かない。

小さな共有値の実装では、owner別の安定したファイル調停先で状態読込み・変更・原子的保存を一つの同期操作にする。管理による受付停止・削除も同じ調停を通す。失敗時は元データを保持し、欠損/破損/無効ownerを初期値で上書きしない。削除後の古い操作が再登録した新しいデータへ適用されない世代識別を持つ。別ownerは別の調停先を使う。任意DB/SDKをこの保存方式へ強制するものではない。

hostの管理・起動時同期・復元/移行には、Feature所有の外部受付フックを明示接続する。停止は新規受付を閉じて進行中の同期書込み終了を待ち、その後に削除する。再有効化と復元後の再開では永続管理状態に従う。エラーは管理UIへ伝え、失敗した解除を成功としない。既存Definition利用者にはoptionalで後方互換を維持する。

## 必須操作列

- 独立A/Bと統合A+Bでnative metadataの型・entity/query・設定/操作の永続識別子を比較する。既存CounterとP1静的WidgetのIDは変更しない。
- A/Bは同じlocal item IDを別ownerで持ち、二つ以上の項目を設定pickerで選べる。選択対象の変更・再起動後の保持、削除された項目の拒否を確認する。
- WidgetボタンとControlの実OS操作で選択対象だけを変更し、本体/extension双方で同じ値を読む。設定/表示の存在だけ、直接performだけでOS合格にしない。
- 二processからの競合更新、片側保存失敗・破損拒否、取消、無効化/削除と遅い操作の競合、再有効化/再登録後の古い世代拒否、Bの継続を検証する。
- 通常Definitionの無効化/再有効化/削除・選択復元と接続する。アプリが前景にいない時の操作を含める。通常Counter/Reminder、静的Widget、既存Shortcuts、共有入力の影響範囲を回帰する。
- ガイドには接続先、app/extension別の実行責任、設定保持、更新要求とOS表示遅延の違い、失敗/管理時の表示を記す。

## 分担・CI・実機

親が製品API/通常host・fixture/CI統合を所有する。計画gateレーンはplan.json、check-delivery.pyとそのtestsだけを所有し、製品/CIに触れない。製品担当を追加する場合はこの共有契約に担当pathを追記してから開始する。担当別のCIは行わない。

2026-09-16、35022622331の修正境界では親が管理UI試験・通常host接続・証拠/CI統合を担当する。CLI nativeレーンはTests/InteractiveWidgetsのStandaloneAWidget.swift、StandaloneBWidget.swift、CombinedWidget.swift、Project.swift.fixture、NativeTests.swiftとTools/verify-interactive-widgets.pyのnative側、および必要なTools/testsのnative検証だけを所有する。共有Core、FeatureA/Bの契約、host側helper、管理UI試験は変更せず、必要な共有修正は提案として一括提出する。共通baselineはこの分担を記録したcommitとし、子はCI/pushを行わない。

初回予算は2run。同じimmutable sourceで、(1)共有/別process試験・通常IPA/回帰、(2)独立/統合Widget/Controlのnative build/metadata/対象OS試験をまとめる。初回投入前に正確なworkflow入力・test filterと再利用sourceを証拠reportへ固定する。各runは通常25分見込み/30分目標、準備とupload込み。native/UIが収まらない場合は同一run内の並列jobを使い、予算増が必要なら根拠を記す。巨大な直列jobや各小修正ごとのCIは行わない。

実機は設定・操作・管理・更新/Refreshをまとめて0.8.x候補で確認し、そのまとまりで版を進める。1.0まで全実機を延期する意味ではない。3失敗までに切り分け、待機はOS監視と一回queue通知とする。

## Appleの参照

- [設定可能Widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)
- [Widgetの操作](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Controlの作成](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)

未実装・未検証の開始契約であり、合格証拠ではない。
