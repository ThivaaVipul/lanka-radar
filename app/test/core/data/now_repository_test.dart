import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/now_repository.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeSources sources;
  late DateTime now;
  late NowRepository phone;

  setUp(() {
    database = memoryDatabase();
    sources = FakeSources();
    now = DateTime(2026, 10, 16, 9);
    phone = sources.repository(database, now: () => now);
  });

  tearDown(() => database.close());

  test('a refresh stores the fuel prices and rates and records each '
      "source's success", () async {
    await phone.refresh();

    final card = await phone.load(const []);
    expect(card.fuel, hasLength(6));
    expect(card.fuel.first.name, 'Petrol 92');
    expect(card.rates.first.rate, 331.286);
    expect(card.ratesFromBackup, isFalse);
    expect(card.fuelAsOf, now);
    final status = await phone.status(NowRepository.ceypetcoSource);
    expect(status.lastSuccess, now);
    expect(status.lastError, isNull);
  });

  test(
    'a failing source is recorded, keeps what it had, and stops nothing',
    () async {
      await phone.refresh();
      final before = now;
      sources.offline = true;
      now = now.add(const Duration(hours: 1));

      await phone.refresh();

      final status = await phone.status(NowRepository.cbslSource);
      expect(status.lastRun, now);
      expect(status.lastSuccess, before);
      expect(status.lastError, contains('offline'));
      expect((await phone.load(const [])).rates, isNotEmpty);
    },
  );

  test('a price CEYPETCO changes keeps the one before', () async {
    await phone.refresh();
    final json = jsonDecode(sources.ceypetco) as Map<String, Object?>;
    for (final entry in json['data']! as List<Object?>) {
      final row = entry! as Map<String, Object?>;
      if (row['product'] == 'Lanka Petrol 92 Octane') {
        row['price'] = 399;
        row['effectiveDate'] = '2026-10-15T00:00:00.000Z';
      }
    }
    sources.ceypetco = jsonEncode(json);

    await phone.refresh();

    final petrol = (await phone.load(const [])).fuel.first;
    expect(petrol.name, 'Petrol 92');
    expect(petrol.price, 399);
    expect(petrol.since, DateTime(2026, 10, 15));
    expect(petrol.was, 414);
  });

  test('refreshIfStale waits until the last try is old enough', () async {
    const maxAge = Duration(minutes: 15);

    await phone.refreshIfStale(maxAge);
    sources.requests.clear();
    now = now.add(const Duration(minutes: 10));
    await phone.refreshIfStale(maxAge);
    expect(sources.requests, isEmpty);

    now = now.add(const Duration(minutes: 10));
    await phone.refreshIfStale(maxAge);
    expect(sources.requests, ['api.ceypetco.gov.lk', 'www.cbsl.gov.lk']);
  });
}
