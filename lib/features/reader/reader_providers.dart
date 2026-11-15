import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/local/settings_store.dart';
import '../../data/models/jm_chapter.dart';
import 'reader_mode.dart';

/// 阅读器首屏数据（章节图片清单 + 切片阈值 + 初始页码 + 默认模式）。
class ReaderData {
  const ReaderData({
    required this.args,
    required this.chapter,
    required this.scrambleId,
    required this.initialPage,
    required this.mode,
  });

  final ReaderArgs args;
  final JmChapter chapter;
  final int scrambleId;
  final int initialPage;
  final ReaderMode mode;

  String get title => args.title.isNotEmpty ? args.title : chapter.title;

  int get total => chapter.images.length;
}

final AsyncNotifierProviderFamily<ReaderController, ReaderData, ReaderArgs>
    readerDataProvider =
    AsyncNotifierProvider.family<ReaderController, ReaderData, ReaderArgs>(
        ReaderController.new,);

class ReaderController extends FamilyAsyncNotifier<ReaderData, ReaderArgs> {
  @override
  Future<ReaderData> build(ReaderArgs arg) async {
    final repository = await ref.watch(albumRepositoryProvider.future);
    final chapter = await repository.chapter(
      JmChapterRef(id: arg.chapterId, title: arg.title),
    );
    final scrambleId = await repository.scrambleId(arg.chapterId);
    final settings = ref.read(settingsProvider);
    final progress = repository.readProgress(arg.albumId, arg.chapterId);
    final initial = arg.page > 1 ? arg.page : (progress?.page ?? 1);
    return ReaderData(
      args: arg,
      chapter: chapter,
      scrambleId: scrambleId,
      initialPage: initial
          .clamp(1, chapter.images.isEmpty ? 1 : chapter.images.length)
          .toInt(),
      mode: ReaderMode.fromCode(settings.defaultReaderMode),
    );
  }

  /// 记住默认阅读模式（切换后下次沿用）。
  Future<void> rememberMode(ReaderMode mode) async {
    await ref.read(settingsProvider.notifier).setDefaultReaderMode(mode.code);
  }
}
