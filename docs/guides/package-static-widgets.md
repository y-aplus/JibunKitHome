# Integrating static widgets owned by a Swift package

## Current integration contract

Define the widget, configuration, timeline provider, resources, and localization in the feature package. The host widget extension imports and composes that product; it should not duplicate feature implementation. Shared data requires an explicitly configured and signed App Group plus a small, versioned snapshot contract.

Verify standalone and integrated builds, extension metadata, resource lookup, and removal of the feature contribution. Simulator or metadata success does not prove gallery discovery, timeline scheduling, App Group signing, or device rendering.

Keep feature ID, widget `kind`, and storage namespace stable after release. `kind` is an extension-unique reverse-DNS string, not the feature ID. Put display name/description in package `Localizable.strings`. The feature exposes the same definition, lifetime, and removal provider used by its main UI. Prefix shared keys with `MiniAppContext.storageKey(_:)`, and configure the identical `JibunKitAppGroup` plus entitlement in app and extension.

App writes go through shared store access. The widget reads `MiniAppManagement.savedStatus` from shared defaults and displays owner data only when enabled. If the App Group cannot be resolved, show unavailable instead of reading `.standard`. This status read is not a cross-process reservation, and write intents must use the normal external-access coordination. A timeline reload is only a scheduling request.

The host creates management registrations from definitions and uses the same App Group for status and values. Initialize an owner value only when both its key and management history are absent and the owner is enabled. Never recreate a value during normal launch, repeated SwiftUI tasks, after removal, or while disabled. Disable retains value; removal deletes only that owner; re-enable restores admission without creating data or starting business work. One owner's rejection must not stop another's initialization.

Acceptance compares independent and combined gallery metadata, timeline reads, localization, A/B isolation, management transitions, upgrade, and device gallery/rendering separately. Removing a widget type from a later binary does not guarantee an already placed widget disappears immediately; stale display is not evidence that its code or store remains active.

## Japanese source notes and historical evidence

このガイドは、通常の`MiniAppDefinition`と共有storeを持つFeatureが、静的Widgetを既存hostへ出荷するための0.8.0のP1接続を示す。2026-09-14時点でCI 34746211458のTimeline4件・独立/統合gallery3件と通常host管理UIが成功した（[source別の証拠](../verification/2026-09-13-p1-a.md)）。4e6a3f4（0.7.1/build9候補）の実機で追加/描画/更新、A管理/B保持、上書き/Refresh保持を確認済み（[実機記録](../verification/2026-09-14-0.8-device-check.md)）。0.8.0で正式公開した。0.7.0の実績へは追加しない。設定可能・操作可能WidgetとControlはP2であり、この手順の対象外とする。

## Feature package

Feature ID、Widget `kind`、保存namespaceは一度公開した後に変更しない。`kind`はFeature IDとは別の、extension内で一意な逆DNS文字列にする。表示名と説明はpackage resourceの`Localizable.strings`から読み、hostの翻訳へ暗黙に依存させない。

FeatureまたはIntegration側は通常画面と同じIDの`MiniAppDefinition`を公開し、同じ`MiniAppFeatureLifetime`と`MiniAppRemovalProvider`を渡す。Widgetが読む値は`MiniAppContext.storageKey(_:)`でowner prefixを付け、appとextensionの両targetに同じ`JibunKitAppGroup`とApp Group entitlementを設定する。hostからの通常の読み書きは共有`MiniAppRestoreCoordinator.withStoreAccess(for:)`を通す。削除callbackは管理層がownerを予約した後に呼ばれるため、所有keyだけを冪等に削除する。

Widget processは`MiniAppManagement.savedStatus(for:defaults:)`で同じ共有defaultsの状態を読み、`.enabled`以外では所有値を表示しない。App Groupを解決できない場合は読取不可を明示し、`.standard`へfallbackして別storeを正常値として表示しない。この読取りは別processの操作予約ではない。書込み入口はhost側の通常管理・保存調停を迂回してはならない。状態変更後の`WidgetCenter.reloadAllTimelines()`は更新要求であり、実際の描画成功や即時更新を保証しない。

