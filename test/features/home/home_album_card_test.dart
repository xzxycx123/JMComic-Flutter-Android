import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/icons/app_icons.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/ui/glass/app_chip.dart';
import 'package:jm_comic/core/ui/glass/app_surface.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/features/home/widgets/album_card.dart';
import 'package:jm_comic/features/home/widgets/cover_image.dart';

import '../../helpers/fixtures.dart';

/// 卡片里的 CoverImage 需要 bootstrap + api；用永不完成的 bootstrap 停在占位图，
/// 避免 widget 测试打真实网络。
Widget _host(Widget child) => ProviderScope(
      overrides: <Override>[
        jmApiProvider.overrideWithValue(FakeJmApi()),
        jmBootstrapProvider
            .overrideWith((ref) => Completer<FakeJmApi>().future),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 160, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('卡片显示本地标签 + 喜欢数', (tester) async {
    const album = JmAlbumSummary(
      id: '350234',
      title: '測試本子',
      author: '測試作者',
      tags: <String>['同人', '漢化'],
      categoryTitle: '單本',
      likes: 4321,
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    expect(find.text('同人'), findsOneWidget);
    expect(find.text('漢化'), findsOneWidget);
    // tags 已占用 2 个名额，一级分类不再重复出现。
    expect(find.text('單本'), findsNothing);

    expect(find.text('4321'), findsOneWidget);
    final hearts = tester.widgetList<SvgIcon>(find.byType(SvgIcon)).toList();
    expect(
      hearts.any((icon) => icon.asset == AppIcons.heart),
      isTrue,
      reason: '未点赞卡片用心形描边图标',
    );
  });

  testWidgets('无计数时统一显示 --，不显示 N/A / 超长标签', (tester) async {
    const album = JmAlbumSummary(
      id: '1',
      title: '无标签条目',
      tags: <String>['N/A', '這是一個非常長的標籤文字'],
      categoryTitle: '',
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    expect(find.text('N/A'), findsNothing);
    expect(find.text('這是一個非常長的標籤文字'), findsNothing);
    expect(find.text(JmAlbumSummary.noLikeCount), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('已点赞用实心爱心；分类兜底成唯一标签', (tester) async {
    const album = JmAlbumSummary(
      id: '2',
      title: '已赞条目',
      categoryTitle: '同人',
      liked: true,
      likes: 12000,
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    expect(find.text('同人'), findsOneWidget);
    expect(find.text('1.2万'), findsOneWidget);
    final hearts = tester.widgetList<SvgIcon>(find.byType(SvgIcon)).toList();
    expect(hearts.any((icon) => icon.asset == AppIcons.heartFilled), isTrue);
  });

  testWidgets('卡片不再使用玻璃表面（solid 可读）', (tester) async {
    const album = JmAlbumSummary(id: '3', title: '无玻璃', likes: 1);
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();
    expect(find.byType(AppSurface), findsNothing);
  });

  testWidgets('标签渲染在卡片正文（标题下方），和搜索页一致', (tester) async {
    const album = JmAlbumSummary(
      id: '350234',
      title: '測試本子',
      author: '測試作者',
      tags: <String>['同人'],
      likes: 12,
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    // 标签是正文里的 chip（AppChip），不是封面上的角标。
    final tagChip = find.ancestor(
      of: find.text('同人'),
      matching: find.byType(AppChip),
    );
    expect(tagChip, findsOneWidget);
    final cover = tester.getRect(find.byType(CoverImage));
    final tag = tester.getRect(find.text('同人'));
    expect(tag.top, greaterThanOrEqualTo(cover.bottom));
    // 标题在标签上方。
    expect(
      tester.getRect(find.text('測試本子')).bottom,
      lessThanOrEqualTo(tag.top),
    );
  });

  testWidgets('调用方自带 caption 时不重复渲染标签', (tester) async {
    const album = JmAlbumSummary(
      id: '4',
      title: '搜索结果',
      author: '測試作者',
      tags: <String>['服务端标签'],
      likes: 9,
    );
    await tester.pumpWidget(
      _host(
        const AlbumCard(
          album: album,
          caption: Text('服务端标签', key: ValueKey<String>('caption-tag')),
        ),
      ),
    );
    await tester.pump();

    // 标签只出现在调用方的 caption 里，封面上不重复；喜欢数照常显示。
    expect(find.text('服务端标签'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('caption-tag')), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
  });
}
