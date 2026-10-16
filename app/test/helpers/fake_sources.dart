import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';

/// A saved response from test/fixtures, byte for byte.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// CEYPETCO and CBSL in memory, answering with the responses saved in M1
/// unless told to fail.
class FakeSources {
  String ceypetco = fixture('ceypetco_fuel_prices.json');
  String cbsl = fixture('cbsl_usd_rates.html');
  bool offline = false;
  final requests = <String>[];

  http.Client get client => MockClient((request) async {
    if (offline) {
      throw http.ClientException('offline', request.url);
    }
    requests.add(request.url.host);
    final body = switch (request.url.host) {
      'api.ceypetco.gov.lk' => ceypetco,
      'www.cbsl.gov.lk' => cbsl,
      _ => null,
    };
    return body == null
        ? http.Response('', 404)
        : http.Response.bytes(utf8.encode(body), 200);
  });

  NowRepository repository(AppDatabase database, {DateTime Function()? now}) =>
      NowRepository(
        database: database,
        ceypetco: Ceypetco(client: client),
        cbsl: Cbsl(client: client),
        now: now,
        tamilNames: () async => const {'Deepavali': 'TA Deepavali'},
      );
}
