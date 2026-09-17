# 再開メモ（次にHermesを開いたとき用）

最終更新: 2026-09-18 深夜。作業はすべてコミット済み・push済み（main）。

## 今の状態

- 派生hostのZaiko追加は完了。ローカルの全ゲートとCI（既定入力）は成功済み
- 実機用IPA: prerelease `zaiko-check-20260918`（Zaikoが本体バイナリに入っていることを検査済み）
- **実機確認は未実施**（JibunKit本流の実機確認が端末を占有しているため待ち）
- 摩擦ログ F-001〜F-009 と仕分け（`triage.md`）は記録済み。upstreamへの提案候補は F-001 / F-002 / F-004 / F-007

## 途中だったもの: Simulator UI回帰の1件失敗の切り分け

Hermesを閉じたため監視プロセスは消えたが、GitHub側の実行は進んでいる。条件を揃えた2本を並行実行中だった。

| run | ref | 内容 |
| --- | --- | --- |
| `35243975880` | `main`（Zaikoあり） | `simulator_tests=true` のフルレーン |
| `35244030756` | `base-check`（Zaikoなし） | 同上（比較用） |

確認コマンド:

```bash
gh run view 35243975880 --repo y-aplus/JibunKitHome --json status,conclusion
gh run view 35244030756 --repo y-aplus/JibunKitHome --json status,conclusion
gh run view <id> --repo y-aplus/JibunKitHome --log --log-failed 2>/dev/null | grep -E "testZIPFilesRoundTripRestoresAttachment.*(passed|failed)|Executed [0-9]+ tests, with"
```

判定と次の手:

- **両方 success** → 前回の失敗は単発のフレーク（Filesピッカーの既知の不安定領域）。結論を `verification.md` に追記して閉じる
- **base success / main failure** → Zaiko追加と相関。ハーネスアプリにZaiko依存は無いので、本体アプリ側の何が影響するかを疑う（起動時処理、App Groupへの書込み、通知予約の有無）。`-f simulator_tests=true -f focused_ui_validation=true -f ui_test_filter=MigrationUITests/BackupRestoreUITests/testZIPFilesRoundTripRestoresAttachment` で反復して再現性を確認する
- **両方 failure** → 環境依存（既知領域）として記録し、Zaikoとは切り離す

## 失敗の内容（参照）

- 失敗run: `35239234258`（main、フルレーン。13テスト中1件失敗）
- 失敗箇所: `UITests/BackupRestoreUITests.swift:141` — ファイル書き出しシートで「保存」を押した後、ファイル名欄（`DOCPicker.filenameTextField`）が10秒以内に現れない。OSのピッカー表示待ち
- 比較用の先行実行: `35242664507`（base、focusedレーン）は**成功**（124.9秒）
- 操作対象は検証用アプリ `com.jibunkit.backup-harness`（Zaikoは依存に入っていない）

## 実機が空いたらやること

1. SideStoreで `zaiko-check-20260918` のIPAを**既存JibunKitを消さずに**上書きインストール（ad-hoc署名なのでSideStoreで再署名）
2. 一覧に「在庫管理」→ JSONバックアップ読込み → アラート品目の見え方 → 通知／通知タップ → 既存Counter・Reminderの値維持 → 管理画面の無効化・削除、を確認
3. 結果を `verification.md` に追記し、摩擦の追加分を `friction-log.md` へ

## ローカルの入口

```bash
wsl.exe -e bash -lc 'bash /mnt/c/Users/YHide/Documents/JibunKitHome/docs-local/local-checks.sh'
```
