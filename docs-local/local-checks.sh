#!/usr/bin/env bash
# 派生hostのローカル検証（CIを回す前に、ここで落とせるものは落とす）
#
# 実行方法（Windows側のbashから）:
#   wsl.exe -e bash -lc 'bash /mnt/c/Users/YHide/Documents/JibunKitHome/docs-local/local-checks.sh'
#
# 前提: WSLにswiftlyと Darwin SDK (iPhoneOS 26.5) が入っていること。
#       SDKが無い場合は 3) 4) をスキップし、1) 2) だけでも意味がある。
set -uo pipefail

source ~/.local/share/swiftly/env.sh
cd /mnt/c/Users/YHide/Documents/JibunKitHome

B=$HOME/.swiftpm/swift-sdks/darwin.artifactbundle
SDK=$B/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk
RC=$B/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift
INC=$B/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib

fail=0
step() { echo; echo "== $1 =="; }

step "1) Feature の Linux テスト（Foundationロジック）"
swift test --package-path Modules/Zaiko 2>&1 | tail -5 || fail=1

if [ -d "$SDK" ]; then
  step "2) Feature の iOS ビルド"
  swift build --package-path Modules/Zaiko --swift-sdk arm64-apple-ios 2>&1 | tail -3 || fail=1

  step "3) ホスト接続と依存ターゲットの iOS ビルド"
  for t in JibunKitCore JibunKitBackup CounterFeature ReminderFeature CounterIntegration ReminderIntegration ZaikoIntegration; do
    printf '%-20s ' "$t"
    swift build --swift-sdk arm64-apple-ios --target "$t" 2>&1 | tail -1 || fail=1
  done

  step "4) アプリ本体ソースの iOS 型検査（Tuist生成物は含まない）"
  BIN=$(swift build --target ZaikoIntegration --swift-sdk arm64-apple-ios --show-bin-path 2>/dev/null)
  out=$(swiftc -typecheck -swift-version 6 -target arm64-apple-ios26.0 -sdk "$SDK" -resource-dir "$RC" \
      -I "$INC" -I "$BIN/Modules" -I "$BIN" -Xfrontend -enable-cross-import-overlays \
      Sources/JibunKit/*.swift 2>&1 | grep -E "error:" | head -20)
  if [ -n "$out" ]; then echo "$out"; fail=1; else echo "typecheck OK (11 files)"; fi
else
  echo "Darwin SDK が無いため 2)〜4) をスキップしました"
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL LOCAL CHECKS PASSED"; else echo "LOCAL CHECKS FAILED"; fi
exit $fail
