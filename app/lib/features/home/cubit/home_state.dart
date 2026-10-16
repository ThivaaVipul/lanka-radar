part of 'home_cubit.dart';

final class HomeState extends Equatable {
  const HomeState({this.items, this.refreshing = false, this.failed = false});

  /// Null until the database first answers.
  final List<FeedItem>? items;
  final bool refreshing;

  /// The last refresh failed.
  final bool failed;

  HomeState copyWith({List<FeedItem>? items, bool? refreshing, bool? failed}) =>
      HomeState(
        items: items ?? this.items,
        refreshing: refreshing ?? this.refreshing,
        failed: failed ?? this.failed,
      );

  @override
  List<Object?> get props => [items, refreshing, failed];
}
