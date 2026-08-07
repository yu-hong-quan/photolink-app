import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'gallery_service.dart';

/// PC 发起删除时，在 App 前台弹出确认桥接。
/// HTTP 请求会阻塞到用户确认/取消（或超时）。
class DeleteConfirmBridge {
  DeleteConfirmBridge._();
  static final DeleteConfirmBridge instance = DeleteConfirmBridge._();

  /// 由 MaterialApp 注入，用于在任意 isolate 回调里弹窗
  GlobalKey<NavigatorState>? navigatorKey;

  Completer<bool>? _busy;

  /// 请求用户确认删除；返回 true 才允许继续软删
  Future<bool> requestConfirm(List<String> photoIds) async {
    if (photoIds.isEmpty) return false;
    // 已有确认中：拒绝并发删除，避免叠多个弹窗
    if (_busy != null) return false;

    final nav = navigatorKey?.currentState;
    final ctx = nav?.overlay?.context ?? navigatorKey?.currentContext;
    if (ctx == null || !ctx.mounted) return false;

    final completer = Completer<bool>();
    _busy = completer;

    // 超时自动拒绝，避免 PC 请求一直挂起
    Timer(const Duration(minutes: 2), () {
      if (!completer.isCompleted) completer.complete(false);
    });

    try {
      // 等下一帧，确保 overlay 可用
      await Future<void>.delayed(Duration.zero);
      final overlayCtx = navigatorKey?.currentState?.overlay?.context ?? ctx;
      if (!overlayCtx.mounted) {
        if (!completer.isCompleted) completer.complete(false);
      } else {
        final ok = await showDialog<bool>(
          context: overlayCtx,
          barrierDismissible: false,
          builder: (_) => _DeleteConfirmDialog(photoIds: photoIds),
        );
        if (!completer.isCompleted) {
          completer.complete(ok == true);
        }
      }
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }

    final result = await completer.future;
    _busy = null;
    return result;
  }
}

/// 第一步：浏览全部待删图片；第二步：再次确认
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.photoIds});

  final List<String> photoIds;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _thumbs = <String, Uint8List?>{};
  int _previewIndex = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbs();
  }

  Future<void> _loadThumbs() async {
    for (final id in widget.photoIds) {
      try {
        final bytes = await GalleryService.instance.getThumbnail(id);
        if (mounted) setState(() => _thumbs[id] = bytes);
      } catch (_) {
        if (mounted) setState(() => _thumbs[id] = null);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onConfirmTap() async {
    // 第二步：再确认一次，防止误触
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再次确认删除'),
        content: Text(
          '确认将 ${widget.photoIds.length} 张图片移入回收站？\n'
          '可在回收站撤回；彻底删除需另行操作。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (again == true) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.photoIds;
    final currentId = ids[_previewIndex.clamp(0, ids.length - 1)];
    final previewBytes = _thumbs[currentId];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Column(
          children: [
            AppBar(
              title: Text('确认删除（${ids.length} 张）'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '请滑动/点选查看全部图片，确认无误后再删除',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(12),
                color: Colors.black12,
                child: _loading && previewBytes == null
                    ? const Center(child: CircularProgressIndicator())
                    : previewBytes == null
                        ? const Center(child: Icon(Icons.broken_image_outlined))
                        : InteractiveViewer(
                            child: Image.memory(previewBytes, fit: BoxFit.contain),
                          ),
              ),
            ),
            // 全部缩略图列表，便于逐张核对
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: ids.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final id = ids[index];
                  final bytes = _thumbs[id];
                  final selected = index == _previewIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _previewIndex = index),
                    child: Container(
                      width: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: bytes == null
                          ? const ColoredBox(
                              color: Colors.black12,
                              child: Icon(Icons.image_outlined, size: 20),
                            )
                          : Image.memory(bytes, fit: BoxFit.cover),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Text('${_previewIndex + 1} / ${ids.length}'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('拒绝'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _onConfirmTap,
                    child: const Text('确认删除'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
