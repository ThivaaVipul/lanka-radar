import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/core/pdf_store.dart';
import 'package:lanka_radar/core/sharing.dart';
import 'package:pdfrx/pdfrx.dart';

/// An official PDF in the app, from the copy kept on the phone (downloaded and
/// kept the first time). It can be saved, so it is always kept, shared, or
/// opened in another app.
class PdfPage extends StatefulWidget {
  const PdfPage({
    required this.url,
    required this.title,
    this.page = 1,
    this.open = openExternally,
    super.key,
  });

  static Route<void> route(
    String url, {
    required String title,
    int page = 1,
    OpenLink open = openExternally,
  }) => MaterialPageRoute(
    builder: (context) =>
        PdfPage(url: url, title: title, page: page, open: open),
  );

  final String url;
  final String title;

  /// The page it opens at, such as a weekly gazette notice's.
  final int page;
  final OpenLink open;

  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  late Future<File> _file;
  bool? _saved;

  @override
  void initState() {
    super.initState();
    _file = _load();
  }

  Future<File> _load() async {
    final store = context.read<PdfStore>();
    final file = await store.open(widget.url, title: widget.title);
    await pdfrxFlutterInitialize();
    final saved = await store.isSaved(widget.url);
    if (mounted) {
      setState(() => _saved = saved);
    }
    return file;
  }

  Future<void> _toggleSaved() async {
    final saved = !(_saved ?? false);
    await context.read<PdfStore>().setSaved(widget.url, saved: saved);
    if (mounted) {
      setState(() => _saved = saved);
    }
  }

  Future<void> _openElsewhere() async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await widget.open(Uri.parse(widget.url));
    } on Exception {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the link")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (saved != null)
            IconButton(
              tooltip: saved ? 'Saved' : 'Save',
              isSelected: saved,
              icon: const Icon(Icons.bookmark_border),
              selectedIcon: const Icon(Icons.bookmark),
              onPressed: () => unawaited(_toggleSaved()),
            ),
          PopupMenuButton<void Function()>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              if (saved != null)
                PopupMenuItem(
                  value: () => unawaited(_share()),
                  child: const Text('Share'),
                ),
              PopupMenuItem(
                value: () => unawaited(_openElsewhere()),
                child: const Text('Open in another app'),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<File>(
        future: _file,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Failed(
              onRetry: () => setState(() => _file = _load()),
              onOpenElsewhere: () => unawaited(_openElsewhere()),
            );
          }
          final file = snapshot.data;
          if (file == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return PdfViewer.file(file.path, initialPageNumber: widget.page);
        },
      ),
    );
  }

  Future<void> _share() async {
    final file = await _file;
    if (mounted) {
      await context.read<Sharing>().shareFile(file.path, title: widget.title);
    }
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry, required this.onOpenElsewhere});

  final VoidCallback onRetry;
  final VoidCallback onOpenElsewhere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text("Couldn't download it", style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
          TextButton(
            onPressed: onOpenElsewhere,
            child: const Text('Open in another app'),
          ),
        ],
      ),
    );
  }
}
