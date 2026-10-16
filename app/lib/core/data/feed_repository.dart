import 'dart:convert';

import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

/// The feed: items stored on the phone, refreshed from the data branch.
///
/// A refresh reads `months/index.json` and downloads only the months whose hash
/// changed, newest first, so a fresh install shows the latest items while the
/// rest of the year fills in. Datasets and status come along with ETags. If a
/// download fails, everything stored so far stays, and the next refresh picks
/// up where this one stopped.
class FeedRepository {
  FeedRepository({
    required AppDatabase database,
    required DataBranch remote,
    DateTime Function()? now,
  }) : _db = database,
       _branch = remote,
       _now = now ?? DateTime.now;

  static const indexPath = 'months/index.json';
  static const documents = [
    'datasets/holidays.json',
    'datasets/usd-lkr.json',
    'status.json',
  ];

  final AppDatabase _db;
  final DataBranch _branch;
  final DateTime Function() _now;

  /// Every stored item, newest first.
  Stream<List<FeedItem>> watchItems() => _db.watchItems().map(
    (rows) => [
      for (final row in rows)
        FeedItem.fromJson(jsonDecode(row.json) as Map<String, Object?>),
    ],
  );

  /// When the last refresh finished, if one ever did.
  Future<DateTime?> lastRefresh() async =>
      (await _db.file(indexPath))?.fetchedAt;

  /// Refreshes when the last refresh is older than [maxAge]; true if it did.
  Future<bool> refreshIfStale(Duration maxAge) async {
    final last = await lastRefresh();
    if (last != null && _now().difference(last) < maxAge) {
      return false;
    }
    await refresh();
    return true;
  }

  Future<void> refresh() async {
    final now = _now();
    final known = await _db.file(indexPath);
    final index = await _branch.get(indexPath, etag: known?.etag);
    if (index != null) {
      final months = _months(index.body);
      final held = await _db.monthHashes();
      for (final (:month, :hash) in months) {
        if (held[month] == hash) {
          continue;
        }
        final path = AppDatabase.monthPath(month);
        final file = await _branch.get(path);
        if (file == null) {
          continue;
        }
        await _db.replaceMonth(
          month,
          _rows(file.body, month, now),
          FileRow(path: path, hash: hash, fetchedAt: now),
        );
      }
      await _db.keepMonths({for (final entry in months) entry.month});
    }
    for (final path in documents) {
      final held = await _db.file(path);
      final fetched = await _branch.get(path, etag: held?.etag);
      if (fetched != null) {
        await _db.saveFile(
          FileRow(
            path: path,
            etag: fetched.etag,
            body: fetched.body,
            fetchedAt: now,
          ),
        );
      }
    }
    // Saved last, so a refresh that failed part way asks for the index again.
    await _db.saveFile(
      FileRow(
        path: indexPath,
        etag: index != null ? index.etag : known?.etag,
        fetchedAt: now,
      ),
    );
  }

  static List<({String month, String hash})> _months(String body) {
    final json = jsonDecode(body) as Map<String, Object?>;
    return [
      for (final entry in json['months']! as List<Object?>)
        if (entry case {'month': final String month, 'hash': final String hash})
          (month: month, hash: hash),
    ];
  }

  static List<ItemsCompanion> _rows(String body, String month, DateTime now) {
    final json = jsonDecode(body) as Map<String, Object?>;
    return [
      for (final raw in json['items']! as List<Object?>)
        _row(raw! as Map<String, Object?>, month, now),
    ];
  }

  static ItemsCompanion _row(
    Map<String, Object?> json,
    String month,
    DateTime now,
  ) {
    final item = FeedItem.fromJson(json);
    final number = item.data['number'];
    final search = [
      item.headlineEn,
      ?item.headlineTa,
      ?item.issuer,
      if (number is String) number,
    ].join('\n').toLowerCase();
    return ItemsCompanion.insert(
      id: item.id,
      month: month,
      published: json['published']! as String,
      topic: item.topic,
      search: search,
      json: jsonEncode(json),
      firstSeen: now,
    );
  }
}
