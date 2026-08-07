import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';
import '../services/device_bootstrap_service.dart';
import '../services/mdns_advertise_service.dart';
import '../services/photo_https_server.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
import 'scan_pc_qr_page.dart';

/// 手机端首页：服务状态、扫码连电脑、本机信息
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _mdns = MdnsAdvertiseService();
  PhotoHttpsServer? _server;
  DeviceInfoModel? _info;
  String _status = '正在初始化…';
  bool _running = false;
  /// PC 是否已访问过本机 API（用于状态文案，不仅依赖启动瞬间）
  bool _pcConnected = false;
  String? _pcIp;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shutdown();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      setState(() {
        _status = '应用已进入后台，局域网服务可能中断，请回到前台';
      });
    } else if (state == AppLifecycleState.resumed && _running) {
      setState(() => _status = _connectedStatusText());
    }
  }

  /// 按是否已有 PC 访问生成状态文案
  String _connectedStatusText() {
    if (!_pcConnected) return '服务运行中，等待 PC 连接';
    final ip = _pcIp;
    if (ip == null || ip.isEmpty) return 'PC 已连接，可传输相册';
    return 'PC 已连接（$ip），可传输相册';
  }

  void _onClientActivity(String? remoteIp) {
    if (!mounted || !_running) return;
    final changed = !_pcConnected ||
        (remoteIp != null && remoteIp.isNotEmpty && remoteIp != _pcIp);
    if (!changed) return;
    setState(() {
      _pcConnected = true;
      if (remoteIp != null && remoteIp.isNotEmpty) {
        _pcIp = remoteIp;
      }
      _status = _connectedStatusText();
    });
  }

  Future<void> _bootstrap() async {
    setState(() {
      _error = null;
      _pcConnected = false;
      _pcIp = null;
      _status = '正在申请权限…';
    });
    final err = await DeviceBootstrapService.instance.ensurePermissions();
    if (err != null) {
      setState(() {
        _error = err;
        _status = '权限不足';
      });
      return;
    }

    final info = await DeviceBootstrapService.instance.buildDeviceInfo();
    final server = PhotoHttpsServer(
      deviceInfo: info,
      onClientActivity: _onClientActivity,
    );
    try {
      setState(() => _status = '正在启动 HTTPS 服务…');
      await server.start();
      await _mdns.start(info);
      setState(() {
        _info = info;
        _server = server;
        _running = true;
        _status = _connectedStatusText();
      });
    } catch (e) {
      setState(() {
        _error =
            '启动失败：$e\n请检查端口 ${PhotoLinkConst.port} 是否被占用，以及防火墙是否放行。';
        _status = '启动失败';
        _running = false;
      });
    }
  }

  Future<void> _shutdown() async {
    await _mdns.stop();
    await _server?.stop();
    _server = null;
    _running = false;
    _pcConnected = false;
    _pcIp = null;
  }

  Future<void> _restart() async {
    await _shutdown();
    await _bootstrap();
  }

  Future<void> _openScanner(DeviceInfoModel info) async {
    // 进入扫码页前先预请求一次，减少首次进入直接 denied 的概率
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要相机权限'),
          content: const Text('扫码连接电脑需要使用相机，请在系统设置中开启权限。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去设置'),
            ),
          ],
        ),
      );
      if (go == true) await openAppSettings();
      return;
    }
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未授予相机权限，无法扫码')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ScanPcQrPage(phoneInfo: info),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return SoftGradientBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('${PhotoLinkConst.appName} · ${PhotoLinkConst.appNameZh}'),
          actions: [
            IconButton(
              tooltip: '刷新 / 重启服务',
              onPressed: _restart,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              FadeSlideIn(
                child: _HeroHeader(running: _running),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: _StatusCard(
                  running: _running,
                  status: _status,
                  error: _error,
                ),
              ),
              if (info != null) ...[
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: _ScanCard(
                    enabled: _running,
                    onScan: () => _openScanner(info),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: _InfoCard(info: info),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 260),
                  child: _QrCard(payload: info.toConnectPayload()),
                ),
              ],
              const SizedBox(height: 16),
              FadeSlideIn(
                delay: const Duration(milliseconds: 320),
                child: const _TipsCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PhotoLinkTheme.brand, PhotoLinkTheme.brandDark],
        ),
        boxShadow: [
          BoxShadow(
            color: PhotoLinkTheme.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.photo_library_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '局域网相册互联',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  running ? '服务已就绪，可扫电脑二维码配对' : '正在准备本机相册服务…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.running,
    required this.status,
    this.error,
  });

  final bool running;
  final String status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final color = error != null
        ? Colors.red
        : running
            ? const Color(0xFF1FA87A)
            : PhotoLinkTheme.accent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            PulseDot(color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Text(
                      status,
                      key: ValueKey(status),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: TextStyle(color: Colors.red.shade700)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.enabled, required this.onScan});

  final bool enabled;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              PhotoLinkTheme.brand.withValues(alpha: 0.10),
              PhotoLinkTheme.accent.withValues(alpha: 0.08),
            ],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '扫码连接电脑',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '打开电脑 PhotoLink，扫描电脑左侧（或弹窗）中的配对二维码。',
              style: TextStyle(color: Color(0xFF5A6F6D), height: 1.4),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: enabled ? onScan : null,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('扫描电脑二维码'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.info});

  final DeviceInfoModel info;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本机信息',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _kv('设备名', info.deviceName),
            _kv('系统', info.osVersion),
            _kv('局域网 IP', info.ip),
            _kv('端口', '${info.port}'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: '${info.ip}:${info.port}'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制 IP:端口')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('复制地址'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(k, style: const TextStyle(color: Color(0xFF5A6F6D))),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.payload});

  final String payload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              '兜底连接串',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '优先扫电脑二维码。此处仅作电脑端手动粘贴兜底。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5A6F6D)),
            ),
            const SizedBox(height: 16),
            BreathingBorder(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: payload,
                  size: 180,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: PhotoLinkTheme.brandDark,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: PhotoLinkTheme.brandDark,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              payload,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A9C9A)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '使用提示',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            _tip('手机与电脑需同一 WiFi，关闭 AP 隔离'),
            _tip('推荐：电脑显示二维码 → 手机扫码配对'),
            _tip('iOS 请保持 App 前台，退后台会中断服务'),
            _tip(
              '防火墙放行 TCP ${PhotoLinkConst.port}、${PhotoLinkConst.pairPort} 与 UDP 5353',
            ),
          ],
        ),
      ),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 18, color: PhotoLinkTheme.brand.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );
  }
}
