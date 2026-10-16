import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  SearchCubit(this._feed) : super(const SearchState());

  /// Shorter queries show nothing rather than half the feed.
  static const minLength = 2;

  final FeedRepository _feed;

  /// Searches as you type; an answer for a query since replaced is dropped.
  Future<void> search(String query) async {
    emit(SearchState(query: query, results: state.results));
    final results = query.trim().length < minLength
        ? null
        : await _feed.search(query);
    if (!isClosed && state.query == query) {
      emit(SearchState(query: query, results: results));
    }
  }
}
