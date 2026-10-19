import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Feed items, one row each: the item as published (JSON), plus the columns the
/// app sorts, filters and searches by.
@DataClassName('ItemRow')
class Items extends Table {
  TextColumn get id => text()();

  /// The month file the item came in, yyyy-MM.
  TextColumn get month => text()();

  /// yyyy-MM-dd, so text order is date order.
  TextColumn get published => text()();
  TextColumn get topic => text()();

  /// Headlines, issuer and number in lower case, for search.
  TextColumn get search => text()();
  TextColumn get json => text()();

  /// When the app first stored the item; later updates keep it.
  DateTimeColumn get firstSeen => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Files read from the data branch: the ETag to ask "changed since?", the hash a
/// month had in the index when it was read, and the body of the small files the
/// app keeps whole (datasets, status).
@DataClassName('FileRow')
class Files extends Table {
  TextColumn get path => text()();
  TextColumn get etag => text().nullable()();
  TextColumn get hash => text().nullable()();
  TextColumn get body => text().nullable()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {path};
}

/// Small values the app keeps for itself, such as when the feed was last left.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// CEYPETCO's prices as the phone has seen them: a row per product and the day a
/// price started, so the price before stays known.
@DataClassName('FuelPriceRow')
class FuelPrices extends Table {
  TextColumn get product => text()();

  /// yyyy-MM-dd
  TextColumn get effective => text()();
  RealColumn get price => real()();

  @override
  Set<Column> get primaryKey => {product, effective};
}

/// USD/LKR by day, from CBSL's rate search.
@DataClassName('RateRow')
class Rates extends Table {
  /// yyyy-MM-dd
  TextColumn get day => text()();
  RealColumn get rate => real()();

