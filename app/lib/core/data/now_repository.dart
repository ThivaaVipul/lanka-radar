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

  /// The load shedding schedule as EDLCare last listed it.
  static const schedulePath = 'phone/load-shedding.json';

  /// Each place's load shedding group, as last found from its point.
  static const groupsPath = 'phone/power-groups.json';

  /// How long a place's group is trusted before it is looked up again, as
  /// CEB can move feeders between groups; longer for a place in none, which
  /// takes every group's outlines to be sure of.
  static const groupCheck = Duration(days: 1);
  static const noGroupCheck = Duration(days: 7);
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
    await refreshGroups();
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

  /// The power cuts at each place set up, from its area's last listing and
  /// its load shedding group's schedule; null until a place has both an area
  /// and a point. Load shedding on now is listed in place of the map's cuts.
  Future<PowerNow?> powerNow() async {
    final places = (await powerSetup()).ready;
    if (places.isEmpty) {
      return null;
    }
    final now = _now();
    final areas = await _stored(powerPath, 'areas');
    final groups = await _stored(groupsPath, 'places');
    final listed = (await _db.file(schedulePath))?.body;
    final schedule = listed == null
        ? const <PlannedCut>[]
        : parseSchedule(listed);
    PlaceCuts cutsAt(Place place) {
      final point = place.point!;
      // A group found for where the place was before it moved doesn't count.
      final group = switch (groups[place.id]) {
        {'point': final String at, 'group': final String group}
            when at == _pointKey(point) =>
          group,
        _ => null,
      };
      final cuts = [
        for (final cut in schedule)
          if (group != null && cut.group == group) cut,
      ];
      final onNow = [
        for (final cut in cuts)
          if (cut.onAt(now)) cut.asOutage,
      ];
      return PlaceCuts(
        place: place,
        group: group,
        outages: onNow.isNotEmpty
            ? onNow
            : outagesAt(
                parseOutages(jsonEncode(areas[place.area!.id] ?? const [])),
                point,
              ),
        ahead: [
          for (final cut in cuts)
            if (cut.start.isAfter(now)) cut,
        ],
      );
    }

    return PowerNow(
      places: [for (final place in places) cutsAt(place)],
      checked: (await status(powerSource)).lastSuccess,
    );
  }

  /// Reads the outages of each area a place is in, and the load shedding
  /// schedule (today and tomorrow, all groups). An area that fails keeps its
  /// last listing and is recorded as a failure; the schedule keeps its last
  /// listing quietly, so the map's check stands on its own.
  Future<void> refreshPower() async {
    final ids = (await powerSetup()).areaIds;
    if (ids.isEmpty) {
      return;
    }
    final today = _today();
    await _read(powerSource, () async {
      final held = await _stored(powerPath, 'areas');
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
      try {
        final body = await _edl.schedule(
          from: today,
          to: today.add(const Duration(days: 2)),
        );
        parseSchedule(body);
        await _db.saveFile(
          FileRow(path: schedulePath, body: body, fetchedAt: _now()),
        );
      } on Exception {
        // The last schedule stays; the next sync tries again.
      }
      if (failed case final failed?) {
        throw failed;
      }
    });
  }

  /// Finds each place's load shedding group from its point, on the phone:
  /// first the group it was in, then the groups of the other places, then
  /// the rest, one group's outlines at a time. A place's group is looked up
  /// again after [groupCheck] ([noGroupCheck] when it is in none) and when it
  /// moves. A lookup that fails keeps what was found before.
  Future<void> refreshGroups() async {
    final places = (await powerSetup()).ready;
    if (places.isEmpty) {
      return;
    }
    final held = await _stored(groupsPath, 'places');
    final now = _now();
    final found = <String, Object?>{};
    for (final place in places) {
      final key = _pointKey(place.point!);
      final last = held[place.id];
      if (!_groupDue(place, last, now)) {
        found[place.id] = last;
        continue;
      }
      final likely = [
        if (last case {'group': final String group}) group,
        for (final other in [...found.values, ...held.values])
          if (other case {'group': final String group}) group,
      ];
      try {
        found[place.id] = {
          'point': key,
          'group': await _groupAt(place.point!, likely),
          'checked': now.toIso8601String(),
        };
      } on Exception {
        if (last != null) {
          found[place.id] = last;
        }
      }
    }
    await _db.saveFile(
      FileRow(
        path: groupsPath,
        body: jsonEncode({'places': found}),
        fetchedAt: now,
      ),
    );
  }

  /// Whether any place's group is due to be looked up ([refreshGroups]).
  Future<bool> groupsDue() async {
    final held = await _stored(groupsPath, 'places');
    final now = _now();
    return (await powerSetup()).ready.any(
      (place) => _groupDue(place, held[place.id], now),
    );
  }

  /// Whether [place]'s group, [last] found, is due to be looked up again: it
  /// moved, or the lookup is older than [groupCheck] ([noGroupCheck] for a
  /// place in none).
  static bool _groupDue(Place place, Object? last, DateTime now) =>
      last is! Map<String, Object?> ||
      last['point'] != _pointKey(place.point!) ||
      last['checked'] is! String ||
      now.difference(DateTime.parse(last['checked']! as String)) >=
          (last['group'] == null ? noGroupCheck : groupCheck);

  /// The group whose outlines [point] is in, trying [likely] groups first,
  /// one at a time, then the rest [groupsAtOnce] at a time; null when it is
  /// in none.
  Future<String?> _groupAt(GeoPoint point, List<String> likely) async {
    Future<bool> isIn(String group) async =>
        inGroup(parseGroupOutlines(await _edl.groupOutlines(group)), point);
    final tried = <String>{};
    for (final group in likely) {
      if (tried.add(group) && await isIn(group)) {
        return group;
      }
    }
    final rest = [
      for (final group in loadSheddingGroups)
        if (!tried.contains(group)) group,
    ];
    for (var from = 0; from < rest.length; from += groupsAtOnce) {
      final batch = rest.skip(from).take(groupsAtOnce).toList();
      final found = await Future.wait([for (final group in batch) isIn(group)]);
      if (found.indexOf(true) case final at when at >= 0) {
        return batch[at];
      }
    }
    return null;
  }

  /// How many groups' outlines are read at once while looking for a place's
  /// group: quicker, and well inside EDLCare's limit of 90 requests.
  static const groupsAtOnce = 4;

  static String _pointKey(GeoPoint point) => '${point.lat},${point.lon}';

  /// What a power file keeps under [key]: each area's outages by area ID, or
  /// each place's group by place ID.
  Future<Map<String, Object?>> _stored(String path, String key) async {
    final body = (await _db.file(path))?.body;
    final json = body == null ? null : jsonDecode(body);
    final stored = json is Map<String, Object?> ? json[key] : null;
    return stored is Map<String, Object?> ? stored : const {};
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
