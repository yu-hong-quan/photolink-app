import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/models/device_info.dart';
import '../services/pc_pair_client.dart';

/// App 扫描 PC 屏幕上的配对二维码，并把本机相册服务地址回传给 PC
class ScanPcQrPage extends StatefulWidget {
  const ScanPcQrPage({super.key, required this.phoneInfo});

  final DeviceInfoModel phoneInfo;

  @override
  State<ScanPcQrPage> createState() => _ScanPcQrPageState();
}

class _ScanPcQrPageState extends State<ScanPcQrPage> {
  MobileScannerController? _controller;
  bool _handling = false;
  bool _cameraReady = false;
  bool _requesting = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  /// 先拿权限，再创建/启动扫码器，避免首次进入直接 denied
  Future<void> _prepareCamera() async {
    setState(() {
      _requesting = true;
      _message = null;
    });

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (status.isGranted) {
      // 等权限对话框完全关闭后再启相机，避免首次启动 race → denied
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      _controller = MobileScannerController(
        autoStart: true,
        facing: CameraFacing.back,
      );
      setState(() {
        _cameraReady = true;
        _requesting = false;
        _message = null;
      });
      return;
    }

    setState(() {
      _cameraReady = false;
      _requesting = false;
      _message = status.isPermanentlyDenied
          ? '相机权限被永久拒绝，请到系统设置中开启'
          : '需要摄像头权限才能扫描电脑二维码';
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling || _controller == null) return;
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
    await _controller!.stop();

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
        _handling = false;
        _message = '配对失败：$e\n请确认与电脑同一 WiFi，且防火墙放行配对端口。';
      });
      await _controller!.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描电脑二维码')),
      body: Column(
        children: [
          Expanded(child: _buildScannerArea()),
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
                if (!_cameraReady && !_requesting) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _prepareCamera,
                    child: const Text('重新申请权限'),
                  ),
                  TextButton(
                    onPressed: openAppSettings,
                    child: const Text('打开系统设置'),
                  ),
                ],
                if (_handling || _requesting) ...[
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

  Widget _buildScannerArea() {
    if (_requesting) {
      return const Center(child: Text('正在申请相机权限…'));
    }
    if (!_cameraReady || _controller == null) {
      return const Center(
        child: Icon(Icons.no_photography_outlined, size: 64, color: Colors.grey),
      );
    }
    return MobileScanner(
      controller: _controller!,
      onDetect: _onDetect,
    );
  }
}
