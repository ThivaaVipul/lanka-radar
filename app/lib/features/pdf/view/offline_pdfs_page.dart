import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/pdf_store.dart';
import 'package:lanka_radar/features/pdf/view/pdf_page.dart';

/// The PDFs kept on the phone: how much space they take, each one (saved ones
/// marked), and a way to clear those not saved.
class OfflinePdfsPage extends StatelessWidget {
  const OfflinePdfsPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (context) => const OfflinePdfsPage());

  @override
  Widget build(BuildContext context) {
    final store = context.read<PdfStore>();
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return StreamBuilder<List<PdfRow>>(
      stream: store.watch(),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <PdfRow>[];
        final total = rows.fold<int>(0, (sum, row) => sum + row.bytes);
        final unsaved = rows.any((row) => !row.saved);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Offline PDFs'),
            actions: [
              if (unsaved)
                TextButton(
                  onPressed: () => unawaited(store.clear()),
                  child: const Text('Clear'),
                ),
            ],
          ),
          body: rows.isEmpty
              ? Center(
                  child: Text(
                    snapshot.hasData ? 'No PDFs yet' : '',
                    style: theme.textTheme.titleMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        '${rows.length} ${rows.length == 1 ? 'PDF' : 'PDFs'}, '
                        '${size(total)}',
                        style: muted,
                      ),
                    ),
                    for (final row in rows)
                      ListTile(
                        title: Text(
                          row.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${size(row.bytes)}$dot'
                          '${cardDate(row.openedAt, today: DateTime.now())}',
                        ),
                        trailing: IconButton(
                          tooltip: row.saved ? 'Saved' : 'Save',
                          isSelected: row.saved,
                          icon: const Icon(Icons.bookmark_border),
                          selectedIcon: const Icon(Icons.bookmark),
                          onPressed: () => unawaited(
                            store.setSaved(row.url, saved: !row.saved),
                          ),
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).push(PdfPage.route(row.url, title: row.title)),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// 850 KB, 12.4 MB.
String size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
