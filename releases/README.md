# 发布产物说明

正式安装包下载：

- 手机端 APK（arm64）：  
  https://github.com/yu-hong-quan/photolink-app/releases/download/v1.1.1/PhotoLink-1.1.1-prod-arm64.apk
- 电脑端 Windows Setup：  
  https://github.com/yu-hong-quan/photolink-pc/raw/master/releases/PhotoLink-Setup-1.1.1-prod.exe
- 电脑端 macOS DMG：  
  https://github.com/yu-hong-quan/photolink-pc/raw/master/releases/PhotoLink-1.1.2-prod-macos.dmg

**iOS**：暂无公开安装包。Apple 不允许像 APK 一样任意分发 IPA；请使用 Android，或自行用 Xcode / Flutter 对本机设备签名安装。详见仓库根目录 README「iOS 说明」。

本地重新打包：

```bash
# Android APK
.\scripts\build-android.ps1 -Env prod
# 或
flutter build apk --release --split-per-abi --dart-define=FLAVOR=prod

# iOS（仅自用，需 Mac + Xcode 签名）
./scripts/build-ios.sh prod
```
