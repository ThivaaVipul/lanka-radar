import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

part 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._feed, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const HomeState());

  /// Opening the app refreshes when the last refresh is older than this.
  static const staleAfter = Duration(minutes: 15);

  final FeedRepository _feed;
  final DateTime Function() _now;
  StreamSubscription<List<FeedItem>>? _items;

  /// Shows the stored items as they change, marks what arrived since the last
  /// visit, and refreshes if the feed is stale.
  Future<void> watch() async {
    final since = await _feed.lastVisit();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(newSince: () => since));
    _items = _feed.watchItems().listen(
      (items) => emit(state.copyWith(items: items)),
    );
    await _refresh(() => _feed.refreshIfStale(staleAfter));
  }

  /// Pull to refresh.
  Future<void> refresh() => _refresh(_feed.refresh);

  void showTopic(String? topic) => emit(state.copyWith(topic: () => topic));

  /// Leaving the feed: what is on it now stops being new.
  Future<void> leave() => _feed.saveVisit(_now());

  /// Coming back: only what arrives from now on is new, and a stale feed
  /// refreshes.
  Future<void> resume() async {
    final since = await _feed.lastVisit();
    if (isClosed) {
      return;
    }
    emit(state.copyWith(newSince: () => since));
    await _refresh(() => _feed.refreshIfStale(staleAfter));
  }

  Future<void> _refresh(Future<void> Function() run) async {
    emit(state.copyWith(refreshing: true, failed: false));
    var failed = false;
    try {
      await run();
    } on Exception {
      // The items already shown stay; only an empty feed turns into an error.
      failed = true;
    }
    if (!isClosed) {
      emit(state.copyWith(refreshing: false, failed: failed));
    }
  }

  @override
  Future<void> close() async {
    await _items?.cancel();
    return super.close();
  }
}
