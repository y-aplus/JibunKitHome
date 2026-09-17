# 派生hostで詰まった点（初見ユーザー体験の一次データ）

作業: Zaiko（在庫管理）を個人用ミニアプリとして派生hostへ追加する。
記録者: エージェント（ユーザーはJibunKitの作者。作者でない「ゆる開発者」を想定して、公開文書だけを頼りに進める）。

## 記録のルール

- 公開されている文書（`docs/updating.md` / `docs/mini-apps.md` / `docs/superpowers/specs/2026-08-28-jibunkit-foundation-design.md` / README）だけを読んで進める。
- 文書に書かれておらず、自分で決めた操作は「決めた内容」と「根拠にした文書の不足点」をセットで残す。
- 詰まりは upstream への改善提案候補として仕分ける（提案そのものはユーザー判断）。

## F-001 派生リポジトリの作り方そのものが文書にない

- **症状**: 方針（foundation-design §4「個人用スーパーアプリと自作ミニアプリは、基盤のGit履歴を引き継いだ独立した非公開リポジトリに置く」）と更新手順（updating.md「公開リポジトリを`upstream`、個人用forkを`origin`」）はあるが、**最初に何をcloneし、何という名前で、どのリモートをどう張るか**の手順がない。
- **自分で決めた内容**: ローカルの基盤作業コピーから `git clone --no-hardlinks` し、`origin` を `upstream` に改名、`upstream` のURLを公開リポジトリに差し替え、`origin` は自分の非公開リポジトリを作った時点で追加する。
- **不足**: 「upstream/origin の初期構成を作る」1〜3行の例。Fork機能を使わない理由（公開になる）は書かれているのに、代わりの具体操作がない。

## F-002 bundle ID / App Group を派生側で維持するのか変えるのかが間接的

- **症状**: `updating.md` の「対応範囲」に「同じAppleアカウント、bundle ID、App Groupを維持したソース更新と上書きインストール」とあるだけで、**派生側の初期設定でどうすべきか**は書かれていない。
- **自分で決めた内容**: 既存端末のJibunKitを上書き更新する形にするため、bundle ID / App Group は基盤のまま維持した。
- **不足**: 派生側の初期設定で決める値（bundle id を変えるか、App Group を共有するか）の推奨。

## F-003 公開基盤の workflow を派生側でそのまま使えるか未検証

- **症状**: `.github/workflows/build-ios.yml` はリリース公開・artifact公開・多数の検証入力を含む。派生側（非公開 or 別リポジトリ）で同じものが動くのか、secrets / permissions / 公開先の前提が読み取れない。
- **状態**: CI 実行の段で実測する（未解決）。

## F-004 Feature の置き場所の選択基準が薄い

- **症状**: `mini-apps.md` は「`Modules/<Name>` に独立Package」と「root Package 内（`Sources/...`）」の両方を許容し、どちらを選ぶべきかの判断材料が薄い。
- **自分で決めた内容**: `Modules/Zaiko` を選んだ。理由は (1) Windows/WSL でも `swift test --package-path Modules/Zaiko` がローカルで回る（root Package は Linux でビルドできない）、(2) 単独動作の検証ができる。
- **不足**: 選択基準（ローカル検証可能性、単独アプリとしての再利用、CIのコスト）の1行ずつ。

## F-005 派生側の自分用メモの置き場所が無い

- **症状**: `docs/` は基盤の文書。個人用の作業メモを混ぜるとマージ競合の原因になる。このファイルは `docs-local/` に置いた（基盤の文書と分離）。
- **自分で決めた内容**: `docs-local/` を派生側の私的文書置き場とする（upstream へのマージ対象外）。
- **不足**: 派生側に置く文書の推奨ディレクトリと、競合を避ける方針。

## F-006 iOS型検査のローカル手段が文書化されていない

- **症状**: `docs/build.md` は「xtoolによるIPA生成経路は廃止した」とだけ書いており、WSLに残っている Darwin SDK（`swift sdk list` に `darwin`、iPhoneOS 26.5）を**型検査に使えること**はどこにも書かれていない。IPA生成とコンパイル確認は別の話なのに、まとめて廃止として書かれている。
- **実測**: `swift build --package-path Modules/Zaiko --swift-sdk arm64-apple-ios` が `Build complete!`。これで `#if os(iOS)` の中（SwiftUI/Combine/UserNotifications を使う store と RootView）の誤りを**CI往復なしで**検出できた。実際にこの経路が適応漏れ（旧キー名の残存）を1件見つけた。
- **不足**: 「WSLでiOS向けにコンパイルだけ確認する」手順（IPA生成とは分けて）。

## F-007 ルートパッケージはLinuxでビルドできない（文書の主張と不一致）

- **症状**: `docs/build.md` は「SwiftのあるmacOS／Linux／WSLでは`swift test`でFoundationロジックを確認できる」と書いているが、main の `JibunKitCore` は CryptoKit / FoundationNetworking / security-scoped resource で Linux ビルド不能。リポジトリ直下の `swift test` は通らない。
- **派生側への影響**: 「Featureを足してローカルでテストする」が、**独立Package（`Modules/` 配下）でないと成立しない**。派生側の作業者にとっては、Featureを `Modules/` に置くべき積極的な理由の1つになる（F-004の判断根拠）。
- **状態**: upstream 側の改善候補（別タスクとして切り出し済み。派生hostでは触らない）。

## F-008 非macOS環境で「ローカルにどこまでできるか」の一覧が無い

- **症状**: `docs/build.md` は「macOSで実行」と「WindowsからIPAを生成（Actions）」の2経路しか示しておらず、Windows／WSL側で**ローカルに検証できる範囲の一覧**が無い。結果として、実際にはローカルでできることまで「CIでしか確認できない」と扱ってしまう（この作業でも、最初にそう判断して計画に入れてしまった）。
- **実測（TuistはLinuxでも動くのか）**: Tuist 4.207.0 は Mise 経由で Linux に**入る**（`tuist-linux-x86_64.tar.gz`、`tuist version` → `4.207.0`）。しかし**コマンド体系が別物で、ローカル生成のCLIではない**。`tuist generate` は `list` / `show` の2つのみ（＝サーバー側の生成記録を見るコマンド）で、文書が使う `tuist scaffold` は存在しない。プロジェクト生成・scaffoldは実行できない。
- **結論**: 文書の「macOSで実行」「Windowsでは手動作成してActionsで検証」という記述は妥当。ただし「Linux版Tuistは入るのに生成はできない」という区別が文書に無いため、非macOS利用者が試して時間を使う余地がある（この作業では実際に試して往復1回分を使った）。
- **不足**: ローカルでできること／できないことの一覧（と、できる場合に必要なツールと版）。
