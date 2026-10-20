import 'package:android_intent_plus/android_intent.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

/// An all-day event, one day or several, for the phone's calendar.
final class CalendarEvent extends Equatable {
  const CalendarEvent({
    required this.title,
    required this.first,
    required this.last,
    this.description,
  });

  final String title;
  final DateTime first;
  final DateTime last;
  final String? description;

  @override
  List<Object?> get props => [title, first, last, description];
}

/// Opens the phone's calendar app with an event filled in, for the user to
/// save. False when no calendar app took it.
typedef AddToCalendar = Future<bool> Function(CalendarEvent event);

/// Android's insert-event screen; no calendar permission needed, since the
/// calendar app saves it.
Future<bool> addToPhoneCalendar(CalendarEvent event) async {
  try {
    await calendarIntent(event).launch();
    return true;
  } on PlatformException {
    return false;
  }
}

/// The intent that opens a calendar app's new-event screen with [event].
AndroidIntent calendarIntent(CalendarEvent event) {
  final first = event.first;
  final last = event.last;
  return AndroidIntent(
    action: 'android.intent.action.INSERT',
    data: 'content://com.android.calendar/events',
    arguments: <String, dynamic>{
      'title': event.title,
      'description': ?event.description,
      'allDay': true,
      // All-day events run from midnight UTC to midnight after the last day.
      'beginTime': DateTime.utc(
        first.year,
        first.month,
        first.day,
      ).millisecondsSinceEpoch,
      'endTime': DateTime.utc(
        last.year,
        last.month,
        last.day + 1,
      ).millisecondsSinceEpoch,
    },
  );
}
