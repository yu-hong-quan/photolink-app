# 发布产物说明

正式安装包下载：

- 手机端 APK（arm64）：  
  https://github.com/yu-hong-quan/photolink-app/releases/download/v1.1.1/PhotoLink-1.1.1-prod-arm64.apk
- 电脑端 Setup：  
  https://github.com/yu-hong-quan/photolink-pc/raw/master/releases/PhotoLink-Setup-1.1.1-prod.exe

本地重新打包：

```bash
.\scripts\build-android.ps1 -Env prod
flutter build apk --release --split-per-abi --dart-define=FLAVOR=prod
```
