import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/icons/app_icons.dart';
import 'package:jm_comic/core/icons/app_images.dart';

/// 素材守卫：pubspec 声明的位图 / SVG 必须真的能 load 出来，避免运行时才发现丢文件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const images = <String>[
    AppImages.appIcon,
    AppImages.brandBanner,
    AppImages.loadingCat,
    AppImages.loadingCatLarge,
    AppImages.loadingCatFrame,
    AppImages.qrApp,
    AppImages.rocket,
    AppImages.badgeNew,
    AppImages.badgeHot,
    AppImages.badgeDay,
    AppImages.badgeWeek,
    'assets/images/mark_default.png',
    'assets/images/mark_newyear.png',
    'assets/images/mark_halloween.png',
    'assets/images/mark_xmas.png',
    'assets/images/mark_sakura.png',
    'assets/images/mark_pink.png',
  ];

  const icons = <String>[
    AppIcons.home,
    AppIcons.user,
    AppIcons.download,
    AppIcons.search,
    AppIcons.back,
    AppIcons.forward,
    AppIcons.close,
    AppIcons.theme,
    AppIcons.bookmark,
    AppIcons.play,
    AppIcons.bookOpen,
    AppIcons.grid,
    AppIcons.list,
    AppIcons.refresh,
    AppIcons.pause,
    AppIcons.trash,
    AppIcons.folder,
    AppIcons.share,
    AppIcons.settings,
    AppIcons.check,
    AppIcons.alert,
    AppIcons.scrollMode,
    AppIcons.pageMode,
  ];

  test('位图素材全部可加载', () async {
    for (final asset in images) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }
  });

  test('SVG 图标全部可加载', () async {
    for (final asset in icons) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }
  });

  test('季节吉祥物回落与切换', () {
    expect(AppImages.seasonalMark(DateTime(2026, 12, 1)), contains('xmas'));
    expect(AppImages.seasonalMark(DateTime(2026, 10, 1)), contains('halloween'));
    expect(AppImages.seasonalMark(DateTime(2026, 1, 1)), contains('newyear'));
    expect(AppImages.seasonalMark(DateTime(2026, 3, 1)), contains('sakura'));
    expect(AppImages.seasonalMark(DateTime(2026, 6, 1)), contains('mark_default'));
  });
}
