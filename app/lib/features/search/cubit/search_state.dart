part of 'search_cubit.dart';

final class SearchState extends Equatable {
  const SearchState({this.query = '', this.results});

  final String query;

  /// Null while there is no query long enough to search.
  final List<FeedItem>? results;

  @override
  List<Object?> get props => [query, results];
}