  @override
  Set<Column> get primaryKey => {day};
}

@DriftDatabase(tables: [Items, Files, Settings, FuelPrices, Rates])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // The app and the background sync (another Flutter engine) open the file
    // separately: write-ahead logging lets one read while the other writes,
    // and a writer waits for the other's lock instead of failing.
    beforeOpen: (details) async {
      await customSelect('PRAGMA journal_mode = WAL').get();
      await customStatement('PRAGMA busy_timeout = 10000');
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(settings);
      }
      if (from < 3) {
        await migrator.createTable(fuelPrices);
        await migrator.createTable(rates);
      }
    },
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'lanka_radar',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );

  /// Makes the item and file queries read again, after the background sync
  /// (which streams can't see) may have changed them.
  void notifyExternalChanges() =>
      notifyUpdates({TableUpdate.onTable(items), TableUpdate.onTable(files)});

  /// Every item, newest first.
  Stream<List<ItemRow>> watchItems() =>
      (select(items)..orderBy([
            (row) => OrderingTerm.desc(row.published),
            (row) => OrderingTerm.desc(row.id),
          ]))
          .watch();

  /// Items whose search text holds every one of [words] (lower case), newest
  /// first.
  Future<List<ItemRow>> search(List<String> words) {
    final query = select(items)
      ..orderBy([
        (row) => OrderingTerm.desc(row.published),
        (row) => OrderingTerm.desc(row.id),
      ]);
    for (final word in words) {
      query.where(
        (row) => row.search.like('%${_escape(word)}%', escapeChar: _likeEscape),
      );
    }
    return query.get();
  }

  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((row) => row.key.equals(key))).getSingleOrNull())?.value;

  Future<void> deleteSetting(String key) =>
      (delete(settings)..where((row) => row.key.equals(key))).go();

  Future<void> saveSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingRow(key: key, value: value));

  Future<List<FuelPriceRow>> allFuelPrices() => select(fuelPrices).get();

  Future<void> saveFuelPrices(List<FuelPriceRow> rows) =>
      batch((batch) => batch.insertAllOnConflictUpdate(fuelPrices, rows));

  /// Rates from [from] (yyyy-MM-dd) on, newest first.
  Future<List<RateRow>> ratesSince(String from) =>
      (select(rates)
            ..where((row) => row.day.isBiggerOrEqualValue(from))
            ..orderBy([(row) => OrderingTerm.desc(row.day)]))
          .get();

  Future<List<RateRow>> allRates() => select(rates).get();

  Future<void> saveRates(List<RateRow> rows) =>
      batch((batch) => batch.insertAllOnConflictUpdate(rates, rows));

  Future<ItemRow?> item(String id) =>
      (select(items)..where((row) => row.id.equals(id))).getSingleOrNull();

  /// The items among [ids], newest first.
  Future<List<ItemRow>> itemsWithIds(Iterable<String> ids) =>
      (select(items)
            ..where((row) => row.id.isIn(ids))
            ..orderBy([(row) => OrderingTerm.desc(row.published)]))
          .get();

  /// Items first stored at or after [time], newest first.
  Future<List<ItemRow>> itemsSeenSince(DateTime time) =>
      (select(items)
            ..where((row) => row.firstSeen.isBiggerOrEqualValue(time))
            ..orderBy([(row) => OrderingTerm.desc(row.published)]))
          .get();

  Future<FileRow?> file(String path) =>
      (select(files)..where((row) => row.path.equals(path))).getSingleOrNull();

  Future<void> saveFile(FileRow row) => into(files).insertOnConflictUpdate(row);

  /// The hash each stored month had in the index, by month (yyyy-MM).
  Future<Map<String, String>> monthHashes() async {
    final rows = await (select(
      files,
    )..where((row) => row.path.like('months/%-%.json'))).get();
    return {
      for (final row in rows)
        if (row.hash != null) _monthOf(row.path): row.hash!,
    };
  }

  /// Makes a month hold exactly [rows]: items no longer in it go, the rest are
  /// written, and an item already stored keeps the time it was first seen.
  Future<void> replaceMonth(
    String month,
    List<ItemsCompanion> rows,
    FileRow file,
  ) => transaction(() async {
    final ids = {for (final row in rows) row.id.value};
    await (delete(
      items,
    )..where((row) => row.month.equals(month) & row.id.isNotIn(ids))).go();
    for (final row in rows) {
      await into(items).insert(
        row,
        onConflict: DoUpdate(
          (_) => row.copyWith(firstSeen: const Value.absent()),
        ),
      );
    }
    await saveFile(file);
  });

  /// Stores items the phone made, leaving any already stored as they are.
  Future<void> addPhoneItems(List<ItemsCompanion> rows) => batch(
    (batch) => batch.insertAll(items, rows, mode: InsertMode.insertOrIgnore),
  );

  /// Drops the items the phone made for days up to [day] (yyyy-MM-dd), which
  /// the workflow's copy of the rates covers now.
  Future<void> dropPhoneItemsThrough(String day) =>
      (delete(items)..where(
            (row) =>
                row.month.equals(phoneMonth) &
                row.published.isSmallerOrEqualValue(day),
          ))
          .go();

  /// Drops the items and files of months the index no longer lists.
  Future<void> keepMonths(Set<String> months) => transaction(() async {
    await (delete(
      items,
    )..where((row) => row.month.isNotIn({...months, phoneMonth}))).go();
    final held = await monthHashes();
    for (final month in held.keys.where((month) => !months.contains(month))) {
      await (delete(
        files,
      )..where((row) => row.path.equals(monthPath(month)))).go();
    }
  });

  static String monthPath(String month) => 'months/$month.json';

  /// Where the items the phone makes itself (USD/LKR moves from CBSL's rates)
  /// are filed: no month file replaces them, and the workflow's copy of the
  /// same ID takes over when it comes.
  static const phoneMonth = 'phone';

  static const _likeEscape = '!';

  /// A word with LIKE's wildcards (and the escape mark) escaped, so it matches
  /// only itself.
  static String _escape(String word) => word.replaceAllMapped(
    RegExp('[!%_]'),
    (match) => '$_likeEscape${match[0]}',
  );

  static String _monthOf(String path) =>
      path.substring('months/'.length, path.length - '.json'.length);
}
