import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/home_screen_widget.dart';

import '../helpers/fake_sources.dart';

void main() {
  final today = DateTime(2026, 10, 20);
  final read = DateTime(2026, 10, 20, 9);
  final outages = parseOutages(fixture('edlcare_outages_49.json'));
  const work = Place(
    id: 'work',
    name: 'Work',
    area: gampaha,
    point: (lat: 7.0, lon: 79.9),
  );

  NowData now({List<PlaceCuts> places = const []}) => NowData(
    fuel: [
      FuelNow(
        name: 'Petrol 92',
        price: 399,
        since: DateTime(2026, 10, 1),
        was: 412,
      ),
      FuelNow(name: 'Diesel', price: 355, since: DateTime(2026, 10, 1)),
    ],
    fuelAsOf: read,
    rates: [
      RateNow(day: DateTime(2026, 10, 20), rate: 301.2),
      RateNow(day: DateTime(2026, 10, 13), rate: 300),
    ],
    holidays: [
      HolidayNow(day: DateTime(2026, 10, 24), name: 'Deepavali'),
      HolidayNow(day: DateTime(2026, 11, 4), name: 'Il Full Moon Poya Day'),
    ],
    power: PowerNow(places: places, checked: read),
  );

  test('shows the numbers as Today does', () {
    final data = widgetData(now(), today: today);

    expect(data['petrol.value'], '399');
    expect(data['petrol.fall'], '13');
    expect(data['petrol.rise'], isNull);
    expect(data['petrol.note'], 'since 1 Oct');
    // No price before: no change, only when it started.
    expect(data['diesel.value'], '355');
    expect(data['diesel.fall'], isNull);
    expect(data['diesel.rise'], isNull);
    expect(data['usd.value'], '301.20');
    expect(data['usd.rise'], '0.4%');
    expect(data['usd.note'], 'in a week');
    expect(data['asOf'], '${read.millisecondsSinceEpoch}');
  });

  test('gives the holidays ahead, so the widget moves on by itself, with '
      'short Poya names', () {
    final data = widgetData(now(), today: today);

    expect(
      data['holidays'],
      '2026-10-24\tDeepavali\tSat 24 Oct\n'
      '2026-11-04\tIl Poya\tWed 4 Nov',
    );
  });

  test('a power cut line only while a place has a cut', () {
    final at = outagesAt(outages, gampahaHome);

    expect(widgetData(now(), today: today)['cut.title'], isNull);
    final one = widgetData(
      now(
        places: [PlaceCuts(place: home, outages: at)],
      ),
      today: today,
    );
    expect(one['cut.title'], 'Power cut at Home');
    expect(one['cut.note'], 'since 09:24');
    final both = widgetData(
      now(
        places: [
          PlaceCuts(place: home, outages: at),
          PlaceCuts(place: work, outages: at),
        ],
      ),
      today: today,
    );
    expect(both['cut.title'], 'Power cuts at Home and Work');
    expect(both['cut.note'], isNull);
  });

  test('with no cut on now, the line shows the next cut due today', () {
    final cuts = parseCalendar(fixture('edlcare_calendar.json'));
    final data = widgetData(
      now(
        places: [
          PlaceCuts(place: home, ahead: [cuts[1], cuts[2]]),
        ],
      ),
      today: today,
    );

    expect(data['cut.title'], 'Load shedding at Home');
    expect(data['cut.note'], '19:30 to 20:30');
    expect(data['cut.soon'], 'yes');
    expect(data['cut.ends'], '${cuts[1].end.millisecondsSinceEpoch}');
    // Tomorrow's alone isn't due today.
    expect(
      widgetData(
        now(
          places: [
            PlaceCuts(place: home, ahead: [cuts[2]]),
          ],
        ),
        today: today,
      )['cut.title'],
      isNull,
    );
  });

  test('before anything is read, the numbers are dashes', () {
    final data = widgetData(const NowData(), today: today);

    expect(data['petrol.value'], '-');
    expect(data['usd.value'], '-');
    expect(data['holidays'], '');
    expect(data['asOf'], isNull);
  });

  test('a widget tap opens its tab', () {
    expect(tabFromWidget(Uri.parse('lankaradar://prices')), HomeTab.prices);
    expect(tabFromWidget(Uri.parse('lankaradar://power')), HomeTab.power);
    expect(tabFromWidget(Uri.parse('lankaradar://nowhere')), isNull);
    expect(tabFromWidget(Uri.parse('https://prices')), isNull);
    expect(tabFromWidget(null), isNull);
  });
}
