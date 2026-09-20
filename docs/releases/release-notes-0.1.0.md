# JibunKit 0.1.0

SideStoreで使う、自作ミニアプリを1本のnative iOS appへまとめる基盤の最初の実験的releaseです。

## 主な内容

- ミニアプリ一覧、共有counter、独立したreminder。
- 数値を加算して更新値を返すApp Shortcut。
- 3サイズの表示専用Widget。
- 利用者の操作で予約し、tapで対象画面へ戻るlocal notification。
- ミニアプリ追加、基盤更新、Windows/WSLとGitHub Actionsでのbuild、SideStore導入・更新の手順。

## 確認済み環境

- iPhone 16e
- iOS 26.6
- SideStore 0.6.3
- GitHub Actions `macos-26` / Xcode 26.6 / xtool 1.17.0

JibunKit識別子で初回導入、build 2への上書き、SideStore署名更新まで確認済みです。

導入と署名更新は[SideStore導入・更新手順](../sidestore.md)、buildの再現方法は[build手順](../build.md)を参照してください。

## 既知の制限

- 確認済みの端末・OS・SideStoreの組合せは上記だけです。
- 無料Apple Accountでの導入には定期的な署名更新が必要です。
- Widgetの表示更新時刻はiOSが決めるため、app本体より遅れることがあります。
- 既存IPAの変換、mini-app store、remote backendは含みません。
- Actions artifactはad-hoc署名です。利用者の端末でSideStoreが最終署名します。

変更の全体は[CHANGELOG.md](../../CHANGELOG.md)、検証結果は[docs/verification/0.1.md](../verification/0.1.md)を参照してください。
