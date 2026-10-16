import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';

/// An empty database in memory.
AppDatabase memoryDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// A feed item as the workflow writes it.
Map<String, Object?> item(
  String id,
  String published, {
  String topic = 'gazettes',
  String headline = 'A headline',
  String? tamil,
  String? issuer = 'Election Commission',
  String? number,
}) => {
  'id': id,
  'source': 'gazettes',
  'topic': topic,
  'issuer': issuer,
  'headline': {'en': headline, 'ta': tamil},
  'keyNumbers': <Object?>[],
  'published': published,
  'effective': null,
  'links': {'page': 'https://documents.gov.lk/web/extra_gazettes'},
  'data': {'number': ?number},
  'alert': true,
};

/// The data branch in memory. Each file's ETag follows its content, a matching
/// If-None-Match gets 304, and every request is recorded.
class FakeBranch {
  FakeBranch() {
    files['datasets/holidays.json'] = '{"schema": 1, "holidays": []}';
    files['datasets/usd-lkr.json'] = '{"schema": 1, "rates": []}';
    files['status.json'] = '{"schema": 1, "sources": {}}';
    _writeIndex();
  }

  final files = <String, String>{};
  final requests = <String>[];
  final unchanged = <String>[];
  final _months = <String, List<Map<String, Object?>>>{};
  bool offline = false;

  DataBranch get branch => DataBranch(
    client: MockClient(_answer),
    base: Uri.parse('https://data.test/data/'),
  );

  void putMonth(String month, List<Map<String, Object?>> items) {
    _months[month] = items;
    files['months/$month.json'] = jsonEncode({
      'schema': 1,
      'month': month,
      'items': items,
    });
    _writeIndex();
  }

  void dropMonth(String month) {
    _months.remove(month);
    files.remove('months/$month.json');
    _writeIndex();
  }

  void _writeIndex() {
    final months = _months.keys.toList()..sort((a, b) => b.compareTo(a));
    files['months/index.json'] = jsonEncode({
      'schema': 1,
      'months': [
        for (final month in months)
          {
            'month': month,
            'count': _months[month]!.length,
            'hash': _etag(files['months/$month.json']!),
          },
      ],
    });
  }

  Future<http.Response> _answer(http.Request request) async {
    if (offline) {
      throw http.ClientException('offline', request.url);
    }
    final path = request.url.path.substring('/data/'.length);
    requests.add(path);
    final body = files[path];
    if (body == null) {
      return http.Response('404: Not Found', 404);
    }
    final etag = _etag(body);
    if (request.headers['If-None-Match'] == etag) {
      unchanged.add(path);
      return http.Response('', 304);
    }
    return http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'etag': etag, 'content-type': 'text/plain; charset=utf-8'},
    );
  }

  static String _etag(String body) => '"${body.hashCode.toRadixString(16)}"';
}
