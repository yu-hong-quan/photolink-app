import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_env.dart';
import '../core/constants.dart';
import '../theme/app_theme.dart';

/// 作者 / 产品信息页（App / PC 共用结构）
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.clientLabel});

  /// 如「手机端」「电脑端」
  final String clientLabel;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _pkg;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _pkg = p);
    });
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse(PhotoLinkConst.authorGithub);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开链接，已复制到剪贴板')),
      );
      await Clipboard.setData(
        const ClipboardData(text: PhotoLinkConst.authorGithub),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = _pkg == null
        ? '…'
        : '${_pkg!.version}（${_pkg!.buildNumber}）';
    return Scaffold(
      appBar: AppBar(title: const Text('关于作者')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    PhotoLinkTheme.brand,
                    PhotoLinkTheme.brand.withValues(alpha: 0.75),
                  ],
                ),
              ),
              child: const Icon(Icons.link_rounded, color: Colors.white, size: 36),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${PhotoLinkConst.appName} · ${PhotoLinkConst.appNameZh}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.clientLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5A6F6D)),
          ),
          const SizedBox(height: 20),
          _InfoTile(label: '版本', value: version),
          _InfoTile(label: '运行环境', value: AppEnv.flavorLabel),
          _InfoTile(
            label: '相册端口',
            value: '${PhotoLinkConst.port}',
          ),
          _InfoTile(
            label: '配对端口',
            value: '${PhotoLinkConst.pairPort}',
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _InfoTile(label: '作者', value: PhotoLinkConst.authorName),
          _InfoTile(label: 'GitHub', value: PhotoLinkConst.authorId),
          const SizedBox(height: 12),
          Text(
            PhotoLinkConst.productDesc,
            style: const TextStyle(
              color: Color(0xFF5A6F6D),
              height: 1.5,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: _openGithub,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('打开作者 GitHub'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      '${PhotoLinkConst.authorName} ${PhotoLinkConst.authorGithub}',
                ),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制作者信息')),
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('复制作者信息'),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF5A6F6D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
