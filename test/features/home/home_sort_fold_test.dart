import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/home/home_page.dart';
import 'package:jm_comic/features/home/widgets/sort_chips.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_env.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget _app() => ProviderScope(
      overrides: <Override>[
        jmApiProvider.overrideWithValue(FakeJmApi()),
        jmBootstrapProvider.overrideWith((ref) async => FakeJmApi()),
        homeRepositoryProvider.overrideWith(
          (ref) async => HomeRepository(api: FakeJmApi()),
        ),
      ],
      child: const MaterialApp(home: HomePage()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  testWidgets('首页排序条可折叠 / 展开，折叠后仍显示当前排序', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await _pumpFrames(tester);

    await tester.scrollUntilVisible(
      find.byType(SortChips),
      240,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();

    expect(tester.getSize(find.byType(SortChips)).height, 34);
    expect(find.byKey(SortChips.toggleKey), findsOneWidget);

    await tester.tap(find.byKey(SortChips.toggleKey));
    await tester.pump();

    expect(find.byKey(SortChips.collapsedLabelKey), findsOneWidget);
    expect(find.text('已收起'), findsOneWidget);
    // 折叠后当前排序仍可见（默认 = 最新更新）。
    expect(find.text('最新更新'), findsOneWidget);

    await tester.tap(find.byKey(SortChips.toggleKey));
    await tester.pump();
    expect(find.text('已收起'), findsNothing);
    expect(find.text('日榜'), findsOneWidget);
  });
}
