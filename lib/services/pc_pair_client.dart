import 'dart:async';
import 'dart:convert';

import '../core/models/device_info.dart';
import 'device_bootstrap_service.dart';
import 'insecure_http.dart';

/// App → PC 配对：向电脑配对口 POST 本机相册地址
class PcPairClient {
  PcPairClient._();

  /// 向指定电脑发起配对；成功返回更新后的手机信息
  static Future<DeviceInfoModel> pairToPc({
    required DeviceInfoModel pc,
    required DeviceInfoModel fallbackPhone,
  }) async {
    final latest = await DeviceBootstrapService.instance.buildDeviceInfo();
    final phone = DeviceInfoModel(
      deviceId: latest.deviceId.isNotEmpty
          ? latest.deviceId
          : fallbackPhone.deviceId,
      deviceName: latest.deviceName,
      deviceType: 'phone',
      osVersion: latest.osVersion,
      ip: latest.ip,
      port: latest.port,
    );

    final uri = Uri.parse('https://${pc.ip}:${pc.port}/api/pair');
    final res = await postJsonInsecure(uri, jsonEncode(phone.toJson()));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return phone;
  }
}
