# 独立Files picker比較（2026-09-18）

Source c3324d7、CI35335082797は比較assertが失敗。ただし両経路ともOS境界の同じ失敗を観測でき、比較実験として切り分け結果を得た。

- 新規iPhone Simulator、JibunKitCore/BackupScreenに依存しないFilePickerComparison app。
- UIKit exportのcallbackを受領。同じ固定JSONをUIKit open(asCopy:false)と、アプリ再起動後のSwiftUI fileImporterでそれぞれ選択。
- 両方でOS DocumentManagerが選択URLをhostへ通知した後、FileProvider bookmark resolutionが -1005、下位resolver -1012。delegateへ空itemsとなり、アプリの読込callback/内容照合には到達しない。
- OSログ時刻: UIKit 10:37:09Z、SwiftUI 10:38:00Z。元hostの35327736417/35329389758と一致する失敗境界。

これにより現CI環境での現象は、JibunKit backup decode/restoreやSwiftUI経路だけに固有ではなく、独立UIKitでも再現すると判断できる。Apple OS一般のバグ、全端末での再現、provider内部の根本原因までは確定していない。新規端末でも再現したためrunner既設端末の状態だけでは説明できない。

0.8.4候補の実機JSON書出し・読込成功は独立した証拠として維持する。製品コードを変更せず、同じ操作/座標/待機時間変更のCI反復は終了。Files自動gateを修復済みとはしない。環境/runtimeの変化やprovider診断に新しい根拠が得られた時点で、この独立fixtureを再利用する。
