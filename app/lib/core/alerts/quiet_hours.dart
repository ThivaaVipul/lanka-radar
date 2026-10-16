import 'package:equatable/equatable.dart';

/// When alerts wait, in minutes after midnight: from [start] to [end], across
/// midnight when the end comes first. What a sync finds then goes out with the
/// first sync after the end.
final class QuietHours extends Equatable {
  const QuietHours({this.on = true, this.start = 22 * 60, this.end = 6 * 60});

  final bool on;
  final int start;
  final int end;

  /// Whether alerts found at [time] wait.
  bool holds(DateTime time) {
    if (!on || start == end) {
      return false;
    }
    final minute = time.hour * 60 + time.minute;
    return start < end
        ? minute >= start && minute < end
        : minute >= start || minute < end;
  }

  QuietHours copyWith({bool? on, int? start, int? end}) => QuietHours(
    on: on ?? this.on,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  @override
  List<Object?> get props => [on, start, end];
}
