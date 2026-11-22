import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/icons/app_icons.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_chip.dart';
import 'package:jm_comic/core/ui/glass/app_surface.dart';
import 'package:jm_comic/data/local/settings_store.dart';
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
  testWidgets('分类打封面左上角，作品标签在作者名下面', (tester) async {
    const album = JmAlbumSummary(
      id: '350234',
      title: '測試本子',
      author: '測試作者',
      tags: <String>['伪娘', '扶她', '中文'],
      categoryTitle: '單本',
      likes: 4321,
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    final cover = tester.getRect(find.byType(CoverImage));

    // 分类角标：封面内、贴左上角。
    final category = tester.getRect(find.text('單本'));
    expect(category.top - cover.top, lessThan(24));
    expect(category.left - cover.left, lessThan(24));

    // 标签：作者名下方，正文里（封面之外）。
    final author = tester.getRect(find.text('測試作者'));
    final tag = tester.getRect(find.text('伪娘'));
    expect(tag.top, greaterThan(author.bottom));
    expect(find.text('扶她'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('伪娘'), matching: find.byType(AppChip)),
      findsOneWidget,
      reason: '标签是正文里的药丸',
    );

    // 语言类标签不占名额。
    expect(find.text('中文'), findsNothing);

    expect(find.text('4321'), findsOneWidget);
  });

  testWidgets('标签药丸不截断文字（无省略号）', (tester) async {
    const album = JmAlbumSummary(
      id: '9',
      title: '長標籤',
      author: '作者',
      tags: <String>['AI繪圖', '女性向'],
      categoryTitle: '短篇',
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    for (final label in <String>['AI繪圖', '女性向']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, isNull);
      expect(text.softWrap, isNot(false));
    }
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

  testWidgets('已点赞用实心爱心；没有分类就不画角标', (tester) async {
    const album = JmAlbumSummary(
      id: '2',
      title: '已赞条目',
      liked: true,
      likes: 12000,
    );
    await tester.pumpWidget(_host(const AlbumCard(album: album)));
    await tester.pump();

    expect(find.text('同人'), findsNothing);
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

  testWidgets('调用方自带 caption 时：分类角标保留，标签不重复', (tester) async {
    const album = JmAlbumSummary(
      id: '4',
      title: '搜索结果',
      author: '測試作者',
      tags: <String>['服务端标签'],
      categoryTitle: '同人',
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

    // 调用方 caption 自己画标签，卡片不再重复画；分类角标与喜欢数照常。
    expect(find.byKey(const ValueKey<String>('caption-tag')), findsOneWidget);
    expect(find.text('服务端标签'), findsOneWidget);
    expect(find.text('同人'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
  });

  testWidgets('LiquidGlass 下标题不再垫圆角矩形底衬', (tester) async {
    const album = JmAlbumSummary(
      id: '5',
      title: '玻璃标题',
      author: '測試作者',
      tags: <String>['同人'],
      likes: 3,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider
              .overrideWith((ref) => Completer<FakeJmApi>().future),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => InterfaceStyleScope(
            style: AppInterfaceStyle.liquidGlass,
            child: child!,
          ),
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 160, child: AlbumCard(album: album)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 标题区不再包一层 Stack/底衬：标题不是任何 Stack 的后代，只剩封面自己
    // 的 Stack（封面 + 分类角标 + 喜欢数 + 新上架角标）。
    expect(
      find.ancestor(
        of: find.text('玻璃标题'),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
    final title = tester.getRect(find.text('玻璃标题'));
    final cover = tester.getRect(find.byType(CoverImage));
    expect(title.top, greaterThanOrEqualTo(cover.bottom));
  });
}
