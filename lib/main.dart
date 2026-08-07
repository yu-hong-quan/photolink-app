import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'pages/home_page.dart';
import 'services/delete_confirm_bridge.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotoLinkApp());
}

class PhotoLinkApp extends StatefulWidget {
  const PhotoLinkApp({super.key});

  @override
  State<PhotoLinkApp> createState() => _PhotoLinkAppState();
}

class _PhotoLinkAppState extends State<PhotoLinkApp> {
  /// 供删除确认桥接在后台 HTTP 回调中弹出前台对话框
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    DeleteConfirmBridge.instance.navigatorKey = _navKey;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: '${PhotoLinkConst.appName} · ${PhotoLinkConst.appNameZh}',
      debugShowCheckedModeBanner: false,
      theme: PhotoLinkTheme.light(centerTitle: true),
      home: const HomePage(),
    );
  }
}
