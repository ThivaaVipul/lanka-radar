import 'dart:convert';

import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/rate_moves.dart';
import 'package:lanka_radar/core/data/search_text.dart';

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
  static const usdLkrPath = 'datasets/usd-lkr.json';
  static const documents = [
    'datasets/holidays.json',
    usdLkrPath,
    'status.json',
  ];

  final AppDatabase _db;
  final DataBranch _branch;
  final DateTime Function() _now;

  static const _lastVisit = 'lastVisit';
  static const _recent = 'search.recent';

  /// How many recent searches are kept.
  static const recentKept = 5;

  /// Every stored item, newest first.
  Stream<List<FeedItem>> watchItems() =>
      _db.watchItems().map((rows) => [for (final row in rows) _item(row)]);

  /// Stored items whose headlines, issuer or number have a word starting with
  /// every word of [query], in any case; newest first.
  Future<List<FeedItem>> search(String query) async {
    final words = queryWords(query);
    if (words.isEmpty) {
      return const [];
    }
    return [for (final row in await _db.search(words)) _item(row)];
  }

  Future<FeedItem?> item(String id) async {
    final row = await _db.item(id);
    return row == null ? null : _item(row);
  }

  /// The stored items among [ids]; those no longer stored are left out.
  Future<List<FeedItem>> items(List<String> ids) async => ids.isEmpty
      ? const []
      : [for (final row in await _db.itemsWithIds(ids)) _item(row)];

  /// Items first stored at or after [time] (by a refresh that started then).
  Future<List<FeedItem>> itemsSeenSince(DateTime time) async => [
    for (final row in await _db.itemsSeenSince(time)) _item(row),
  ];

  /// Re-reads the stored items, which a background sync may have changed.
  void notifyExternalChanges() => _db.notifyExternalChanges();

  /// Makes the workflow's USD/LKR move items from the rates the phone read from
  /// CBSL, for the days the workflow's copy of the rates doesn't reach yet, and
  /// drops those it has caught up with: if it found the move too, its own item
  /// comes in the month files under the same ID.
  Future<void> updatePhoneItems() async {
    final dataset = datasetRates((await _db.file(usdLkrPath))?.body);
    final last = dataset.isEmpty ? null : (dataset.keys.toList()..sort()).last;
    if (last != null) {
      await _db.dropPhoneItemsThrough(last);
    }
    final rates = {
      for (final row in await _db.allRates()) row.day: row.rate,
      // Where both have a day, the workflow's rate, so both find the same moves.
      ...dataset,
    };
    final now = _now();
    await _db.addPhoneItems([
      for (final move in weeklyMoves(rates))
        if (last == null || move.day.compareTo(last) > 0)
          _row(moveItem(move), AppDatabase.phoneMonth, now),
    ]);
  }

  /// The last searches, newest first.
  Future<List<String>> recentSearches() async {
    final value = await _db.setting(_recent);
    return value == null
        ? const []
        : [...(jsonDecode(value) as List<Object?>).whereType<String>()];
  }

  /// Keeps [query] at the top of the recent searches.
  Future<void> rememberSearch(String query) async {
    final kept = query.trim();
    if (kept.isEmpty) {
      return;
    }
    final recent = [
      kept,
      for (final other in await recentSearches())
        if (other.toLowerCase() != kept.toLowerCase()) other,
    ].take(recentKept).toList();
    await _db.saveSetting(_recent, jsonEncode(recent));
  }

  Future<void> forgetSearch(String query) async {
    final recent = [
      for (final other in await recentSearches())
        if (other != query) other,
    ];
    await _db.saveSetting(_recent, jsonEncode(recent));
  }

  /// When the feed was last left, if ever: items that arrived after it are new.
  Future<DateTime?> lastVisit() async {
    final value = await _db.setting(_lastVisit);
    return value == null ? null : DateTime.parse(value);
  }

  Future<void> saveVisit(DateTime time) =>
      _db.saveSetting(_lastVisit, time.toIso8601String());

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
      final Fetched? fetched;
      try {
        fetched = await _branch.get(path, etag: held?.etag);
      } on DataBranchException catch (error) {
        if (error.statusCode != 404) {
          rethrow;
        }
        // A dataset the workflow hasn't written yet.
        continue;
      }
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

  static FeedItem _item(ItemRow row) => FeedItem.fromJson(
    jsonDecode(row.json) as Map<String, Object?>,
    firstSeen: row.firstSeen,
  );

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
    return ItemsCompanion.insert(
      id: item.id,
      month: month,
      published: json['published']! as String,
      topic: item.topic,
      search: searchText(item),
      json: jsonEncode(json),
      firstSeen: now,
    );
  }
}
