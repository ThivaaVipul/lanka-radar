part of 'home_cubit.dart';

final class HomeState extends Equatable {
  const HomeState({
    this.items,
    this.refreshing = false,
    this.failed = false,
    this.topic,
    this.newSince,
    this.nowCard,
  });

  /// How far back a new item may have been published: history filling in is
  /// never marked new.
  static const newWithin = Duration(days: 14);

  /// Null until the database first answers.
  final List<FeedItem>? items;
  final bool refreshing;

  /// The last refresh failed.
  final bool failed;

  /// The topic chip chosen; null for All.
  final String? topic;

  /// When the feed was last left: items that arrived after it are new. Null on a
  /// fresh install, when nothing is marked.
  final DateTime? newSince;

  /// The Now card's values; null until first loaded.
  final NowData? nowCard;

  List<FeedItem>? get visibleItems => topic == null
      ? items
      : [
          for (final item in items ?? const <FeedItem>[])
            if (item.topic == topic) item,
        ];

  bool isNew(FeedItem item) {
    final since = newSince;
    final seen = item.firstSeen;
    return since != null &&
        seen != null &&
        seen.isAfter(since) &&
        item.published.isAfter(since.subtract(newWithin));
  }

  HomeState copyWith({
    List<FeedItem>? items,
    bool? refreshing,
    bool? failed,
    String? Function()? topic,
    DateTime? Function()? newSince,
    NowData? nowCard,
  }) => HomeState(
    items: items ?? this.items,
    refreshing: refreshing ?? this.refreshing,
    failed: failed ?? this.failed,
    topic: topic != null ? topic() : this.topic,
    newSince: newSince != null ? newSince() : this.newSince,
    nowCard: nowCard ?? this.nowCard,
  );

  @override
  List<Object?> get props => [
    items,
    refreshing,
    failed,
    topic,
    newSince,
    nowCard,
  ];
}
