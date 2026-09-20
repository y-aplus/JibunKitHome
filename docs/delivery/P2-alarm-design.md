# P2-L AlarmKit 設計提出

> 履歴注記: 本文は実装前の設計提出であり、現在状態や未達一覧ではない。採用範囲の状態は[plan.json](plan.json)と[status](../status.md)、現行接続は[AlarmKitガイド](../guides/alarms.md)を優先する。

基準は `bcfde0d88c19a143620b16e71230e4fb404ae7f1`。これは実装前の契約案であり、Windows では Swift/Xcode/AlarmKit を実行していない。以下の Swift 宣言は Apple の現行公開 documentation と WWDC25 sample で照合したが、actor annotation と最終 SDK interface は Xcode 26 CI で再確認する。

## 結論と責任境界

AlarmKit を汎用通知・タイマーへ抽象化しない。Feature は「なぜ、いつ鳴らすか」、表示、`AlarmMetadata`、ボタンの意味、再登録可否を所有する。共通基盤は owner、Feature local ID、世代、OS の `Alarm.ID` (`UUID`) の対応、操作の受付、照合 journal、管理/復元の排他だけを提供する。OS は許可、実際の発火・状態遷移、daemon 内の登録、system presentation を所有する。

推奨する最小境界（名称は提案、未実装）は次である。

```swift
@available(iOS 26.0, *)
public protocol MiniAppAlarmAdapter: Sendable {
    associatedtype Metadata: AlarmMetadata // Feature 所有。Core は中身を解釈しない
    var owner: MiniAppID { get }
    func configuration(alarmID: UUID, generation: UUID) throws
        -> AlarmManager.AlarmConfiguration<Metadata>
}

public struct MiniAppAlarmKey: Hashable, Codable, Sendable {
    public let owner: MiniAppID
    public let localID: String
}

public struct MiniAppAlarmRegistration: Codable, Sendable {
    public let key: MiniAppAlarmKey
    public let generation: UUID
    public let alarmID: UUID
    public var desired: DesiredState       // scheduled / absent
    public var operation: Operation?       // scheduling/replacing/cancelling retry journal
}

@available(iOS 26.0, *)
public protocol MiniAppAlarmService: Sendable {
    func schedule<A: MiniAppAlarmAdapter>(_ adapter: A, key: MiniAppAlarmKey,
        expectedGeneration: UUID?) async throws -> MiniAppAlarmRegistration
    func replace<A: MiniAppAlarmAdapter>(_ adapter: A, key: MiniAppAlarmKey,
        expectedGeneration: UUID) async throws -> MiniAppAlarmRegistration
    func stop(_ key: MiniAppAlarmKey, generation: UUID) async throws
    func cancel(_ key: MiniAppAlarmKey, generation: UUID) async throws
    func reconcile(owner: MiniAppID) async throws -> AlarmReconciliation
}
```

この generic adapter 形なら `AlarmManager.AlarmConfiguration<Metadata>` の `Metadata: AlarmMetadata` を失わず、Core の type erasure も不要である。Core に Feature metadata の enum/switch、任意 payload、独自 timer engine を入れない。`stop` と `cancel` は同義化しない。Apple は両方を別 API として公開するため、OS 上の意味を native probe で記録してから product UI の語彙へ割り当てる。

## 確認できた native API

AlarmKit は iOS/iPadOS 26 の framework。Apple 公開宣言で `AlarmManager` は `class`、`AlarmMetadata` は `Codable & Hashable & Sendable`、`Alarm` とその `State` は値型/Sendable である。公開ページに `@MainActor` は表示されていないため「非 MainActor」と断定せず、Xcode 26 の generated interface と strict-concurrency build を合格条件にする。

```swift
import AlarmKit
import AppIntents
import SwiftUI

@available(iOS 26.0, *)
struct FeatureAlarmMetadata: AlarmMetadata {
    let owner: String
    let localID: String
    let generation: UUID
}

@available(iOS 26.0, *)
func scheduleExample(at date: Date, id: UUID) async throws -> Alarm {
    let stop = AlarmButton(text: "停止", textColor: .white,
                           systemImageName: "stop.circle")
    let alert = AlarmPresentation.Alert(title: "予定の時刻です", stopButton: stop)
    let attributes = AlarmAttributes(
        presentation: AlarmPresentation(alert: alert),
        metadata: FeatureAlarmMetadata(owner: "feature.a", localID: "wake", generation: UUID()),
        tintColor: .blue)
    let configuration = AlarmManager.AlarmConfiguration(
        schedule: .fixed(date), attributes: attributes,
        stopIntent: StopFeatureAlarmIntent(alarmID: id.uuidString))
    return try await AlarmManager.shared.schedule(id: id, configuration: configuration)
}

@available(iOS 26.0, *)
struct StopFeatureAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "アラームを停止"
    @Parameter(title: "Alarm ID") var alarmID: String
    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }
    func perform() async throws -> some IntentResult { .result() }
}
```

