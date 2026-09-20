# Management removal failure and retry fixture

## Current integration contract

This diagnostic fixture demonstrates a partial feature-removal failure. The first removal attempt must remain visibly failed with its original stage and error, keep enough state for retry, and avoid reporting the feature as fully removed. A later retry resumes the removal contract idempotently and leaves unrelated features intact.

The fixture is test support, not a production error simulator or evidence that every external revocation path has been exercised.

`P0BManagementFailureProbe` is copied only into a signed diagnostic host. It registers ordinary lifetime, removal, and `onUnregister` hooks and has no bypass deletion button. Its private `CounterStore` fails the first process-local deregistration attempt before removal runs, preserves the saved value and incomplete management state, and succeeds on the management screen's second retry. The retry deletes only the diagnostic owner and re-registers at zero while the normal Counter remains unchanged.

The UI test saves a comparison Counter value, edits the diagnostic feature, confirms its name and data description, observes the first-stage error and retained value, retries removal, and verifies owner isolation. It uses bounded scrolling to materialize rows in a lazy list. Failure injection stays inside the fixture and must not add branches to production deregistration or storage.

## Japanese source notes and historical evidence

`P0BManagementFailureProbe`は、通常IPAには含めず、署名済み診断hostへだけコピーする管理画面fixtureである。通常の`MiniAppDefinition`にlifetime、removal、onUnregisterを登録し、管理共通層を迂回する専用削除ボタンは持たない。

fixtureの保存層は独自ownerとUserDefaults suiteを渡した`CounterStore`である。`onUnregister`はprocess内の初回だけ意図的に失敗し、その時点の保存値を診断メッセージへ含める。登録解除が失敗するためremoval callbackはまだ呼ばれず、管理状態は「削除が未完了」のままになる。二回目は登録解除が成功し、同じ管理画面の「削除を再試行」から所有キーだけを削除する。

UITestは次の操作列を一つの実画面試験で確認する。

1. 通常Counterの値を増やして比較値を保存する。
2. 診断Featureへ登録済みURLで入り、独自ownerの値を増やす。
3. 管理画面で対象名とデータ説明を確認して削除する。
4. 管理画面内で登録解除段階の失敗、未完了状態、エラー内の登録解除時点の保存値を確認する。失敗後の値保持は共通層の結合testでも直接検査する。
5. 削除を再試行して完了させ、初期状態で再登録する。
6. 診断Featureが0へ戻り、通常Counterの値が変わらないことを確認する。

長いlazy listでは、行がまだaccessibility treeに存在しない場合がある。試験は上下へbounded scrollして対象行をmaterializeし、単純な`waitForExistence`だけに依存しない。失敗注入はこのfixture内だけに閉じ、productionの登録解除や保存処理へ分岐を加えない。
