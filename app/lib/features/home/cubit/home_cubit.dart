import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

part 'home_state.dart';

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._feed) : super(const HomeState());

  /// Opening the app refreshes when the last refresh is older than this.
  static const staleAfter = Duration(minutes: 15);

  final FeedRepository _feed;
  StreamSubscription<List<FeedItem>>? _items;

  /// Shows the stored items as they change, and refreshes if they are stale.
  void watch() {
    _items = _feed.watchItems().listen(
      (items) => emit(state.copyWith(items: items)),
    );
    unawaited(_refresh(() => _feed.refreshIfStale(staleAfter)));
  }

  /// Pull to refresh.
  Future<void> refresh() => _refresh(_feed.refresh);

  Future<void> _refresh(Future<void> Function() run) async {
    emit(state.copyWith(refreshing: true, failed: false));
    try {
      await run();
      emit(state.copyWith(refreshing: false));
    } on Exception {
      // The items already shown stay; only an empty feed turns into an error.
      emit(state.copyWith(refreshing: false, failed: true));
    }
  }

  @override
  Future<void> close() async {
    await _items?.cancel();
    return super.close();
  }
}
