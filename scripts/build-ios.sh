#!/usr/bin/env bash
# 打包 iOS（需在 macOS + Xcode 执行）
# 用法：./scripts/build-ios.sh prod
# 产物：build/ios/iphoneos/Runner.app ；可用 Xcode Archive 进一步导出 IPA

set -euo pipefail
ENV_NAME="${1:-prod}"
case "$ENV_NAME" in
  local|test|prod) ;;
  *) echo "用法: $0 local|test|prod"; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEFINES=(--dart-define="FLAVOR=$ENV_NAME")
echo "PhotoLink iOS FLAVOR=$ENV_NAME"

flutter pub get
flutter build ios --release "${DEFINES[@]}"

echo "完成：build/ios/iphoneos/Runner.app"
echo "提示：打开 ios/Runner.xcworkspace 用 Xcode Archive 导出 IPA / 上架。"
