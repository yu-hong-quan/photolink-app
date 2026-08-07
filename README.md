# PhotoLink App（图联 · 手机端）

局域网相册 HTTPS 服务端 + mDNS 广播；可扫码或主动搜索电脑配对。

## 运行

```bash
flutter pub get
# 本地环境
flutter run --dart-define=FLAVOR=local
# 或
./scripts/run-android.ps1 -Env local   # Windows
./scripts/run-ios.sh local             # macOS
```

## 打包（local / test / prod）

| 环境 | 相册端口 | 配对端口 |
|------|----------|----------|
| local | 53337 | 53338 |
| test | 53327 | 53328 |
| prod | 53317 | 53318 |

```bash
# Android APK
.\scripts\build-android.cmd prod
# 或 .\scripts\build-android.ps1 -Env test

# Android AAB（上架）
.\scripts\build-android-aab.ps1 -Env prod

# iOS（需 macOS + Xcode）
./scripts/build-ios.sh prod
```

**注意：手机与电脑必须使用同一 FLAVOR。**

## 目录

- `lib/services/photo_https_server.dart` — Shelf HTTPS API
- `lib/services/mdns_pc_discovery_service.dart` — 搜索电脑
- `lib/pages/discover_pc_page.dart` — 选电脑连接
- `lib/pages/about_page.dart` — 作者信息
- `scripts/` — 多环境运行 / 打包脚本
