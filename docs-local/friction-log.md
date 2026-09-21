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

## F-003 公開基盤の workflow を派生側でそのまま使えるか

- **症状**: `.github/workflows/build-ios.yml` はリリース公開・artifact公開・多数の検証入力を含む。派生側で同じものが動くのか、secrets / permissions / 公開先の前提が読み取れない。
- **実測（解決）**: 派生側の公開リポジトリで既定入力の実行が **成功**（run 35237198657、job `Xcode 26.6 (combined)`、IPA生成と検査まで通過）。`secrets.` は一切使われておらず、`permissions: contents: read` のみで動作した。固定SHA-256でのTuist導入も派生側で通った。
- **影響を受ける人**: 派生host利用者（Windows中心の利用者全員）。
- **残る不明点**: 既定以外の入力群（`simulator_tests` / `feature_validation` / native比較）を派生側で回したときの挙動、リリースや公開先に依存するstepがあるか。Simulator回帰は今回未実行。

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

## F-009 派生側でworkflowを回すと、既定ではupstream側のリポジトリで起動してしまう

- **症状**: 派生hostには remote が2つある（`origin`＝派生、`upstream`＝公開基盤）。`docs/build.md` の実行例は `gh workflow run build-ios.yml --ref YOUR_BRANCH -f ...` で、`--repo` も「既定リポジトリの設定」も書かれていない。
- **実測**: `gh repo set-default --view` は "No default remote repository has been set" を返し、その状態で実行すると **ghは `upstream`（公開基盤＝y-aplus/JibunKit）側に run を作った**。気付いて取り消したが、取り消し前は `queued` で、そのまま進めば基盤リポジトリで実機用IPAのビルドが走っていた。`gh repo set-default y-aplus/JibunKitHome` で固定して解決。
- **影響**: プラットフォーム側リポジトリに無関係なrunが作られ、Actions分数も消費する。派生側の作業が基盤側の履歴に現れる。
- **影響範囲の切り分け（重要）**: workflow_dispatchは[対象リポジトリへのwrite権限（`repo` / `actions:write`）が必要](https://docs.github.com/rest/actions/workflows)。よって**実害が出るのは基盤リポジトリにwrite権限を持つ人＝メンテナーだけ**。権限の無い一般ユーザーはrunを作れず `Not Found` で失敗するだけ。一般ユーザー側に残るのは「対象が曖昧なまま失敗し、原因（既定リポジトリ未設定）がどこにも書かれていない」という軽い摩擦。
- **仕分け**: 実害はメンテナー固有。ただし修正は1行（`gh repo set-default` を手順に足す、または例に `--repo` を明示）で一般ユーザーにも効くため、upstream提案の優先度は低〜中。派生側の手順には先に入れる。
- **不足**: 派生側でworkflowを実行する手順に「`gh repo set-default`（または `--repo` の明示）」を追加する。

## F-010 Core Spotlight Search Continuation (アプリで検索) のホスト基盤受け口がない

- **症状**: Spotlight 最下部の「アプリで検索」からアプリへ検索クエリを渡す `CSQueryContinuationActionType` について、ホスト（`JibunKitApp` / `Project.swift` / `MiniAppSpotlight.swift`）に受け口やミニアプリへの配送ルートがない。
- **派生側での対処**: 基盤本体への直接改変を避け、まずは個別アイテムの直接タップ（`CSSearchableItemActionType`）とアプリ内検索・ユーザー辞書機能で完結させ、Search Continuation は基盤改善提案として仕様書（`docs-local/spotlight-continuation-proposal.md`）にまとめた。
- **影響**: Spotlight を活用した検索・ランチャー系ミニアプリを作ろうとするすべての開発者。

## F-011 外部アプリ起動 (URL Scheme open) の共通ポリシー・支援がJibunKitCoreにない

- **症状**: Feature から他のアプリ（URL Scheme）を起動する際、Feature 側で直接 `UIApplication.shared.open` を呼ぶ必要があり、JibunKit 共通での URL Scheme 遷移確認や安全性チェック（不正な URL の排除）の仕組みがない。
- **派生側での対処**: Feature 側の `appendDestination` で対象の URL Scheme を安全にパースして起動。

## F-012 Actions ArtifactがZIP形式でしか取得できず、実機導入時に手動展開またはRelease添付を強いられる

- **症状**: `.github/workflows/build-ios.yml` で生成される成果物 `JibunKit-ad-hoc` は GitHub Actions の Artifact 仕様により、ブラウザや iPhone (Safari) からダウンロードする際に必ず単一の `.zip` にまとめられる。そのため、iPhone 実機で SideStore 等を用いてインストールする際、「ZIPをダウンロード → ファイルアプリ等で展開 → 中の `.ipa` を取り出す」という余分な手動ステップを強いられる。
- **基盤ルールの制約**: `docs/updating.md` によると `workflows` は foundation-owned（基盤所有）であり、派生側で `.github/workflows/build-ios.yml` を直接編集して Release への自動アップロード等を組み込むことは、今後の upstream マージ時の継続的な競合原因となるため推奨されない（Integration points に含まれない）。
- **派生側での対処**: 必要なビルドごとに、手元から GitHub CLI（`gh release create <tag> JibunKit.ipa --prerelease`）を使ってプレリリースを作成し、生の `.ipa` ファイルを直接ダウンロードできるダイレクトリンクを提供する運用とした。
- **不足**: 基盤公式の workflow または配布手順において、SideStore 等での実機インストールを想定した「生の `.ipa` をワンアクションで取得できる推奨手順（例: 派生ホスト向けのオプショナルな Release 配置手順の明記、または独立した配布ワークフローの案内）」が不足している。

## F-013 Core Spotlight のタイトル最優先マッチングと略称（keywords / alternateNames）露出の壁

- **症状**: `CSSearchableItemAttributeSet` の `keywords` や `alternateNames` に略称・別名（例: 「マック」「sbux」「トーク」）を設定しても、Spotlight の検索結果に表示されない、または極端に下位に押し下げられてユーザーが見つけられない。
- **実測と結論**: iOS の Spotlight スコアリングアルゴリズムは `title`（タイトル）の一致を圧倒的に重視する。`keywords` に頼るのではなく、`title` 自体に `マクドナルド (マック / mac)` のように主要な略称を組み込むことで、短縮形でも 100% 確実にタイトル一致として最上位にヒットするようになる。ただし、「トーク」や「ライン」のようにシステム辞書や既存の連絡先・メッセージ等と強く競合する汎用単語は、システムのエンゲージメントスコアや候補過多により依然として露出が制限される場合がある。

## F-014 Spotlight ルーティング直後の外部アプリ起動（openURL）におけるライフサイクル競合

- **症状**: Spotlight の検索結果をタップしてアプリがバックグラウンドから復帰（または起動）する際、`onContinueUserActivity` 内で即座に同期的に `UIApplication.shared.open(url)` を呼ぶと、iOS がアプリを完全にフォアグラウンド・アクティブ化する前の状態であるため、外部 URL 起動リクエストがサイレントに破棄され、「ホスト（JibunKit）画面が開くだけで対象の外部アプリが開かない」現象が発生する。
- **派生側での対処**: `Task { @MainActor in try? await Task.sleep(nanoseconds: 350_000_000); UIApplication.shared.open(...) }` のように、ウィンドウシーンのアクティブ化が完了するまでわずかなディレイ（約0.35秒）を設けてから起動する。さらに、画面上部に「起動中... [開く]」というフォールバック再試行バナーを設けることで、確実な起動導線を確立。

