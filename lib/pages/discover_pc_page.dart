import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/device_info.dart';
import '../services/mdns_pc_discovery_service.dart';
import '../services/pc_pair_client.dart';
import '../theme/app_theme.dart';

/// App 主动搜索局域网电脑并选择连接（配对）
class DiscoverPcPage extends StatefulWidget {
  const DiscoverPcPage({super.key, required this.phoneInfo});

  final DeviceInfoModel phoneInfo;

  @override
  State<DiscoverPcPage> createState() => _DiscoverPcPageState();
}

class _DiscoverPcPageState extends State<DiscoverPcPage> {
  final _discovery = MdnsPcDiscoveryService();
  StreamSubscription<List<DeviceInfoModel>>? _sub;
  final _pcs = <String, DeviceInfoModel>{};
  bool _scanning = true;
  bool _pairing = false;
  String? _error;
  String? _hint;
  Timer? _rescanTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _rescanTimer?.cancel();
    _sub?.cancel();
    _discovery.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _sub = _discovery.devicesStream.listen((list) {
      if (!mounted) return;
      setState(() {
        _pcs
          ..clear()
          ..addEntries(list.map((d) {
            final key = d.deviceId.isNotEmpty ? d.deviceId : d.ip;
            return MapEntry(key, d);
          }));
      });
    });
    await _startScan(preserveCache: false);
    // 移动端 Bonsoir 偶发需二次启动
    _rescanTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted || _pcs.isNotEmpty) return;
      _startScan(preserveCache: true);
    });
  }

  Future<void> _startScan({bool preserveCache = true}) async {
    setState(() {
      _scanning = true;
      _error = null;
      _hint = '正在搜索局域网电脑…';
    });
    try {
      await _discovery.start(preserveCache: preserveCache);
      if (mounted) {
        setState(() {
          for (final d in _discovery.devices) {
            final key = d.deviceId.isNotEmpty ? d.deviceId : d.ip;
            _pcs[key] = d;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '搜索失败：$e');
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 2200), () {
        if (mounted) {
          setState(() {
            _scanning = false;
            if (_pcs.isEmpty && _error == null) {
              _hint = '未发现电脑。请确认电脑已打开 PhotoLink，且与手机同一 Wi‑Fi。';
            }
          });
        }
      });
    }
  }

  Future<void> _connect(DeviceInfoModel pc) async {
    if (_pairing) return;
    setState(() {
      _pairing = true;
      _hint = '正在连接「${pc.deviceName}」…';
      _error = null;
    });
    try {
      final phone = await PcPairClient.pairToPc(
        pc: pc,
        fallbackPhone: widget.phoneInfo,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('配对成功'),
          content: Text(
            '已把本机地址 ${phone.ip}:${phone.port} 发给电脑「${pc.deviceName}」。\n'
            '电脑端将自动连接并打开相册。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好的'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '连接失败：$e\n请确认与电脑同一 Wi‑Fi，且防火墙放行配对端口。';
        _hint = null;
      });
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _pcs.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索电脑'),
        actions: [
          IconButton(
            tooltip: '重新搜索',
            onPressed: _pairing ? null : () => _startScan(preserveCache: false),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: PhotoLinkTheme.brand.withValues(alpha: 0.08),
            child: Row(
              children: [
                PulseOrDot(scanning: _scanning || _pairing),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _pairing
                        ? (_hint ?? '配对中…')
                        : (_hint ??
                            (_scanning
                                ? '扫描中'
                                : '发现 ${list.length} 台电脑')),
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, height: 1.4),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _scanning
                            ? '正在搜索…'
                            : '暂无电脑。也可返回首页使用扫码连接。',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF5A6F6D)),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final pc = list[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                PhotoLinkTheme.brand.withValues(alpha: 0.15),
                            child: const Icon(
                              Icons.computer_rounded,
                              color: PhotoLinkTheme.brand,
                            ),
                          ),
                          title: Text(
                            pc.deviceName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('${pc.ip}:${pc.port}'),
                          trailing: FilledButton(
                            onPressed: _pairing ? null : () => _connect(pc),
                            child: const Text('连接'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 简易扫描指示点（避免依赖 PC 端 PulseDot）
class PulseOrDot extends StatelessWidget {
  const PulseOrDot({super.key, required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scanning ? PhotoLinkTheme.accent : PhotoLinkTheme.brand,
      ),
    );
  }
}
