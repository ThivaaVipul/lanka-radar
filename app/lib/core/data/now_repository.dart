import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/health.dart';
import 'package:lanka_radar/core/data/market_prices.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
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

/// The Now card's sources: CEYPETCO's fuel prices, CBSL's USD/LKR and its
/// market prices, which the phone reads itself and keeps a history of, plus
/// the holidays and the workflow's backup rates the feed refresh stores.
class NowRepository {
  NowRepository({
    required AppDatabase database,
    required this._ceypetco,
    required this._cbsl,
    required this._market,
    required this._edl,
    DateTime Function()? now,
    Future<Map<String, String>> Function()? tamilNames,
  }) : _db = database,
       _now = now ?? DateTime.now,
       _tamilNames = tamilNames ?? _loadTamilNames;

  static const ceypetcoSource = 'ceypetco';
  static const cbslSource = 'cbsl';
  static const marketSource = 'cbsl-market';
  static const powerSource = 'edlcare';

  /// Each place's area's outages as EDLCare last listed them.
  static const powerPath = 'phone/power-cuts.json';
  static const _powerSetup = 'power.setup';

  /// Where the market prices the phone has read are kept.
  static const marketPath = 'phone/market-prices.json';

  /// How many price reports one refresh reads at most: a fresh install reads
  /// the listing's few weeks.
  static const reportsPerRead = 15;

  /// How long a look at the listing lasts while the day's report isn't in.
  static const marketRecheck = Duration(hours: 2);

  /// How far back each CBSL read goes: enough for the 30-day sheet.
  static const rateDays = 45;
  static const _lastRefresh = 'phone.lastRefresh';

  final AppDatabase _db;
  final Ceypetco _ceypetco;
  final Cbsl _cbsl;
  final CbslMarket _market;
  final EdlCare _edl;
  final DateTime Function() _now;
  final Future<Map<String, String>> Function() _tamilNames;
  Map<String, String>? _names;
  (DateTime?, MarketPrices)? _parsedMarket;

  /// Reads CEYPETCO and CBSL when the last try is older than [maxAge].
  Future<void> refreshIfStale(Duration maxAge) async {
    final last = await _db.setting(_lastRefresh);
    if (last != null && _now().difference(DateTime.parse(last)) < maxAge) {
      return;
    }
    await refresh();
  }

