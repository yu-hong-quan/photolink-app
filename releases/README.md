# 发布产物说明

正式安装包请下载：

- [PhotoLink-1.1.1-prod-arm64.apk](./PhotoLink-1.1.1-prod-arm64.apk)（若本目录已随仓库提供）
- 或到仓库 Releases / 本 README 顶部「下载安装」区获取

打包命令：`.\scripts\build-android.ps1 -Env prod` 后执行分架构：

`flutter build apk --release --split-per-abi --dart-define=FLAVOR=prod`