## Hostとextension

通常hostは列挙したDefinitionから既存の`MiniAppManagement.Registration`を作る。`lifetime`、`removal`、`onUnregister`をそのまま接続し、管理状態もFeature値も同じApp Group defaultsを使う。初期値はowner keyとそのownerの永続管理状態がどちらも未作成で、ownerが有効な場合だけ保存する。削除後の再登録ではkeyがなくても管理状態の履歴があるため、初期値を勝手に復活させない。通常起動やSwiftUI `.task`再実行で上書きせず、disabled/removed ownerを再作成しない。各ownerを独立に判定し、Aの拒否でBの初期化を止めない。無効化は値を保持し、削除は対象ownerの値だけを消し、再有効化は受付を戻すだけで業務処理や値の作成を自動開始しない。

静的Widgetを通常出荷するには、Widget型をSwift Package製品に含めるだけでは足りない。出荷対象appが埋め込むWidget extensionの`@main WidgetBundle`へ各Widget型を明示的に列挙し、extension targetから各package製品へ依存する。二Featureを一つの標準Widget extensionへ登録でき、FeatureごとのextensionやCore wrapper、生成器は必須ではない。単独A、単独B、統合hostの登録集合を比較し、統合集合が二つの安定kindの和であることを検査する。

## 受入試験

`Tests/PackageWidgets`は同一suiteへA=11/B=22を保存し、次を確認する。

- packageの通常Definition、lifetime、removalが同じowner IDである。
- A更新後もB=22を保持する。
- A無効化中はA値を隠し、通常store書込みを拒否し、Bを保持する。
- A再有効化で削除前のA値を再表示する。
- A削除後もB値を保持し、A再登録後の新しい値がBへ影響しない。
- 初回seed、更新後cold再構築、disabled/removedでのcold再構築、削除直後のA不在、再有効化直後のA空を区別する。
- 英語・日本語resourceと安定kindがpackageに含まれる。
- 単独A/Bと統合hostをWidget galleryで発見し、previewとホーム画面を画像/OCRで実描画確認する。統合hostでは更新・無効化・再有効化・削除・再登録の各状態を同じホーム画面上のA/Bで確認する。

timeline取得、extension build、kindのbinary文字列、reload要求の成功だけをOS描画成功として扱わない。

## 0.8.0の端末確認

実行済みのCIは上記sourceの証拠として扱い、端末合格と区別する。実装提出やbuildだけで通常アプリ再起動保持を合格と扱わない。4e6a3f4のiOS 27.0実機では、galleryの二Widget、ホーム描画、本体値との一致、A/B更新、Aの無効化・再有効化・削除・再登録と各段階のB保持を確認した。同IPA上書きとSideStore Refresh後の起動でもA空値/B数値を保持した。単純なアプリ再起動だけを独立にやり直した観測はないため、上書き/Refresh後の起動保持と区別する。reload要求と実表示の時差を一般保証せず、この確認から1.0境界を独自に確定しない。

## Widget型を出荷構成から除いた後

アプリ内の無効化/削除では、収録されたWidget providerがowner管理状態を読んで非表示相当の内容へ更新できる。一方、再ビルドでWidget型をBundleから除去することは、ホームに配置済みのWidgetや以前の表示をその場で消す操作ではない。4e6a3f4の実機では診断版からCounterのみの通常版へ上書き後、診断Widgetの旧表示が残り、タップで本体トップへ移った。通常IPAには診断kind/resourceがないことを検査済み。表示残存をFeatureの稼働・store再読込の証拠とはしない。

不要になった配置は利用者がホームから取り除く。所有データも消す意図なら、該当Featureを収録した版の管理画面で削除を完了してからコードを除く。コードを外すだけでは既存の所有データを消去した保証にならない。管理削除後でもOSの旧表示が即時に消えるとは約束しない。
