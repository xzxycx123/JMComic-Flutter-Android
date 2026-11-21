import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/core/theme/app_colors.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/ui/glass/app_chip.dart';
import 'package:jm_comic/features/home/widgets/sort_chips.dart';

/// 可交互宿主：把折叠状态放在 State 里，模拟 HomePage 的持有方式。
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SortChips(
          selected: AlbumOrder.weekly,
          collapsed: _collapsed,
          onToggle: () => setState(() => _collapsed = !_collapsed),
          onSelected: (_) {},
        ),
      ),
    );
  }
}

void main() {
  testWidgets('排序条高 34dp，角标图 ≤ 16dp，药丸圆角 999', (tester) async {
    await tester.pumpWidget(const _Host());
    expect(tester.getSize(find.byType(SortChips)).height, SortChips.barHeight);
    expect(SortChips.barHeight, 34);

    final chips = tester.widgetList<AppChip>(find.byType(AppChip)).toList();
    expect(chips, isNotEmpty);
    expect(
      chips.every((chip) => chip.cornerRadius == AppColors.radiusPill),
      isTrue,
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, isNotEmpty, reason: '日榜 / 周榜 / 人气应有榜单角标');
    for (final image in images) {
      expect(image.width, lessThanOrEqualTo(16));
      expect(image.height, lessThanOrEqualTo(16));
    }
    // 单个药丸不撑破整条高度。
    final pill = tester.getSize(find.byType(AppChip).first);
    expect(pill.height, lessThanOrEqualTo(SortChips.barHeight - 8));
  });

  testWidgets('折叠后仍显示当前排序，可重新展开', (tester) async {
    await tester.pumpWidget(const _Host());
    expect(find.text('已收起'), findsNothing);

    // 展开态：全部 5 个排序可见（横向列表懒加载，至少能看到前几个）。
    expect(find.text('最新更新'), findsOneWidget);
    expect(find.text('周榜'), findsOneWidget);

    await tester.tap(find.byKey(SortChips.toggleKey));
    await tester.pump();

    // 折叠态：只剩当前排序（周榜）+ 已收起提示。
    expect(find.byKey(SortChips.collapsedLabelKey), findsOneWidget);
    expect(find.text('周榜'), findsOneWidget);
    expect(find.text('最新更新'), findsNothing);
    expect(find.text('已收起'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      '展开排序',
    );

    await tester.tap(find.byKey(SortChips.toggleKey));
    await tester.pump();
    expect(find.text('最新更新'), findsOneWidget);
    expect(find.text('已收起'), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      '收起排序',
    );
  });

  testWidgets('点击排序药丸回报选中项', (tester) async {
    AlbumOrder? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SortChips(
            selected: AlbumOrder.latestUpdate,
            collapsed: false,
            onSelected: (order) => picked = order,
          ),
        ),
      ),
    );
    await tester.tap(find.text('日榜'));
    await tester.pump();
    expect(picked, AlbumOrder.daily);
  });
}