この形は Apple sample の `schedule(id:configuration:) async throws -> Alarm`、`AlarmConfiguration`、`LiveActivityIntent` に沿う最小例であり、この repository では未コンパイル。実装では Intent に `owner/localID/generation/alarmID` を全て固定し、文字列を UUID として検証し、SharedState の現世代と登録表が一致した場合だけ Feature callback を配送する。

確認済みの manager surface は次の通り。

- `AlarmManager.shared`
- `authorizationState`、`authorizationUpdates` (`AsyncSequence<AuthorizationState, Never>`)、`requestAuthorization() async throws -> AuthorizationState`
- `alarms: [Alarm] { get throws }`、`alarmUpdates` (`AsyncSequence<[Alarm], Never>`)
- `schedule<Metadata>(id: Alarm.ID, configuration: AlarmConfiguration<Metadata>) async throws -> Alarm where Metadata: AlarmMetadata`
- `cancel(id:) throws`、`stop(id:) throws`、`countdown(id:) throws`、`pause(id:) throws`、`resume(id:) throws`

公開 manager に configuration の `update` はない。「更新」は既存 ID への再 `schedule` が置換になると推測せず、基盤 API では `replace` と呼ぶ。まず新 UUID を `scheduling` journal に保存し、新登録成功後に desired registration を原子的に切替え、旧 ID を cancel する。旧 cancel 失敗は新旧両 ID を journal に残して再照合する。新 schedule 失敗時は旧登録/Bを保持する。即時 countdown の置換は二重発火または空白を原子的に避けられないため初版で拒否してよい。native probe で同一 ID 再 schedule の公式未記載挙動が確定しても、それを API 契約に採用するまでは実行済み更新と呼ばない。

## owner、世代、再起動照合

保存は owner 別で、最低限 `(owner, localID, generation, alarmID, desired, operation, lastObservedState)` を持つ。AlarmKit の `alarms` は「現在の client に属する daemon 登録」を返し、取得した `Alarm.state` は snapshot で自動更新されない。cold launch と `alarmUpdates` の各 emission で全体集合を照合する。

1. 管理状態が enabled の owner だけ新規操作を受ける。local ID の長さ/文字集合は Feature 契約で検証する。
2. 保存と OS の双方に同じ `alarmID` があれば state を更新する。OS 側 metadata を owner lookup の正本にはしない。
3. 保存にあり OS にないものは「発火後停止」「利用者/OSによる取消」「登録途中失敗」のいずれもあり得る。Apple は one-shot が fire-and-stop すると daemon store から削除されると明記するため、無条件再登録しない。`desired == scheduled` でも Feature policy と時刻を確認し、期限切れを大量再発火しない。
4. OS にあり保存にないものは orphan として UUID を保持・報告する。owner を推測して A/B へ配送しない。今回の app client 全体に属するため、既知の pending journal でのみ採用し、それ以外は統合担当が定める app-level quarantine/cleanup 対象とする。
5. 同じ `(owner, localID)` の古い世代は操作対象にせず、cleanup の `alarmID` としてだけ保持する。削除/復元後の Intent は `staleGeneration` で業務状態を変えない。

OS ID は app client scope で UUID を毎回生成し、Feature local ID から決定的生成しない。これで削除→再登録が同じ ID を再利用せず、古いボタンを現世代へ誤配送しない。A の失敗、許可拒否、購読 Task の取消、破損 entry は B の registration/SharedState を変更しない。

## 操作別の失敗保証

