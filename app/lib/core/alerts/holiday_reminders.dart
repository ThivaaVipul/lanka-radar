import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/dates.dart';

/// Holiday reminders go out at about this hour the evening before, Sri Lanka
/// time; Android may send them a little late to save battery.
const reminderHour = 19;

/// A reminder the evening before a public holiday.
final class HolidayReminder extends Equatable {
  const HolidayReminder(this.holiday);

  final HolidayNow holiday;

  /// When it goes out, as a time of day in Sri Lanka.
  DateTime get at => DateTime(
    holiday.day.year,
    holiday.day.month,
    holiday.day.day - 1,
    reminderHour,
  );

  /// Stays the same for a holiday, so scheduling it again replaces it.
  String get key => 'holiday-${isoDay(holiday.day)}-${holiday.name}';

  String get title => 'Holiday tomorrow';

  /// The name, marked when the date is tentative, then the Tamil name.
  String get body => [
    if (holiday.tentative) '${holiday.name} (tentative)' else holiday.name,
    ?holiday.tamil,
  ].join('\n');

  @override
  List<Object?> get props => [holiday];
}

/// A reminder for each of [holidays] whose evening before is still to come.
List<HolidayReminder> holidayReminders(
  List<HolidayNow> holidays, {
  required DateTime now,
}) => [
  for (final holiday in holidays)
    if (HolidayReminder(holiday).at.isAfter(now)) HolidayReminder(holiday),
];
