import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/price_history.dart';

/// What a chart is about.
sealed class ChartSubject extends Equatable {
  const ChartSubject();

  String get title;

  /// Prices set on a day hold until the next one; a rate moves every day.
  bool get steps => true;

  /// Where the numbers come from, under the title.
  String get source;
}

final class FuelChart extends ChartSubject {
  const FuelChart(this.name);

  final String name;

  @override
  String get title => name;

  @override
  String get source => 'CEYPETCO and fuel price gazettes';

  @override
  List<Object?> get props => [name];
}

final class RateChart extends ChartSubject {
  const RateChart();

  @override
  String get title => 'USD/LKR';

  @override
  bool get steps => false;

  @override
  String get source => 'Central Bank of Sri Lanka';

  @override
  List<Object?> get props => [];
}

final class GoodChart extends ChartSubject {
  const GoodChart(this.name);

  final String name;

  @override
  String get title => name;

  @override
  String get source => 'Price orders in the gazette';

  @override
  List<Object?> get props => [name];
}

/// How far back a rate chart looks.
enum ChartRange {
  month('1M', 30),
  quarter('3M', 91),
  year('Since Jan', null);

  const ChartRange(this.label, this.days);

  final String label;

  /// Null for everything since January.
  final int? days;
}

final class PriceChartState extends Equatable {
  const PriceChartState({this.points, this.range = ChartRange.quarter});

  /// Every point, oldest first; null until loaded.
  final List<PricePoint>? points;
  final ChartRange range;

  /// The points the chart shows: a rate's within the range, a price's all.
  List<PricePoint> shown(ChartSubject subject, DateTime today) {
    final all = points ?? const <PricePoint>[];
    final days = range.days;
    if (subject.steps || days == null || all.isEmpty) {
      return all;
    }
    return since(all, today.subtract(Duration(days: days)));
  }

  @override
  List<Object?> get props => [points, range];
}

class PriceChartCubit extends Cubit<PriceChartState> {
  PriceChartCubit(this._feed, this._phone, this.subject)
    : super(const PriceChartState());

  final FeedRepository _feed;
  final NowRepository _phone;
  final ChartSubject subject;

  Future<void> load() async {
    final items = await _feed.watchItems().first;
    final points = switch (subject) {
      FuelChart(:final name) => fuelHistory(
        name,
        await _phone.fuelRows(),
        items,
      ),
      RateChart() => rateHistory(
        await _phone.datasetRates(),
        await _phone.allRates(),
      ),
      GoodChart(:final name) => goodsHistory(items)[name] ?? const [],
    };
    if (!isClosed) {
      emit(PriceChartState(points: points, range: state.range));
    }
  }

  void showRange(ChartRange range) =>
      emit(PriceChartState(points: state.points, range: range));
}
