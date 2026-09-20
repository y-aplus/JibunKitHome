# Removing feature-owned data

## Current integration contract

The feature declares what it owns and implements idempotent removal. The host orchestrates the removal lifecycle: close new admission, stop and drain runtime work, revoke or cancel external registrations where possible, delete feature storage, and report partial failures without claiming success.

Removal must not touch another owner or silently broaden from one profile/account to all data. Keep enough failure detail for an explicit retry, and distinguish user data removal from merely disabling or hiding a feature.

Declare a `MiniAppRemovalProvider` with the feature ID, a user-facing data description, and an idempotent `removeData` callback. The host owns confirmation, runtime shutdown, notification/search deregistration, the owner reservation, and persistence of management state. It calls the provider only after the runtime is stopped, ordinary store work has drained, and exclusive access is held. The callback must not reacquire the same reservation. Cancellation, timeout, stop failure, or deregistration failure must skip deletion.

Delete only declared keys and directories; never infer storage for a feature without a provider or clear an entire shared UserDefaults suite/container. Re-registration starts from initial feature data and unconfirmed feature consent, but does not revoke or request the application's OS permission. Removing owned data does not remove code or resources from the installed application.

## Japanese source notes and historical evidence

`MiniAppRemovalProvider`は、Featureが所有する保存データと利用者向け説明を宣言する。削除確認、Featureの停止、通知・検索等の登録解除、owner予約、管理設定の永続化はhost管理層の責任であり、providerはデータ削除だけを行う。

```swift
let provider = MiniAppRemovalProvider(
    id: context.id,
    dataDescription: "保存した項目と添付ファイル"
) {
    try await store.removeOwnedData()
}
```

`removeData`を呼ぶ時点では、同じownerのRuntimeが停止し、通常保存操作がなく、hostが排他予約を保持している。callback内から同じownerの予約を再取得しない。停止・登録解除・予約のいずれかに失敗した場合や、利用者が確認を取り消した場合はcallbackを呼ばない。timeoutを成功扱いして削除へ進めない。

削除対象はFeatureが明示したキーやディレクトリだけに限定する。providerがないFeatureの保存先を推測して削除しない。UserDefaults suiteや共有コンテナ全体の消去は、他Featureのデータを巻き込むため禁止する。

Counterは`counter.value`、Reminderは`reminder.message`に相当するcontext由来キーだけを削除する。削除後にstoreを作り直すとそれぞれ`0`と空文字列を返し、既存schema 1バックアップは引き続き復元できる。Reminderの通知request/category削除とCounterのRuntime終了はhost側の所有解除手順で扱う。

削除はコードをIPAから除く操作ではない。再登録時は初期保存状態から始まり、Feature内同意は未確認に戻る。iOSがJibunKitに付与した権限自体はFeature削除で取り消されず、同意と別に扱う。再登録の操作だけでOS権限要求や業務処理を開始しない。
