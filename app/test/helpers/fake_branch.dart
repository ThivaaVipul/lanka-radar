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
  String? group,
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
  'data': {'number': ?number, 'group': ?group},
  'alert': true,
};

/// A weekly gazette notice as the workflow writes it: a vacancy (jobs) or an
/// examination (exams) of the gazette of [week].
Map<String, Object?> notice(
  String id,
  String week, {
  String topic = 'jobs',
  String headline = 'Post of Registrar of Marriages',
  String? closes,
  int page = 4,
}) => {
  ...item(
    id,
    week,
    topic: topic,
    headline: headline,
    issuer: 'Registrar General',
  ),
  'source': 'weekly',
  'links': {
    'page': 'https://documents.gov.lk/web/gazettes',
    'pdf_en': 'https://documents.gov.lk/api/content-file-proxy?file=/iia.pdf',
  },
  'data': {
    'week': week,
    'section': topic == 'jobs' ? 'vacancies' : 'exams',
    'page': page,
    'closes': ?closes,
  },
  'alert': false,
};

/// A Litro price list read off its image: Colombo's prices as its key numbers,
/// and [districts]' (12.5 kg, 5 kg, 2.3 kg) in its data.
Map<String, Object?> gasList(String day, Map<String, List<num>> districts) => {
  ...item(
    'gas-litro-$day',
    day,
    topic: 'prices',
    headline: 'Litro gas prices',
    issuer: 'Litro Gas Lanka',
  ),
  'source': 'gas',
  'effective': day,
  'links': {'image': 'https://www.litrogas.com/list-$day.webp'},
  'keyNumbers': [
    for (final (index, size) in ['12.5 kg', '5 kg', '2.3 kg'].indexed)
      {'label': size, 'value': districts['Colombo']![index], 'unit': 'LKR'},
  ],
  'data': {
    'sizes': ['12.5 kg', '5 kg', '2.3 kg'],
    'districts': districts,
    'district': 'Colombo',
  },
};

/// The data branch in memory. Each file's ETag follows its content, a matching
/// If-None-Match gets 304, and every request is recorded.
class FakeBranch {
  FakeBranch() {
    files['datasets/holidays.json'] = '{"schema": 1, "holidays": []}';
    files['datasets/usd-lkr.json'] = '{"schema": 1, "rates": []}';
    files['status.json'] = '{"schema": 1, "sources": {}}';
    files['datasets/laugfs-gas.json'] = jsonEncode({
      'schema': 1,
      'sizes': ['12.5 kg', '5 kg', '2 kg'],
      'prices': {
        'Colombo': [4965, 1988, 795],
        'Jaffna': [5336, 2210, 888],
      },
      'since': null,
      'before': null,
    });
    _writeIndex();
    _writeTextsIndex();
  }

  final files = <String, String>{};
  final requests = <String>[];
  final unchanged = <String>[];
  final _months = <String, List<Map<String, Object?>>>{};
  final _texts = <String, Map<String, String>>{};
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

  /// A month of gazette text, by item ID.
  void putTexts(String month, Map<String, String> texts) {
    _texts[month] = texts;
    files['texts/$month.json'] = jsonEncode({
      'schema': 1,
      'month': month,
      'texts': texts,
    });
    _writeTextsIndex();
  }

  void _writeTextsIndex() {
    final months = _texts.keys.toList()..sort((a, b) => b.compareTo(a));
    files['texts/index.json'] = jsonEncode({
      'schema': 1,
      'months': [
        for (final month in months)
          {
            'month': month,
            'count': _texts[month]!.length,
            'hash': _etag(files['texts/$month.json']!),
          },
      ],
    });
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
