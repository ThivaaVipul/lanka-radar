import 'dart:convert';

import 'package:http/http.dart' as http;

/// A file read from the data branch, with its ETag for the next request.
typedef Fetched = ({String body, String? etag});

/// Reads the workflow's `data` branch from raw.githubusercontent.com: public, no
/// token. Unchanged files answer 304, so a refresh downloads only what changed.
class DataBranch {
  DataBranch({http.Client? client, Uri? base})
    : _client = client ?? http.Client(),
      _base = base ?? defaultBase;

  static final defaultBase = Uri.parse(
    'https://raw.githubusercontent.com/ThivaaVipul/lanka-radar/data/',
  );

  final http.Client _client;
  final Uri _base;

  /// The file at [path], or null when it is unchanged since [etag].
  Future<Fetched?> get(String path, {String? etag}) async {
    final response = await _client.get(
      _base.resolve(path),
      headers: {'If-None-Match': ?etag},
    );
    if (response.statusCode == 304) {
      return null;
    }
    if (response.statusCode != 200) {
      throw DataBranchException(path, response.statusCode);
    }
    return (
      body: utf8.decode(response.bodyBytes),
      etag: response.headers['etag'],
    );
  }

  void close() => _client.close();
}

class DataBranchException implements Exception {
  const DataBranchException(this.path, this.statusCode);

  final String path;
  final int statusCode;

  @override
  String toString() => 'DataBranchException: $path answered $statusCode';
}
