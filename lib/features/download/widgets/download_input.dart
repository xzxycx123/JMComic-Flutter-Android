import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/jm_id_parser.dart';

/// 下载输入卡：批量车号输入 + 解析预览 + 三个操作。
class DownloadInput extends StatefulWidget {
  const DownloadInput({
    required this.controller,
    required this.onSubmit,
    super.key,
    this.busy = false,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool busy;

  @override
  State<DownloadInput> createState() => _DownloadInputState();
}

class _DownloadInputState extends State<DownloadInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant DownloadInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = previewJmIds(widget.controller.text);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusPanel),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: widget.controller,
            minLines: 3,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: AppTypography.body.copyWith(color: scheme.onSurface),
            decoration: const InputDecoration(
              hintText: '每行一个车号，支持 350234 / JM350234 / 链接',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  preview.label,
                  style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text;
                  if (text == null || text.isEmpty) return;
                  widget.controller.text = text;
                },
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                child: const Text('粘贴'),
              ),
              TextButton(
                onPressed: () => widget.controller.clear(),
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.busy ? null : widget.onSubmit,
              child: widget.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Text('加入队列'),
            ),
          ),
        ],
      ),
    );
  }
}
