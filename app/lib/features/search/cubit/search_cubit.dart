import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/wholesale_prices.dart';
import 'package:lanka_radar/features/search/search_results.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit(this._feed, this._phone) : super(const SearchState());

  /// Shorter queries show the suggestions rather than half the feed.
  static const minLength = 2;

  final FeedRepository _feed;
  final NowRepository _phone;

  /// The prices and holidays to match, read once when search opens.
  NowData? _now;
  List<HolidayNow> _holidays = const [];
  String _centre = defaultWholesaleCentre;

  Future<void> load() async {
    final recent = await _feed.recentSearches();
    _now = await _phone.load(await _feed.watchItems().first);
    _holidays = await _phone.upcomingHolidays();
    _centre = await _feed.wholesaleCentre();
    if (!isClosed) {
      emit(state.copyWith(recent: recent));
    }
  }

  /// Searches as you type; an answer for a query since replaced is dropped.
  Future<void> search(String query) async {
    emit(state.copyWith(query: query, results: () => state.results));
    final words = searchWords(query);
    if (query.trim().length < minLength || words.isEmpty) {
      emit(state.copyWith(results: () => null, only: () => null));
      return;
    }
    final notices = await _feed.search(query);
    final results = searchEverything(
      words: words,
      notices: notices,
      inside: await _feed.searchInside(
        query,
        excluding: {for (final item in notices) item.id},
      ),
      now: _now,
      holidays: _holidays,
      wholesaleCentre: _centre,
    );
    if (!isClosed && state.query == query) {
      emit(state.copyWith(results: () => results));
    }
  }

  /// Shows only [group], or every group again.
  void showOnly(SearchGroup? group) => emit(state.copyWith(only: () => group));

  /// Remembers the query being looked at, for the recent searches.
  Future<void> remember() async {
    await _feed.rememberSearch(state.query);
    final recent = await _feed.recentSearches();
    if (!isClosed) {
      emit(state.copyWith(recent: recent));
    }
  }

  Future<void> forget(String query) async {
    await _feed.forgetSearch(query);
    final recent = await _feed.recentSearches();
    if (!isClosed) {
      emit(state.copyWith(recent: recent));
    }
  }
}
