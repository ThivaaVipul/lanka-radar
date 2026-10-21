import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/search_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';

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

/// A gazette's text, its first pages, for searching inside it: a row per item,
/// from the data branch's `texts/` month files.
@DataClassName('TextRow')
class Texts extends Table {
  TextColumn get id => text()();

  /// The month file it came in, yyyy-MM.
  TextColumn get month => text()();

  /// The text as search keeps it (see searchWords).
  TextColumn get search => text()();

  /// The text as printed, for the line a search result shows.
  TextColumn get body => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// PDFs kept on the phone after they were opened, so they open again offline.
@DataClassName('PdfRow')
class Pdfs extends Table {
  TextColumn get url => text()();

  /// The file's name in the app's PDF folder.
  TextColumn get file => text()();

  /// What it is, for the list of kept PDFs.
  TextColumn get title => text()();
  IntColumn get bytes => integer()();
  DateTimeColumn get openedAt => dateTime()();

  /// Kept however much space the others take.
  BoolColumn get saved => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {url};
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

@DriftDatabase(tables: [Items, Files, Settings, FuelPrices, Rates, Texts, Pdfs])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(settings);
      }
      if (from < 3) {
        await migrator.createTable(fuelPrices);
        await migrator.createTable(rates);
      }
      if (from < 5) {
        // Search learned the words on the cards (4), then to match words
        // from their start (5).
        await reindexSearch();
      }
      if (from < 6) {
        await migrator.createTable(texts);
        await migrator.createTable(pdfs);
      }
    },
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'lanka_radar',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
      setup: _shareWithTheOtherEngine,
    ),
  );

  /// The app and the background sync (another Flutter engine) open the file
  /// separately: write-ahead logging lets one read while the other writes, and
  /// a writer waits for the other's lock instead of failing. Set as the
  /// connection opens, so it covers migrations too: both engines may start one
  /// right after an update.
  static void _shareWithTheOtherEngine(CommonDatabase database) {
    database
      ..execute('PRAGMA busy_timeout = 10000')
      ..execute('PRAGMA journal_mode = WAL');
  }

  /// Makes the item and file queries read again, after the background sync
  /// (which streams can't see) may have changed them.
  void notifyExternalChanges() =>
      notifyUpdates({TableUpdate.onTable(items), TableUpdate.onTable(files)});

  /// Works out every stored item's search text again from its JSON.
  Future<void> reindexSearch() => transaction(() async {
    for (final row in await select(items).get()) {
      final item = FeedItem.fromJson(
        jsonDecode(row.json) as Map<String, Object?>,
      );
      await (update(items)..where((other) => other.id.equals(row.id))).write(
        ItemsCompanion(search: Value(searchText(item))),
      );
    }
  });

  /// Every item, newest first.
  Stream<List<ItemRow>> watchItems() =>
      (select(items)..orderBy([
            (row) => OrderingTerm.desc(row.published),
            (row) => OrderingTerm.desc(row.id),
          ]))
          .watch();

  /// Items whose search text has a word starting with every one of [words]
  /// (lower case), newest first; the text puts a space before each word.
  Future<List<ItemRow>> search(List<String> words) {
    final query = select(items)
      ..orderBy([
        (row) => OrderingTerm.desc(row.published),
        (row) => OrderingTerm.desc(row.id),
      ]);
    for (final word in words) {
      query.where(
        (row) =>
            row.search.like('% ${_escape(word)}%', escapeChar: _likeEscape),
      );
    }
    return query.get();
  }

  /// Items whose text (not counting those in [excluding]) has a word starting
  /// with every one of [words], newest first, with the text; at most [limit].
  Future<List<(ItemRow, TextRow)>> searchTexts(
    List<String> words, {
    Set<String> excluding = const {},
    int limit = 50,
  }) async {
    final query = select(items).join([
      innerJoin(texts, texts.id.equalsExp(items.id)),
    ])..where(items.id.isNotIn(excluding));
    for (final word in words) {
      query.where(
        texts.search.like('% ${_escape(word)}%', escapeChar: _likeEscape),
      );
    }
    query
      ..orderBy([
        OrderingTerm.desc(items.published),
        OrderingTerm.desc(items.id),
      ])
      ..limit(limit);
    return [
      for (final row in await query.get())
        (row.readTable(items), row.readTable(texts)),
    ];
  }

  Future<PdfRow?> pdf(String url) =>
      (select(pdfs)..where((row) => row.url.equals(url))).getSingleOrNull();

  /// The kept PDFs, the last opened first.
  Stream<List<PdfRow>> watchPdfs() => (select(
    pdfs,
  )..orderBy([(row) => OrderingTerm.desc(row.openedAt)])).watch();

  Future<List<PdfRow>> allPdfs() =>
      (select(pdfs)..orderBy([(row) => OrderingTerm.desc(row.openedAt)])).get();

  Future<void> savePdf(PdfRow row) => into(pdfs).insertOnConflictUpdate(row);

  Future<void> deletePdf(String url) =>
      (delete(pdfs)..where((row) => row.url.equals(url))).go();

  /// The hash each stored text month had in the texts index, by month.
  Future<Map<String, String>> textHashes() async {
    final rows = await (select(
      files,
    )..where((row) => row.path.like('texts/%-%.json'))).get();
    return {
      for (final row in rows)
        if (row.hash != null) _textMonthOf(row.path): row.hash!,
    };
  }

  /// Makes a text month hold exactly [rows].
  Future<void> replaceTextMonth(
    String month,
    List<TextsCompanion> rows,
    FileRow file,
  ) => transaction(() async {
    await (delete(texts)..where((row) => row.month.equals(month))).go();
    await batch((batch) => batch.insertAllOnConflictUpdate(texts, rows));
    await saveFile(file);
  });

  /// Drops the texts and files of months the texts index no longer lists.
  Future<void> keepTextMonths(Set<String> months) => transaction(() async {
    await (delete(texts)..where((row) => row.month.isNotIn(months))).go();
    final held = await textHashes();
    for (final month in held.keys.where((month) => !months.contains(month))) {
      await (delete(
        files,
      )..where((row) => row.path.equals(textPath(month)))).go();
    }
  });

  static String textPath(String month) => 'texts/$month.json';

  static String _textMonthOf(String path) =>
      path.substring('texts/'.length, path.length - '.json'.length);

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
