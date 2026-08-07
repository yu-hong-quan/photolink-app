import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';

/// App 端 mDNS 发现：只收集局域网内的电脑（deviceType=pc）
class MdnsPcDiscoveryService {
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _eventSub;
  final _devices = <String, DeviceInfoModel>{};
  final _controller = StreamController<List<DeviceInfoModel>>.broadcast();
  bool _starting = false;
  bool _restartQueued = false;

  Stream<List<DeviceInfoModel>> get devicesStream => _controller.stream;
  List<DeviceInfoModel> get devices => _devices.values.toList();

  /// [preserveCache]：重启时保留已发现电脑，避免列表闪空
  Future<void> start({bool preserveCache = false}) async {
    if (_starting) {
      _restartQueued = true;
      return;
    }
    _starting = true;
    try {
      await stop();
      if (!preserveCache) {
        _devices.clear();
        _emit();
      }

      _discovery = BonsoirDiscovery(type: PhotoLinkConst.mdnsType);
      await _discovery!.ready;

      final stream = _discovery!.eventStream;
      if (stream == null) {
        debugPrint('App mDNS eventStream 为空，跳过本轮');
        return;
      }
      // 必须在 start 前挂监听，否则早期事件会丢
      _eventSub = stream.listen(_onEvent);
      await _discovery!.start();
      debugPrint('App 已开始搜索电脑: ${PhotoLinkConst.mdnsType}');
    } finally {
      _starting = false;
      if (_restartQueued) {
        _restartQueued = false;
        unawaited(start(preserveCache: true));
      }
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    final service = event.service;
    if (service == null) return;

    if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
      service.resolve(_discovery!.serviceResolver);
    } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
      if (service is! ResolvedBonsoirService) return;
      final host = service.host;
      if (host == null || host.isEmpty) return;
      final attrs = service.attributes;
      final info = DeviceInfoModel(
        deviceId: attrs['deviceId'] ?? service.name,
        deviceName: service.name,
        deviceType: attrs['deviceType'] ?? 'phone',
        osVersion: attrs['osVersion'] ?? '',
        ip: (attrs['ip']?.isNotEmpty == true) ? attrs['ip']! : host,
        port: service.port,
      );
      // 只保留电脑；过滤本机手机广播
      if (info.deviceType != 'pc') return;
      final key = info.deviceId.isNotEmpty ? info.deviceId : info.ip;
      _devices[key] = info;
      _emit();
      debugPrint('发现电脑: ${info.deviceName} ${info.ip}:${info.port}');
    } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
      final key = service.attributes['deviceId'] ?? service.name;
      _devices.remove(key);
      _devices.removeWhere((k, v) => v.deviceName == service.name);
      _emit();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List<DeviceInfoModel>.from(devices));
    }
  }

  Future<void> stop() async {
    try {
      await _eventSub?.cancel();
    } catch (_) {}
    _eventSub = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
  }

  Future<void> dispose() async {
    _restartQueued = false;
    await stop();
    await _controller.close();
  }
}
