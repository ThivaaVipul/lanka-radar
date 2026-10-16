import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// How a source the phone reads itself last went.
final class SourceStatus extends Equatable {
  const SourceStatus({this.lastRun, this.lastSuccess, this.lastError});

  factory SourceStatus.fromJson(Map<String, Object?> json) => SourceStatus(
    lastRun: _time(json['lastRun']),
    lastSuccess: _time(json['lastSuccess']),
    lastError: json['lastError'] as String?,
  );

  final DateTime? lastRun;
  final DateTime? lastSuccess;

  /// Null when the last run worked.
  final String? lastError;

  Map<String, Object?> toJson() => {
    'lastRun': lastRun?.toIso8601String(),
    'lastSuccess': lastSuccess?.toIso8601String(),
    'lastError': lastError,
  };

  static DateTime? _time(Object? value) =>
      value is String ? DateTime.parse(value) : null;

  @override
  List<Object?> get props => [lastRun, lastSuccess, lastError];
}

/// The Now card's sources: CEYPETCO's fuel prices and CBSL's USD/LKR, which the
/// phone reads itself and keeps a history of, plus the holidays and the
/// workflow's backup rates the feed refresh stores.
class NowRepository {
  NowRepository({
    required AppDatabase database,
    required this._ceypetco,
    required this._cbsl,
    DateTime Function()? now,
    Future<Map<String, String>> Function()? tamilNames,
  }) : _db = database,
       _now = now ?? DateTime.now,
       _tamilNames = tamilNames ?? _loadTamilNames;

  static const ceypetcoSource = 'ceypetco';
  static const cbslSource = 'cbsl';

  /// How far back each CBSL read goes: enough for the 30-day sheet.
  static const rateDays = 45;
  static const _lastRefresh = 'phone.lastRefresh';

  final AppDatabase _db;
  final Ceypetco _ceypetco;
  final Cbsl _cbsl;
  final DateTime Function() _now;
  final Future<Map<String, String>> Function() _tamilNames;
  Map<String, String>? _names;

  /// Reads CEYPETCO and CBSL when the last try is older than [maxAge].
  Future<void> refreshIfStale(Duration maxAge) async {
    final last = await _db.setting(_lastRefresh);
    if (last != null && _now().difference(DateTime.parse(last)) < maxAge) {
      return;
    }
    await refresh();
  }

  /// Reads both sources, each on its own: a failure is recorded with its source
  /// and stops neither the other nor the feed.
  Future<void> refresh() async {
    await _db.saveSetting(_lastRefresh, _now().toIso8601String());
    await _read(ceypetcoSource, () async {
      final prices = await _ceypetco.activePrices();
      await _db.saveFuelPrices([
        for (final price in prices)
          FuelPriceRow(
            product: price.product,
            effective: isoDay(price.effective),
            price: price.price,
          ),
      ]);
    });
    await _read(cbslSource, () async {
      final today = _today();
      final rates = await _cbsl.usdRates(
        from: today.subtract(const Duration(days: rateDays)),
        to: today,
      );
      await _db.saveRates([
        for (final MapEntry(key: day, value: rate) in rates.entries)
          RateRow(day: isoDay(day), rate: rate),
      ]);
    });
  }

  Future<SourceStatus> status(String source) async {
    final value = await _db.setting('source.$source');
    return value == null
        ? const SourceStatus()
        : SourceStatus.fromJson(jsonDecode(value) as Map<String, Object?>);
  }

  /// The Now card, from what the phone has stored; [items] is the feed, for
  /// the LP gas list, the exam timetable and fuel gazettes.
  Future<NowData> load(List<FeedItem> items) async {
    final today = _today();
    final ceypetco = await status(ceypetcoSource);
    return buildNow(
      today: today,
      fuelRows: await _db.allFuelPrices(),
      fuelChecked: ceypetco.lastSuccess,
      rates: await _db.ratesSince(
        isoDay(today.subtract(const Duration(days: 30))),
      ),
      backupRates: (await _db.file('datasets/usd-lkr.json'))?.body,
      holidays: (await _db.file('datasets/holidays.json'))?.body,
      tamilNames: _names ??= await _tamilNames(),
      items: items,
    );
  }

  Future<void> _read(String source, Future<void> Function() read) async {
    final before = await status(source);
    final now = _now();
    SourceStatus after;
    try {
      await read();
      after = SourceStatus(lastRun: now, lastSuccess: now);
    } on Exception catch (error) {
      after = SourceStatus(
        lastRun: now,
        lastSuccess: before.lastSuccess,
        lastError: '$error',
      );
    }
    await _db.saveSetting('source.$source', jsonEncode(after.toJson()));
  }

  DateTime _today() {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  static Future<Map<String, String>> _loadTamilNames() async {
    final json = await rootBundle.loadString('assets/holidays_ta.json');
    return (jsonDecode(json) as Map<String, Object?>).cast<String, String>();
  }
}
