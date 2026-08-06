# PhotoLink App（图联 · 手机端）

局域网相册 HTTPS 服务端 + mDNS 广播。

## 运行

```bash
flutter pub get
flutter run
```

## 目录

- `lib/services/photo_https_server.dart` — Shelf HTTPS API
- `lib/services/gallery_service.dart` — photo_manager 封装
- `lib/services/mdns_advertise_service.dart` — 设备广播
- `lib/pages/home_page.dart` — 状态 / IP / 二维码
