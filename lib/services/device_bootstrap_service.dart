import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/models/device_info.dart';
import 'gallery_service.dart';

/// 权限与本机设备信息组装
class DeviceBootstrapService {
  DeviceBootstrapService._();
  static final DeviceBootstrapService instance = DeviceBootstrapService._();

  String? _deviceId;

  /// 申请相册 + 本地网络相关权限
  Future<String?> ensurePermissions() async {
    final photosOk = await GalleryService.instance.requestPermission();
    if (!photosOk) {
      return '请授予相册完整访问权限（含照片与视频），否则无法提供服务';
    }

    if (Platform.isAndroid) {
      // Android 13+ 图片/视频权限拆分；缺 videos 会导致视频列表为空而照片正常
      await Permission.photos.request();
      await Permission.videos.request();
      // 旧版 Android 仍依赖存储权限
      await Permission.storage.request();
    }

    return null;
  }

  /// 读取本机局域网 IP 并组装设备信息模型
  Future<DeviceInfoModel> buildDeviceInfo() async {
    _deviceId ??= const Uuid().v4();
    final network = NetworkInfo();
    var ip = await network.getWifiIP();
    ip ??= await _fallbackLocalIp();

    final plugin = DeviceInfoPlugin();
    var name = 'PhotoLink Phone';
    var osVersion = '';
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      name = a.model.isNotEmpty ? a.model : 'Android';
      osVersion = 'Android ${a.version.release}';
    } else if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      name = i.name.isNotEmpty ? i.name : 'iPhone';
      osVersion = '${i.systemName} ${i.systemVersion}';
    }

    return DeviceInfoModel(
      deviceId: _deviceId!,
      deviceName: name,
      deviceType: 'phone',
      osVersion: osVersion,
      ip: ip ?? '0.0.0.0',
      port: PhotoLinkConst.port,
    );
  }

  /// WiFi IP 拿不到时，从网卡枚举 IPv4
  Future<String?> _fallbackLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final ni in interfaces) {
        for (final addr in ni.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
