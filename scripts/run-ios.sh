#!/usr/bin/env bash
# 运行 iOS 调试
# 用法：./scripts/run-ios.sh local

set -euo pipefail
ENV_NAME="${1:-local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
flutter pub get
flutter run --dart-define="FLAVOR=$ENV_NAME"
