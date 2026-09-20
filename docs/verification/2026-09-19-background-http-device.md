# 背景HTTPのprocess終了後復元 — 実機確認結果

## 実機結果・停止解除

ユーザーから `cold復元chain: 成立（OSの起動契機は未判定） run=78450873 task=1 size=10 sha256=6e9ba2d4743b72079ae971666d7e61f0587704fbcfcd4f874ebb2a6a700d4435` を受領。保存済み証拠表示ボタンを押す前に表示されていた。完了callbackから自動表示する実装と整合する。診断終了した元processと別processで、同一run/taskのOS callback・owner再接続・保存・completion返却までの永続証拠が成立した。OSがprocessを起動した契機や配送時間は未判定である。

その後ユーザーが停止を明示解除したため開発を再開。以下は当時の停止境界と実施手順の記録であり、現在の再操作依頼ではない。

ユーザー予告に従い、このIPAと手順の提示を境に実装・新規CIを停止する。再開指示までは新しい作業を始めない。位置のgeofenceは今回Simulatorで成功したため、実機の歩行やAndroid/iPad操作を追加依頼しない。

source: `4a1340ab3cedfe10fded79fa975d4a4bd65d160c`。CI35365770330成功、native87件・OS UI6件、失敗0/skip0。geofenceの実enter/exitは58.701秒。診断IPAは0.8.5/build15、6,526,208 bytes、SHA-256 `5351a1b3555a6766a8271b5aec9f67db0ec4c13ac1df581739922de5178744ee`。全entry CRCと版を取得後確認。通常0.8.5とは異なる診断構成である。

## 実施済み手順

1. [診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-http-cold-check-20260919/JibunKit-P2-combined-check.ipa)を上書きし、**Background A**を開く。下部の「診断HTTP URL」までスクロールする。
2. 次のURLを貼る。

   `https://httpbingo.org/drip?duration=10&numbytes=10&delay=0&code=200`

3. **background download開始**を押し、開始表示が出たらすぐ隣の**転送中のprocessを終了（診断）**を一度押す。アプリが閉じるのが意図した動作。アプリ切替画面からの強制終了はしない。終了を拒否されたら、その表示を報告して止める。
4. JibunKitを開かず約1分待つ。その後開き、**Background A → 保存済みの転送証拠を表示**を押す。
5. **報告:** 表示された「cold復元chain」の文をそのまま送る。未成立でも開始ボタンを繰り返し押さない。

「成立（OSの起動契機は未判定）」は、別processでOS callback・同じ転送の保存・completion返却が揃った証拠。OSが自動で起動した時刻や、一定時間内配送の保証とはしない。「未成立」は今回の証拠が揃わないという意味であり、それだけで製品不具合と断定しない。

通常版へ戻すときは[正式0.8.5 IPA](https://github.com/y-aplus/JibunKit/releases/download/0.8.5/JibunKit.ipa)。今回戻し操作の反復確認は依頼しない。
