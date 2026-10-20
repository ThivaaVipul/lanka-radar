import 'package:home_widget/home_widget.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/format/outages.dart';

/// The home-screen widget. The app works out what it shows and saves it where
/// the widget's Android side reads it (`RadarWidget.kt`), which only draws.
class HomeScreenWidget {
  const HomeScreenWidget();

  /// The widget's provider on Android.
  static const provider = 'app.lankaradar.RadarWidget';

  /// Shows [now] on the widget. A widget that can't be reached never fails
  /// what called it.
  Future<void> show(NowData now) async {
    try {
      final data = widgetData(now, today: DateTime.now());
      for (final MapEntry(:key, :value) in data.entries) {
        await HomeWidget.saveWidgetData<String>(key, value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: provider);
    } on Exception {
      // No widget plugin here (tests), or nothing to update.
    }
  }

  /// The link of the widget tap that started the app, if one did.
  static Future<Uri?> launchedWith() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } on Exception {
      return null;
    }
  }

  /// The links of widget taps while the app is running.
  static Stream<Uri?> get taps => HomeWidget.widgetClicked;
}

/// What the widget shows, by the keys its Android side reads: Petrol 92,
/// Diesel and USD/LKR as on Today (the value, a rise or a fall and by how
/// much, and a note), the holidays ahead (so it moves on to the next by
/// itself), a line for a power cut at a place, and when the fuel prices were
/// read. A null value clears its key.
Map<String, String?> widgetData(NowData now, {required DateTime today}) {
  Map<String, String?> number(
    String key, {
    required String? value,
    double? change,
    String? by,
    String? note,
  }) => {
    '$key.value': value ?? '-',
    '$key.rise': change != null && change > 0 ? by : null,
    '$key.fall': change != null && change < 0 ? by : null,
    '$key.note': note,
  };

  Map<String, String?> fuel(String key, String name) {
    final price = now.fuel.where((price) => price.name == name).firstOrNull;
    final was = price?.was;
    return number(
      key,
      value: price == null ? null : amount(price.price),
      change: price == null || was == null ? null : price.price - was,
      by: price == null || was == null
          ? null
          : amount((price.price - was).abs()),
      note: price == null
          ? null
          : 'since ${cardDate(price.since, today: today)}',
    );
  }

  final rate = now.rates.firstOrNull;
  final move = weekMove(now.rates);
  final cut = now.power?.cut ?? const <PlaceCuts>[];
  final outages = [for (final cuts in cut) ...cuts.outages];
  final (place, soon) =
      cutsAhead(
        now.power,
        before: DateTime(today.year, today.month, today.day + 1),
      ).firstOrNull ??
      (null, null);
  String at(DateTime time) => clock(time.hour * 60 + time.minute);
  return {
    ...fuel('petrol', 'Petrol 92'),
    ...fuel('diesel', 'Diesel'),
    ...number(
      'usd',
      value: rate == null ? null : amount(rate.rate),
      change: move,
      by: move == null ? null : '${move.abs().toStringAsFixed(1)}%',
      note: move == null ? null : 'in a week',
    ),
    // One a line: the day, the name, the day as shown. A cell has one line
    // for the name, so "Vap Full Moon Poya Day" says "Vap Poya".
    'holidays': [
      for (final holiday in now.holidays.take(5))
        [
          isoDay(holiday.day),
          holiday.name.replaceFirst(' Full Moon Poya Day', ' Poya'),
          weekdayDate(holiday.day),
        ].join('\t'),
    ].join('\n'),
    // A cut on now, else the next one due today, which the widget hides once
    // it is over.
    'cut.title': cut.isNotEmpty
        ? cutPlacesTitle(cut)
        : soon == null
        ? null
        : '${soon.name} at ${place!.name}',
    'cut.note': cut.isNotEmpty
        ? (outages.length == 1 ? outageWhen(outages.single) : null)
        : soon == null
        ? null
        : '${at(soon.start)} to ${at(soon.end)}',
    'cut.soon': cut.isEmpty && soon != null ? 'yes' : null,
    'cut.ends': cut.isEmpty && soon != null
        ? soon.end.millisecondsSinceEpoch.toString()
        : null,
    'asOf': now.fuelAsOf?.millisecondsSinceEpoch.toString(),
  };
}
