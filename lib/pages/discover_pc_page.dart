import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/device_info.dart';
import '../services/mdns_pc_discovery_service.dart';
import '../services/pc_pair_client.dart';
import '../theme/app_theme.dart';

/// App 主动搜索局域网电脑并选择连接（配对）
class DiscoverPcPage extends StatefulWidget {
  const DiscoverPcPage({
    super.key,
    required this.phoneInfo,
    this.connectedPcIp,
  });

  final DeviceInfoModel phoneInfo;

  /// 当前已与本机相册通信的电脑 IP（来自 HTTPS 远端地址）；为空表示尚未连接
  final String? connectedPcIp;

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

  String? get _connectedIp {
    final ip = widget.connectedPcIp?.trim();
    if (ip == null || ip.isEmpty) return null;
    return ip;
  }

  bool _isConnected(DeviceInfoModel pc) {
    final connected = _connectedIp;
    if (connected == null) return false;
    return pc.ip == connected;
  }

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

  /// 已连接置顶；同组内按名称排序
  List<DeviceInfoModel> get _sortedList {
    final list = _pcs.values.toList();
    list.sort((a, b) {
      final ac = _isConnected(a);
      final bc = _isConnected(b);
      if (ac != bc) return ac ? -1 : 1;
      return a.deviceName.compareTo(b.deviceName);
    });
    return list;
  }

  /// 若已连接 IP 未出现在 mDNS 结果中，补一条占位，避免「当前连接」看不见
  List<DeviceInfoModel> get _displayList {
    final list = _sortedList;
    final connected = _connectedIp;
    if (connected == null) return list;
    final exists = list.any((e) => e.ip == connected);
    if (exists) return list;
    return [
      DeviceInfoModel(
        deviceId: 'connected::$connected',
        deviceName: '当前已连接电脑',
        deviceType: 'pc',
        osVersion: '',
        ip: connected,
        // 占位仅展示；端口未知时用 0，不提供「连接」动作依赖真实 mDNS 项
        port: 0,
      ),
      ...list,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = _displayList;
    final connectedCount = list.where(_isConnected).length;
    final otherCount = list.length - connectedCount;

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
                                : '已连接 $connectedCount · 可连接 $otherCount')),
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    children: [
                      if (connectedCount > 0) ...[
                        const _SectionLabel(
                          title: '当前连接',
                          subtitle: '已与本机相册通信的电脑',
                        ),
                        ...list.where(_isConnected).map(_buildPcCard),
                        const SizedBox(height: 12),
                      ],
                      if (otherCount > 0) ...[
                        _SectionLabel(
                          title: '可连接',
                          subtitle: connectedCount > 0
                              ? '局域网内其他 PhotoLink 电脑'
                              : '点选后即可配对',
                        ),
                        ...list.where((e) => !_isConnected(e)).map(_buildPcCard),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPcCard(DeviceInfoModel pc) {
    final connected = _isConnected(pc);
    // mDNS 未解析到、仅靠 IP 占位的项不能发起配对
    final canPair = !connected && pc.port > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: connected
                ? const Color(0xFF1FA87A).withValues(alpha: 0.18)
                : PhotoLinkTheme.brand.withValues(alpha: 0.15),
            child: Icon(
              connected
                  ? Icons.link_rounded
                  : Icons.computer_rounded,
              color: connected
                  ? const Color(0xFF1FA87A)
                  : PhotoLinkTheme.brand,
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  pc.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (connected) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1FA87A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '已连接',
                    style: TextStyle(
                      color: Color(0xFF1FA87A),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            pc.port > 0 ? '${pc.ip}:${pc.port}' : pc.ip,
          ),
          trailing: connected
              ? TextButton(
                  onPressed: _pairing || pc.port <= 0
                      ? null
                      : () => _connect(pc),
                  child: const Text('重新连接'),
                )
              : FilledButton(
                  onPressed: (_pairing || !canPair) ? null : () => _connect(pc),
                  child: const Text('连接'),
                ),
        ),
      ),
    );
  }
}

/// 列表分组标题
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF163A38),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF5A6F6D),
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