| 操作 | 成功確定点 | 拒否・中断・失敗時 |
|---|---|---|
| 許可 | `requestAuthorization()` が `.authorized` | `.denied` は未登録として明示。throw/Task cancel を許可済み扱いしない。設定変更は `authorizationUpdates` で反映 |
| 開始 | `schedule` が `Alarm` を返し、登録表 commit 後に結果を返す | schedule throw は desired を成功にしない。OS成功後の保存失敗は pending UUID を残せる先行 journal と `alarms` 照合で回収 |
| 更新 | 新 ID の schedule、保存切替、旧 ID cancel の順 | 新規失敗は旧を保持。旧取消失敗は partial failure として両 ID を保持し再試行。B保持 |
| stop | `AlarmManager.stop(id:)` が return し、再読出しで期待集合を照合 | throw/cancel は registration を消さない。one-shot 消失との意味を device probe で確認 |
| cancel | `cancel(id:)` が return し、`alarms`/updates から消失を照合 | throw 時は desired `.absent` と UUID を残す。UI に解除完了を出さない |
| pause/resume/countdown | 同期 throws API の return 後、updates/state で照合 | state 不適合 throw を握り潰さず Feature へ typed failure。別 alarm にフォールバックしない |

`alarmUpdates`/`authorizationUpdates` を読む Task の cancel は購読終了であって OS alarm の cancel ではない。Runtime 画面 Task にぶら下げず、app-level service の寿命で再購読する。購読切断中も次回 `alarms` 全量照合で回復する。

## 通常管理、復元、App Intent

P2-W から再利用できるもの:

- `MiniAppID` と owner 別 `MiniAppSharedState` の generation/tombstone。Intent が読んだ世代を update 時に要求する。
- `MiniAppExternalAccess` による extension/Intent 受付 close/open、`MiniAppManagement` の `enabled → disabling/removing → disabled/removed`、owner 単位の `MiniAppRestoreCoordinator` 排他。
- `MiniAppDefinition.effectiveRestoreLifecycle` と `MiniAppRemovalProvider`、既存の namespaced AppIntent package/metadata 比較 fixture。

そのまま再利用できないもの:

- SharedState の generation は daemon の `Alarm.ID`、Alarm state、pending OS operation の保存ではない。専用 registration journal が要る。
- P2-W の同期 file update は OS schedule/cancel の async/sync throws と原子的 transaction を作れない。OS 成功と保存成功の間を journal + reconcile で閉じる。
- Widget/Control の `AppIntent` をそのまま alarm button にしない。AlarmKit configuration が受けるのは `LiveActivityIntent` であり、stop/secondary action ごとに owner/世代/ID を埋めた thin Intent が必要。
- 復元した Codable 値から alarm を自動発火/再登録しない。restore は受付停止→購読停止→registration snapshot/Feature data 適用→OS集合照合→明示 policy で再登録→受付再開、と分ける。

通常接続では Alarm adapter の external access を既存 SharedState adapter の内側に合成し、`close` が新規 Intent/開始を止め、進行中 operation を drain する。`unregister` は当該 owner の全 UUID を cancel して `alarms` からの消失を照合する冪等処理にする。失敗すれば既存 `MiniAppManagement.Stage.unregistering` に残り、disabled/removed 完了へ進まない。enable は保存値を戻すだけで alarm を暗黙開始せず、Feature の通常 UI から明示 schedule する。削除は OS unregister 成功後に owner registration/Feature data/consent を削除する。A cleanup 中も B は予約しない。

stop Intent は OS の標準 stop を妨げない thin callback とする。Apple sample は system が button type に応じ stop/countdown を処理すると説明しているため、Intent 内で同じ `stop(id:)` を重複実行する設計にはしない。業務側 callback が必要なら SharedState の世代確認後に「停止を観測した」event を冪等記録する。custom secondary Intent は `openAppWhenRun = true` なら routing ID を main scene の単一入口へ渡し、background 完結なら `false` のまま短い owner-scoped operation に限定する。

## plist、target、SDK、署名

