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

@DriftDatabase(tables: [Items, Files])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() => driftDatabase(
    name: 'lanka_radar',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );

  /// Every item, newest first.
  Stream<List<ItemRow>> watchItems() =>
      (select(items)..orderBy([
            (row) => OrderingTerm.desc(row.published),
            (row) => OrderingTerm.desc(row.id),
          ]))
          .watch();

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

  /// Drops the items and files of months the index no longer lists.
  Future<void> keepMonths(Set<String> months) => transaction(() async {
    await (delete(items)..where((row) => row.month.isNotIn(months))).go();
    final held = await monthHashes();
    for (final month in held.keys.where((month) => !months.contains(month))) {
      await (delete(
        files,
      )..where((row) => row.path.equals(monthPath(month)))).go();
    }
  });

  static String monthPath(String month) => 'months/$month.json';

  static String _monthOf(String path) =>
      path.substring('months/'.length, path.length - '.json'.length);
}
