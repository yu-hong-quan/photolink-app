import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/models/device_info.dart';
import '../services/device_bootstrap_service.dart';
import '../services/insecure_http.dart';

/// App 扫描 PC 屏幕上的配对二维码，并把本机相册服务地址回传给 PC
class ScanPcQrPage extends StatefulWidget {
  const ScanPcQrPage({super.key, required this.phoneInfo});

  final DeviceInfoModel phoneInfo;

  @override
  State<ScanPcQrPage> createState() => _ScanPcQrPageState();
}

class _ScanPcQrPageState extends State<ScanPcQrPage> {
  final _controller = MobileScannerController();
  bool _handling = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _ensureCamera();
  }

  Future<void> _ensureCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted && mounted) {
      setState(() => _message = '需要摄像头权限才能扫描电脑二维码');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final barcodes = capture.barcodes;
    String? raw;
    for (final b in barcodes) {
      if (b.rawValue != null && b.rawValue!.isNotEmpty) {
        raw = b.rawValue;
        break;
      }
    }
    if (raw == null || raw.isEmpty) return;

    final pc = DeviceInfoModel.fromPcPairPayload(raw);
    if (pc == null) {
      setState(() => _message = '不是 PhotoLink 电脑配对码，请扫描 PC 端二维码');
      return;
    }

    setState(() {
      _handling = true;
      _message = '正在向电脑 ${pc.deviceName}（${pc.ip}）发送本机地址…';
    });
    await _controller.stop();

    try {
      // 确保回传的是最新局域网 IP
      final latest = await DeviceBootstrapService.instance.buildDeviceInfo();
      final phone = DeviceInfoModel(
        deviceId: latest.deviceId.isNotEmpty
            ? latest.deviceId
            : widget.phoneInfo.deviceId,
        deviceName: latest.deviceName,
        deviceType: 'phone',
        osVersion: latest.osVersion,
        ip: latest.ip,
        port: latest.port,
      );

      final uri = Uri.parse('https://${pc.ip}:${pc.port}/api/pair');
      final res = await postJsonInsecure(uri, jsonEncode(phone.toJson()));
      if (!mounted) return;
      if (res.statusCode == 200) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('配对成功'),
            content: Text(
              '已把本机地址 ${phone.ip}:${phone.port} 发给电脑「${pc.deviceName}」。\n'
              '请在电脑端点击连接即可浏览相册。',
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
      } else {
        setState(() {
          _handling = false;
          _message = '配对失败 HTTP ${res.statusCode}: ${res.body}';
        });
        await _controller.start();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _handling = false;
        _message = '配对失败：$e\n请确认与电脑同一 WiFi，且防火墙放行配对端口。';
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描电脑二维码')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  '请对准电脑 PhotoLink 窗口中的配对二维码',
                  textAlign: TextAlign.center,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _handling ? Colors.blueGrey : Colors.red.shade700,
                    ),
                  ),
                ],
                if (_handling) ...[
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
