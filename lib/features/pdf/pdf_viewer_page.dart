import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/utils/logger.dart';
import '../../data/local/progress_store.dart';
import '../../data/local/settings_store.dart';
import '../../data/sources/pdf_reader_channel.dart';
import '../reader/reader_mode.dart';
import '../reader/reader_page.dart';

/// 内置 PDF 阅读器入参（`/pdf?uri=...&title=...`）。
class PdfViewerArgs {
  const PdfViewerArgs({required this.uri, this.title = ''});

  final String uri;
  final String title;

  factory PdfViewerArgs.fromQuery(Map<String, String> query) => PdfViewerArgs(
        uri: query['uri'] ?? '',
        title: query['title'] ?? '',
      );

  Map<String, String> toQuery() => <String, String>{
        'uri': uri,
        if (title.isNotEmpty) 'title': title,
      };

  String get route => '/pdf?${Uri(queryParameters: toQuery()).query}';

  String get displayTitle => title.trim().isEmpty ? 'PDF' : title.trim();
}

/// 将本地 PDF 渲染为阅读器使用的单页 PNG。
class PdfViewerPage extends ConsumerStatefulWidget {
  const PdfViewerPage({required this.args, super.key});

  final PdfViewerArgs args;

  @override
  ConsumerState<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends ConsumerState<PdfViewerPage> {
  late final PdfReader _reader;
  late final ProgressStore _progress;

  PdfDocumentInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reader = ref.read(pdfReaderProvider);
    _progress = ref.read(progressStoreProvider);
    unawaited(_open());
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final info = await _reader.open(widget.args.uri);
      if (!mounted) return;
      setState(() {
        if (info.isEmpty) {
          _error = '这个 PDF 没有可显示的页面';
        } else {
          _info = info;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _close() async {
    try {
      await _reader.close();
    } catch (error) {
      Log.w('关闭 PDF 失败：$error');
    }
  }

  Future<void> _saveProgress(int page) async {
    try {
      await _progress.writePdfPage(widget.args.uri, page);
    } catch (error) {
      Log.w('保存 PDF 阅读进度失败：$error');
    }
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/history');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return ReaderPageFrame(
        child: ReaderPageError(
          message: error,
          onRetry: () => unawaited(_open()),
          onExit: _exit,
          onOpenExternally: () async {
            await ref.read(downloadRepositoryProvider).openFile(
                  uri: widget.args.uri,
                  name: widget.args.title,
                );
          },
        ),
      );
    }
    final info = _info;
    if (info == null) {
      return const ReaderPageFrame(child: ReaderPageLoading());
    }

    final media = MediaQuery.of(context);
    final renderWidth =
        (media.size.width * media.devicePixelRatio).round().clamp(720, 1600);
    final uri = widget.args.uri;
    final mode =
        ReaderMode.fromCode(ref.read(settingsProvider).defaultReaderMode);
    return ReaderPageFrame(
      child: ReaderView(
        title: widget.args.displayTitle,
        total: info.pageCount,
        initialPage: _progress.readPdfPage(uri) ?? 1,
        mode: mode,
        loadPage: (page) => _reader.render(uri, page - 1, renderWidth),
        onProgress: _saveProgress,
        onExit: _exit,
      ),
    );
  }
}