  /// Reads the sources, each on its own: a failure is recorded with its source
  /// and stops neither the others nor the feed.
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
    await _readMarket();
    await refreshPower();
  }

  /// The places the phone watches for power cuts.
  Future<PowerSetup> powerSetup() async =>
      PowerSetup.fromJson(await _db.setting(_powerSetup));

  Future<void> savePowerSetup(PowerSetup setup) =>
      _db.saveSetting(_powerSetup, setup.toJson());

  /// CEB's provinces and a province's area offices, for picking a place's.
  Future<List<CebRegion>> powerProvinces() => _edl.provinces();

  Future<List<CebRegion>> powerAreas(String provinceId) =>
      _edl.areas(provinceId);

  /// The power cuts at each place set up, from its area's last listing; null
  /// until a place has both an area and a point.
  Future<PowerNow?> powerNow() async {
    final places = (await powerSetup()).ready;
    if (places.isEmpty) {
      return null;
    }
    final areas = await _powerAreas();
    return PowerNow(
      places: [
        for (final place in places)
          PlaceCuts(
            place: place,
            outages: outagesAt(
              parseOutages(jsonEncode(areas[place.area!.id] ?? const [])),
              place.point!,
            ),
          ),
      ],
      checked: (await status(powerSource)).lastSuccess,
    );
  }

  /// Reads the outages of each area a place is in. An area that fails keeps
  /// its last listing, and the failure is recorded once the rest are in.
  Future<void> refreshPower() async {
    final ids = (await powerSetup()).areaIds;
    if (ids.isEmpty) {
      return;
    }
    await _read(powerSource, () async {
      final held = await _powerAreas();
      final areas = <String, Object?>{};
      Exception? failed;
      for (final id in ids) {
        try {
          final body = await _edl.outages(id);
          parseOutages(body);
          areas[id] = jsonDecode(body);
        } on Exception catch (error) {
          failed = error;
          areas[id] = held[id];
        }
      }
      await _db.saveFile(
        FileRow(
          path: powerPath,
          body: jsonEncode({'areas': areas}),
          fetchedAt: _now(),
        ),
      );
      if (failed != null) {
        throw failed;
      }
    });
  }

  /// Each area's outages as EDLCare last listed them, by area ID.
  Future<Map<String, Object?>> _powerAreas() async {
    final body = (await _db.file(powerPath))?.body;
    final json = body == null ? null : jsonDecode(body);
    return switch (json) {
      {'areas': final Map<String, Object?> areas} => areas,
      _ => const {},
    };
  }

  /// Reads the price reports the phone doesn't have yet, newest first, unless
  /// the latest is in (today's, or Friday's at a weekend) or the listing was
  /// looked at lately.
  Future<void> _readMarket() async {
    final held = await marketPrices();
    final today = _today();
    final weekday = today.subtract(
      Duration(
        days: switch (today.weekday) {
          DateTime.saturday => 1,
          DateTime.sunday => 2,
          _ => 0,
        },
      ),
    );
    final latest = held.latest;
    final looked = (await status(marketSource)).lastRun;
    if ((latest != null && !latest.isBefore(weekday)) ||
        (looked != null && _now().difference(looked) < marketRecheck)) {
      return;
    }
    await _read(marketSource, () async {
      var prices = held;
      final wanted = [
        for (final day in await _market.listedDays())
          if (!prices.days.contains(day) && !prices.skipped.contains(day)) day,
      ];
      for (final day in wanted.take(reportsPerRead)) {
        try {
          prices = prices.withReport(day, await _market.report(day));
        } on FormatException {
          // Laid out some other way: not tried again.
          prices = prices.skipping(day);
        } on SourceException catch (error) {
          if (error.statusCode != 404) {
            rethrow;
          }
          prices = prices.skipping(day);
        }
        await _db.saveFile(
          FileRow(
            path: marketPath,
            body: jsonEncode(prices.toJson()),
            fetchedAt: _now(),
          ),
        );
      }
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
      market: await marketPrices(),
      power: await powerNow(),
    );
  }

  /// The market prices the phone has read, parsed again only when they change.
  Future<MarketPrices> marketPrices() async {
    final file = await _db.file(marketPath);
    final saved = file?.fetchedAt;
    if (_parsedMarket case (final known, final prices) when known == saved) {
      return prices;
    }
    final prices = MarketPrices.fromJson(file?.body);
    _parsedMarket = (saved, prices);
    return prices;
  }

  /// Every price CEYPETCO has given the phone, with the day each started.
  Future<List<FuelPriceRow>> fuelRows() => _db.allFuelPrices();

  /// Every USD/LKR rate the phone has read from CBSL.
  Future<List<RateRow>> allRates() => _db.allRates();

  /// The workflow's copy of the rates since January (`datasets/usd-lkr.json`).
  Future<String?> datasetRates() async =>
      (await _db.file('datasets/usd-lkr.json'))?.body;

  /// Every holiday from today on, for the reminders.
  Future<List<HolidayNow>> upcomingHolidays() async => holidaysFrom(
    (await _db.file('datasets/holidays.json'))?.body,
    _today(),
    _names ??= await _tamilNames(),
  );

  /// Every source's health: the workflow's, from its status.json, and the two
  /// the phone reads itself.
  Future<Health> health() async {
    final workflow = parseWorkflowStatus((await _db.file('status.json'))?.body);
    return Health(
      workflowRan: workflow.ran,
      github: workflow.sources,
      phone: [
        _health('Fuel prices', await status(ceypetcoSource)),
        _health('USD/LKR', await status(cbslSource)),
        _health('Market prices', await status(marketSource)),
        if ((await powerSetup()).areaIds.isNotEmpty)
          _health('Power cuts', await status(powerSource)),
      ],
    );
  }

  static SourceHealth _health(String name, SourceStatus status) => SourceHealth(
    name: name,
    lastRun: status.lastRun,
    lastSuccess: status.lastSuccess,
    lastError: status.lastError,
  );

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
