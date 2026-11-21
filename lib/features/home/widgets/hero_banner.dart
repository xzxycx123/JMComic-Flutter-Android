import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/home_feed.dart';
import '../../../data/models/jm_album_summary.dart';
import 'cover_image.dart';

class _ModuleBadge extends StatelessWidget {
  const _ModuleBadge({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.micro.copyWith(color: scheme.onPrimary),
    );
    return AppBadge(
      label: label,
      color: scheme.primary,
      metalChild: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
        ),
        child: label,
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    final ink = glass ? Theme.of(context).colorScheme.onSurface : Colors.white;
    final reducedMotion = glass && MediaQuery.disableAnimationsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(count, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration:
              reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? ink : ink.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppColors.radiusPill),
          ),
        );
      }),
    );
  }
}

/// 首页轮播：高 180、圆角 20、5s 自动翻页，底部渐变 scrim + 2 行标题。
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    required this.banners,
    super.key,
    this.onTap,
  });

  final List<PromoteBanner> banners;
  final ValueChanged<JmAlbumSummary>? onTap;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  static const Duration _interval = Duration(seconds: 5);

  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _index = 0;
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.banners.length <= 1) return;
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 180,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: _controller,
            itemCount: widget.banners.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final banner = widget.banners[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => widget.onTap?.call(banner.album),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppColors.radiusCover),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        CoverImage(
                          albumId: banner.album.id,
                          radius: 0,
                          fit: BoxFit.cover,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Color(0x00000000),
                                Color(0x00000000),
                                Color(0xCC000000),
                              ],
                              stops: <double>[0, 0.45, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 14,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (banner.moduleTitle.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child:
                                      _ModuleBadge(title: banner.moduleTitle),
                                ),
                              Text(
                                banner.album.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.sectionTitle.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                child: AppSurface(
                  kind: AppSurfaceKind.controlGroup,
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child:
                      _PageDots(count: widget.banners.length, current: _index),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
