part of 'search_cubit.dart';

final class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.results,
    this.only,
    this.recent = const [],
  });

  final String query;

  /// Null while there is no query long enough to search.
  final SearchResults? results;

  /// The one group shown, after its header was tapped; null for all.
  final SearchGroup? only;

  /// The last searches, newest first.
  final List<String> recent;

  /// The query's words, for highlighting matches.
  List<String> get words => searchWords(query);

  SearchState copyWith({
    String? query,
    SearchResults? Function()? results,
    SearchGroup? Function()? only,
    List<String>? recent,
  }) => SearchState(
    query: query ?? this.query,
    results: results != null ? results() : this.results,
    only: only != null ? only() : this.only,
    recent: recent ?? this.recent,
  );

  @override
  List<Object?> get props => [query, results, only, recent];
}
