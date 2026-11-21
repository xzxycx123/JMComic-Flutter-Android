import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../core/utils/jm_id_parser.dart';

/// 下载输入卡：批量车号输入 + 解析预览 + 三个操作。
///
/// 输入区属于「滚动内容 / 输入框」，按玻璃使用规则走 solid 实色表面：
/// 卡片本体是普通 Container，内部通过 [InheritedGlassSurfaceStyle] 把输入框和
/// 主按钮也压成实色，避免折射层嵌套。
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
      child: InheritedGlassSurfaceStyle(
        surfaceStyle: GlassSurfaceStyle.solid,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppTextField(
              controller: widget.controller,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: AppTypography.body.copyWith(color: scheme.onSurface),
              decoration: InputDecoration(
                hintText: '每行一个车号，支持 350234 / JM350234 / 链接',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: context.isLiquidGlass
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                    : EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    preview.label,
                    style: AppTypography.micro
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                AppButton.text(
                  cornerRadius: AppColors.radiusPill,
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    final text = data?.text;
                    if (!mounted || text == null || text.isEmpty) return;
                    widget.controller.text = text;
                  },
                  style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                  child: const Text('粘贴'),
                ),
                AppButton.text(
                  cornerRadius: AppColors.radiusPill,
                  onPressed: () => widget.controller.clear(),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                cornerRadius: AppColors.radiusPill,
                solid: true,
                onPressed: widget.busy ? null : widget.onSubmit,
                semanticLabel: widget.busy ? '加入队列' : null,
                child: widget.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: AppProgressIndicator.circular(
                          size: 18,
                          strokeWidth: 2.2,
                        ),
                      )
                    : const Text('加入队列'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
