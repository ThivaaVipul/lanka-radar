/// The workflow's USD/LKR move items (`rates.py` in the scrapers), which the
/// phone also makes from CBSL's same-day rates so a big move alerts the day it
/// happens. Same rule and same IDs, so whichever copy arrives first wins.
library;

import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';

const _move = 0.02;
const _week = Duration(days: 7);

/// A rate 2% or more away from the rate a week earlier.
final class RateMove extends Equatable {
  const RateMove({
    required this.day,
    required this.rate,
    required this.weekAgo,
  });

  /// yyyy-MM-dd
  final String day;
  final double rate;
  final double weekAgo;

  double get change => rate / weekAgo - 1;

  @override
  List<Object?> get props => [day, rate, weekAgo];
}

/// Days where the rate is 2% or more away from a week earlier, at most one a
/// week, from rates by day (yyyy-MM-dd).
List<RateMove> weeklyMoves(Map<String, double> rates) {
  final days = rates.keys.toList()..sort();
  final moves = <RateMove>[];
  // The last day a week or more before the day being looked at.
  var before = -1;
  for (var index = 0; index < days.length; index++) {
    final day = _utc(days[index]);
    while (before + 1 < index &&
        !_utc(days[before + 1]).isAfter(day.subtract(_week))) {
      before++;
    }
    if (before < 0) {
      continue;
    }
    final move = RateMove(
      day: days[index],
      rate: rates[days[index]]!,
      weekAgo: rates[days[before]]!,
    );
    if (move.change.abs() >= _move &&
        (moves.isEmpty || day.difference(_utc(moves.last.day)) >= _week)) {
      moves.add(move);
    }
  }
  return moves;
}

/// The feed item for [move], as the workflow writes it.
Map<String, Object?> moveItem(RateMove move) {
  final direction = move.change > 0 ? 'up' : 'down';
  final percent = (move.change.abs() * 100).toStringAsFixed(1);
  return {
    'id': 'rates-usd-lkr-${move.day}',
    'source': 'rates',
    'topic': 'rates',
    'issuer': 'Central Bank of Sri Lanka',
    'headline': {
      'en':
          'USD/LKR $direction $percent% in a week, to '
          '${move.rate.toStringAsFixed(2)}',
      'ta': null,
    },
    'keyNumbers': [
      {
        'label': 'USD/LKR',
        'value': move.rate,
        'unit': 'LKR',
        'previous': move.weekAgo,
      },
    ],
    'published': move.day,
    'effective': null,
    'links': {'page': Cbsl.page},
    'data': {'change': double.parse(move.change.toStringAsFixed(4))},
    'alert': true,
  };
}

/// The rates in the workflow's `datasets/usd-lkr.json`, by day.
Map<String, double> datasetRates(String? body) {
  if (body == null) {
    return const {};
  }
  final json = jsonDecode(body) as Map<String, Object?>;
  return {
    for (final entry in json['rates'] as List<Object?>? ?? const [])
      if (entry case {'date': final String day, 'rate': final num rate})
        day: rate.toDouble(),
  };
}

DateTime _utc(String day) => DateTime.parse('${day}T00:00:00Z');
