import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/health.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/features/home/notice_rows.dart';

part 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._feed, this._phone, this._alerts, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const HomeState());

  /// Opening the app refreshes when the last refresh is older than this.
  static const staleAfter = Duration(minutes: 15);

  final FeedRepository _feed;
  final NowRepository _phone;
  final AlertsRepository _alerts;
  final DateTime Function() _now;
  StreamSubscription<List<FeedItem>>? _items;

  /// Shows the stored items as they change, marks what arrived since the last
  /// visit, and refreshes if the feed is stale.
  Future<void> watch() async {
    await _alerts.appShown(_now());
    final since = await _feed.lastVisit();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(newSince: () => since));
    _items = _feed.watchItems().listen((items) {
      emit(state.copyWith(items: items));
      unawaited(_loadNowCard());
    });
    await _refreshIfStale();
  }

  /// Pull to refresh: the feed and the sources the phone reads itself.
  Future<void> refresh() => _refresh(_feed.refresh, _phone.refresh);

  void showTopic(String? topic) => emit(state.copyWith(topic: () => topic));

  /// Leaving the feed: what is on it now stops being new, and background syncs
  /// may alert again.
  Future<void> leave() async {
    await _feed.saveVisit(_now());
    await _alerts.appHidden();
  }

  /// Coming back: only what arrives from now on is new, and a stale feed
  /// refreshes.
  Future<void> resume() async {
    await _alerts.appShown(_now());
    // A background sync may have stored items this screen hasn't seen.
    _feed.notifyExternalChanges();
    final since = await _feed.lastVisit();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(newSince: () => since));
    await _refreshIfStale();
  }

  Future<void> _refreshIfStale() => _refresh(
    () => _feed.refreshIfStale(staleAfter),
    () => _phone.refreshIfStale(staleAfter),
  );

  Future<void> _refresh(
    Future<void> Function() feed,
    Future<void> Function() phone,
  ) async {
    emit(state.copyWith(refreshing: true, failed: false));
    var failed = false;
    try {
      await feed();
    } on Exception {
      // The items already shown stay; only an empty feed turns into an error.
      failed = true;
    }
    try {
      await phone();
    } on Exception {
      // CEYPETCO and CBSL record their own failures, and the Now card shows
      // the age of what it has; the feed's state is about the feed.
    }
    await _feed.updatePhoneItems();
    try {
      await _alerts.remindHolidays(
        await _phone.upcomingHolidays(),
        now: _now(),
      );
    } on Exception {
      // Scheduled again after the next refresh.
    }
    if (isClosed) {
      return;
    }
    emit(state.copyWith(refreshing: false, failed: failed));
    await _loadNowCard();
    if (!failed && (state.items?.isNotEmpty ?? false)) {
      // After the first sync that brings a feed, once.
      await _alerts.askPermissionOnce();
    }
  }

  Future<void> _loadNowCard() async {
    final card = await _phone.load(state.items ?? const []);
    final health = await _phone.health();
    if (!isClosed) {
      emit(state.copyWith(nowCard: card, health: health));
    }
  }

  @override
  Future<void> close() async {
    await _items?.cancel();
    return super.close();
  }
}
