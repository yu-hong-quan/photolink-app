import 'package:flutter/material.dart';

import 'core/constants.dart';
import 'pages/home_page.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotoLinkApp());
}

class PhotoLinkApp extends StatelessWidget {
  const PhotoLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${PhotoLinkConst.appName} · ${PhotoLinkConst.appNameZh}',
      debugShowCheckedModeBanner: false,
      theme: PhotoLinkTheme.light(centerTitle: true),
      home: const HomePage(),
    );
  }
}