- app target に空でない localized `NSAlarmKitUsageDescription` が必須。欠落/空文字では schedule 不可。
- countdown を使う Feature は widget extension に `ActivityConfiguration(for: AlarmAttributes<FeatureMetadata>.self)` を追加し、app target の `NSSupportsLiveActivities = YES` を有効にする。Apple sample は countdown 対応なのに extension がない場合、alarm が予期せず dismiss され alert しない可能性を明記する。alert-only 初期 fixture は countdown を使わず条件を分離できる。
- deployment target は iOS 26 以上の native fixture。製品がより低い deployment target を保つ場合は `canImport(AlarmKit)` と `@available(iOS 26.0, *)` の optional adapter にし、Registry/Core 自体を iOS 26 専用にしない。Xcode 26/iOS 26 SDK で app、Intent metadata、必要なら widget extension を build する。
- Apple の AlarmKit documentation は専用 entitlement を要求しておらず、公式 iOS capability 一覧にも AlarmKit 項目はない。従って `com.apple.developer.alarmkit` を推測で entitlements に追加しない。Alarm permission は runtime authorization と usage description で扱う。
- App Group は JibunKit の SharedState/Intent 連携に必要な既存要件であり AlarmKit 自体の要件とは書かない。custom sound は main bundle または app container の `Library/Sounds`。push update を採らない初版では APNs entitlement も要求しない。
- ad-hoc/SideStore/無料署名/有料 program の可否は未確定。Apple の capability 表だけから「有料アカウント必須」または「不要」と断定しない。署名 byte に未知 entitlement を足す実験もしない。

## 最小 native 比較と証拠

同じ source、同じ iOS 26 device、同じ署名方式・team/profile で、独立 app と通常 JibunKit host を比較する。最初は alert-only、同じ `NSAlarmKitUsageDescription`、同じ AlarmKit 呼出し、異なる bundle ID のみ。続いて host A/B、最後に countdown + widget extension と段階化する。

1. build 証拠: Xcode/SDK/Swift version、generated interface から availability/throw/async/actor、build log、built app/extension Info.plist、`codesign -d --entitlements :-`、embedded provisioning profile、bundle/extension IDs、AppIntent metadata。
2. native 証拠: `authorizationState` before/after、prompt の実画面 capture、request/schedule の returned state/error domain+code、`alarms` の UUID/state、`alarmUpdates` と authorization updates の時刻付き log。
3. UI/device 証拠: silent/Focus 下の実発火、Lock Screen/StandBy/対応機の Dynamic Island、stop/custom button、app closed/cold launch、端末再起動前後（初回 unlock 前後を区別）、Settings で拒否/再許可、通常版へ戻した後の既存データ保持。
4. 共存証拠: A/B 同時登録、A stop/cancel/拒否/無効化/削除/復元失敗時の B UUID/state/bytes 不変、古い世代 Intent 拒否、orphan/部分保存からの再起動照合。

独立 app も失敗なら OS/署名/端末条件、独立のみ成功なら host plist/target/metadata/署名合成、双方成功で A/B のみ失敗なら基盤契約、と切り分ける。Simulator 成功は署名・実 alert の証拠にしない。3失敗までに error/log/profile/codesign の差へ分解する。

## CI案と未確定

親の統合後に一括実行する。ローカル文書検査以外はこの提出では走らせない。

- source compile job: standalone A、standalone B、combined、通常 host を Xcode 26/iOS 26 SDK で Release build。strict concurrency、iOS 25 availability fallback、AppIntent metadata identity、Info.plist/署名差分を検査。
- hosted XCTest: fake/journal 層で A/B schedule failure、保存失敗、Task cancellation、stale generation、partial replace、unregister retry、restore が期限切れを再登録しないことを deterministic に検査。native manager は protocol seam の外側に限定する。
- Simulator smoke は authorization/schedule API の存在と cold reconcile まで。実 alert、Focus bypass、再起動、署名可否、watch/StandBy は device gate。
- 実機は上記「最小 native 比較」を一回の操作列にまとめ、CI 成功と別記録にする。

未確定は、最終 SDK の global actor annotation、同一 ID 再 schedule の挙動、`stop` と `cancel` の recurring/alerting 各状態での差、OS が許容する alarm 数と error taxonomy、daemon orphan の安全な app-level cleanup 方針、ad-hoc/SideStore/各 account/profile での実利用、端末再起動・初回 unlock 前の presentation である。いずれも API の存在や文書化済み behavior と混ぜず native/device probe で閉じる。

## Apple 一次資料

- [AlarmKit framework](https://developer.apple.com/documentation/alarmkit)
- [AlarmManager](https://developer.apple.com/documentation/alarmkit/alarmmanager)
- [Scheduling an alarm with AlarmKit (Apple sample)](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [WWDC25: Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)
- [`schedule(id:configuration:)`](https://developer.apple.com/documentation/alarmkit/alarmmanager/schedule%28id%3Aconfiguration%3A%29)
- [`alarms`](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms)
- [`Alarm.State`](https://developer.apple.com/documentation/alarmkit/alarm/state-swift.enum)
- [`NSAlarmKitUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription)
- [`LiveActivityIntent`](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
