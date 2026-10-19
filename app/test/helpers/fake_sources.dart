import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/market_report.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:pdfrx/pdfrx.dart';

/// A saved response from test/fixtures, byte for byte.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A saved response from test/fixtures as bytes.
List<int> fixtureBytes(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

/// Reads a price report's characters with PDFium, as the app does.
Future<List<ReportChar>> readReport(Uint8List pdf) async {
  await pdfrxInitialize(
    tmpPath: Directory.systemTemp.createTempSync('pdfrx').path,
  );
  return reportChars(pdf);
}

/// CEYPETCO and CBSL in memory, answering with the responses saved in M1
/// unless told to fail. CBSL's price report listing is empty unless given,
/// and of the reports only the ones in [reports] are there.
class FakeSources {
  String ceypetco = fixture('ceypetco_fuel_prices.json');
  String cbsl = fixture('cbsl_usd_rates.html');
  String marketListing = '<html></html>';
  final reports = <String, List<int>>{};
  bool offline = false;
  final requests = <String>[];

  /// The paths of the requests to CBSL's price reports and their listing.
  final marketRequests = <String>[];

  http.Client get client => MockClient((request) async {
    if (offline) {
      throw http.ClientException('offline', request.url);
    }
    requests.add(request.url.host);
    final path = request.url.path;
    if (request.url.host == 'www.cbsl.gov.lk' && path.contains('price')) {
      marketRequests.add(path.split('/').last);
    }
    if (path.contains('/pricerpt/')) {
      final pdf = reports[path.split('/').last];
      return pdf == null
          ? http.Response('', 404)
          : http.Response.bytes(pdf, 200);
    }
    final body = switch (request.url.host) {
      'api.ceypetco.gov.lk' => ceypetco,
      'www.cbsl.gov.lk' when path.endsWith('/price-report') => marketListing,
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
        market: CbslMarket(client: client, read: readReport),
        now: now,
        tamilNames: () async => const {'Deepavali': 'TA Deepavali'},
      );
}

/// Market prices from two reports, as the phone keeps them: beans everywhere, imported red onions not at Narahenpita, thalapath only at
/// Negombo, balaya not in the latest report, and samba.
const marketDataset = '''
{
  "days": ["2026-10-16", "2026-10-19"],
  "items": [
    {"name": "Beans", "unit": "kg", "section": "Vegetables",
     "prices": {"Pettah": [600, 600], "Dambulla": [430, 430],
                "Narahenpita": [650, 700]}},
    {"name": "Red Onion (Imp)", "unit": "kg", "section": "Other",
     "prices": {"Pettah": [440, 450], "Narahenpita": [null, null]}},
    {"name": "Egg (White)", "unit": "each", "section": "Other",
     "prices": {"Pettah": [36, 36], "Narahenpita": [37, 37]}},
    {"name": "Thalapath", "unit": "kg", "section": "Fish",
     "prices": {"Negombo": [2100, 2100]}},
    {"name": "Balaya", "unit": "kg", "section": "Fish",
     "prices": {"Negombo": [1500, null]}},
    {"name": "Samba", "unit": "kg", "section": "Rice",
     "prices": {"Pettah": [240, 240], "Narahenpita": [240, 240]}}
  ]
}
''';

/// Stores [marketDataset] as the market prices the phone has read.
Future<void> storeMarketPrices(AppDatabase database) => database.saveFile(
  FileRow(
    path: NowRepository.marketPath,
    body: marketDataset,
    fetchedAt: DateTime(2026, 10, 19, 12),
  ),
);
