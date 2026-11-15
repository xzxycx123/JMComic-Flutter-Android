import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 关于页：版本、开源许可、排障指引。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text('关于'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: <Widget>[
          const BrandBanner(height: 96),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              const BrandMark(size: 56, radius: AppColors.radiusCard, asset: AppImages.appIcon),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    AppConfig.appName,
                    style: AppTypography.title.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${AppConfig.appVersion} · Android · GPL-3.0',
                    style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '首页内容来自 JM 移动端接口（/promote、/latest、/categories、/categories/filter），'
            '作者：xzxycx'
            '使用Dart开发',
            style: AppTypography.body.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          _LinkTile(
            icon: AppIcons.check,
            title: '开源许可（GPL-3.0）',
            onTap: () => _showMitLicense(context),
          ),
          _LinkTile(
            icon: AppIcons.bookOpen,
            title: '第三方开源许可',
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: AppConfig.appVersion,
            ),
          ),
          _LinkTile(
            icon: AppIcons.alert,
            title: '故障排查',
            onTap: () => _showTroubleshoot(context),
          ),
          const SizedBox(height: 24),
          _QrCard(scheme: scheme),
          const SizedBox(height: 20),
          Text(
            '协议事实以 tools\\probe_api.ps1 的实时输出为准（docs/PROBE_RESULT_2026-11-14.txt 为留档）。',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Text(
            '${AppConfig.copyright} · GNU GPL v3.0',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showMitLicense(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GNU GPL v3.0'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: FutureBuilder<String>(
            future: rootBundle.loadString(AppConfig.licenseAsset),
            builder: (context, snapshot) {
              if (snapshot.hasError || !snapshot.hasData) {
                return const SingleChildScrollView(
                  child: Text('${AppConfig.licenseSummary}\n\n（完整文本见仓库根 LICENSE）'),
                );
              }
              return SingleChildScrollView(
                child: Text(
                  '${AppConfig.licenseSummary}\n\n${snapshot.data}',
                  style: const TextStyle(fontSize: 12, height: 1.45),
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showTroubleshoot(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('排障指引'),
        content: const SingleChildScrollView(
          child: Text(
            '1. shell 里跑 pwsh -File tools\\probe_api.ps1，全绿说明线路与协议正常。\n'
            '2. 全线路 TLS 握手失败：多为代理节点问题，换节点或用手机热点。\n'
            '3. 接口返回非 JSON：多为被重定向到引导页，等 /setting 重新下发 cookie。\n'
            '4. 图床 403：确认请求头带 User-Agent / Referer / X-Requested-With。',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 官方 APP 二维码卡片（`img/ui/qr_app.png` 派生到 assets/images/qr_app.png）。
class _QrCard extends StatelessWidget {
  const _QrCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusPanel),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              AppImages.qrApp,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              semanticLabel: '官方 APP 二维码',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '官方 APP 二维码',
                  style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 4)
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.onTap});

  final String icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: SvgIcon(icon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.body.copyWith(color: scheme.onSurface),
                  ),
                ),
                IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: const SvgIcon(AppIcons.forward, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
