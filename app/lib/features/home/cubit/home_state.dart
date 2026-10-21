part of 'home_cubit.dart';

final class HomeState extends Equatable {
  const HomeState({
    this.items,
    this.refreshing = false,
    this.failed = false,
    this.topic,
    this.newSince,
    this.nowCard,
    this.health,
    this.gasDistrict = defaultGasDistrict,
    this.wholesaleCentre = defaultWholesaleCentre,
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

  /// Every source's health, for the app bar's warning.
  final Health? health;

  /// The district whose LP gas prices Prices shows.
  final String gasDistrict;

  /// The economic centre whose wholesale vegetable prices Prices shows.
  final String wholesaleCentre;

  List<FeedItem>? get visibleItems => topic == null
      ? items
      : [
          for (final item in items ?? const <FeedItem>[])
            if (item.topic == topic) item,
        ];

  /// How many of the latest items Today lists when nothing is new.
  static const latestOnToday = 5;

  /// What Today lists: what arrived since the last visit, or the latest few when
  /// nothing has. Never election notices, which fold away in Notices, nor the
  /// weekly gazette's vacancies and exams, which alert once a week and are in
  /// Notices and Dates.
  List<FeedItem> get todayItems {
    final notices = [
      for (final item in items ?? const <FeedItem>[])
        if (_onToday(item)) item,
    ];
    final fresh = [
      for (final item in notices)
        if (isNew(item)) item,
    ];
    return fresh.isNotEmpty ? fresh : notices.take(latestOnToday).toList();
  }

  /// Whether Today lists new items rather than the latest ones.
  bool get todayHasNew => (items ?? const <FeedItem>[]).any(
    (item) => _onToday(item) && isNew(item),
  );

  static bool _onToday(FeedItem item) =>
      !isElectionNotice(item) && item.source != 'weekly';

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
    Health? health,
    String? gasDistrict,
    String? wholesaleCentre,
  }) => HomeState(
    items: items ?? this.items,
    refreshing: refreshing ?? this.refreshing,
    failed: failed ?? this.failed,
    topic: topic != null ? topic() : this.topic,
    newSince: newSince != null ? newSince() : this.newSince,
    nowCard: nowCard ?? this.nowCard,
    health: health ?? this.health,
    gasDistrict: gasDistrict ?? this.gasDistrict,
    wholesaleCentre: wholesaleCentre ?? this.wholesaleCentre,
  );

  @override
  List<Object?> get props => [
    items,
    refreshing,
    failed,
    topic,
    newSince,
    nowCard,
    health,
    gasDistrict,
    wholesaleCentre,
  ];
}
