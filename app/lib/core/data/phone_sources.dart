import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lanka_radar/core/data/market_report.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:pdfrx/pdfrx.dart';

/// Sources that answer only inside Sri Lanka, so the phone reads them itself
/// (GitHub's servers abroad can't). Requests name the project, as the scrapers do.
const userAgent =
    'Mozilla/5.0 (compatible; LankaRadar/0.1; '
    '+https://github.com/ThivaaVipul/lanka-radar)';

const _timeout = Duration(seconds: 20);

/// A fuel price as CEYPETCO lists it, and the day it started.
typedef FuelPrice = ({String product, double price, DateTime effective});

/// Ceylon Petroleum Corporation's active fuel prices.
class Ceypetco {
  Ceypetco({http.Client? client}) : _client = client ?? http.Client();

  static final api = Uri.parse(
    'https://api.ceypetco.gov.lk/api/admin/fuel-prices/active?limit=100',
  );
  static const page = 'https://ceypetco.gov.lk/marketing-sales/';

  final http.Client _client;

  Future<List<FuelPrice>> activePrices() async {
    final response = await _client
        .get(api, headers: {'User-Agent': userAgent})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw SourceException('CEYPETCO', response.statusCode);
    }
    return parseFuelPrices(utf8.decode(response.bodyBytes));
  }
}

/// The active fuel prices in CEYPETCO's answer, by product name. Fuel oils
/// (type "other") are left out.
List<FuelPrice> parseFuelPrices(String body) {
  final json = jsonDecode(body) as Map<String, Object?>;
  if (json['success'] != true) {
    throw const FormatException('CEYPETCO answered without success');
  }
  final prices = <FuelPrice>[
    for (final row in json['data']! as List<Object?>)
      if (row case {
        'type': 'fuel',
        'status': 'active',
        'product': final String product,
        'price': final num price,
        'effectiveDate': final String effective,
      })
        (
          product: product.trim(),
          price: price.toDouble(),
          effective: DateTime.parse(effective.substring(0, 10)),
        ),
  ]..sort((a, b) => a.product.compareTo(b.product));
  if (prices.isEmpty) {
    throw const FormatException('CEYPETCO listed no fuel');
  }
  return prices;
}

/// The Central Bank's daily USD/LKR rates, from its rate search form.
class Cbsl {
  Cbsl({http.Client? client}) : _client = client ?? http.Client();

  static final results = Uri.parse(
    'https://www.cbsl.gov.lk/cbsl_custom/exrates/exrates_results.php',
  );
  static const page =
      'https://www.cbsl.gov.lk/en/rates-and-indicators/exchange-rates';

  final http.Client _client;

  Future<Map<DateTime, double>> usdRates({
    required DateTime from,
    required DateTime to,
  }) async {
    final response = await _client
        .post(
          results,
          headers: {'User-Agent': userAgent},
          body: {
            'lookupPage': 'lookup_daily_exchange_rates.php',
            'startRange': '2006-11-11',
            'rangeType': 'dates',
            'txtStart': isoDay(from),
            'txtEnd': isoDay(to),
            'chk_cur[]': 'USD~US Dollar',
            'submit_button': 'Submit',
          },
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw SourceException('CBSL', response.statusCode);
    }
    return parseUsdRates(utf8.decode(response.bodyBytes));
  }
}

final _rateRow = RegExp(
  r'<td>\s*(\d{4}-\d{2}-\d{2})\s*</td>\s*<td>\s*(\d+(?:\.\d+)?)\s*</td>',
);

/// The rows of CBSL's results table: a day and how many rupees a dollar buys.
Map<DateTime, double> parseUsdRates(String html) {
  final rates = {
    for (final row in _rateRow.allMatches(html))
      DateTime.parse(row[1]!): double.parse(row[2]!),
  };
  if (rates.isEmpty) {
    throw const FormatException('CBSL answered without rates');
  }
  return rates;
}

/// The Central Bank's Daily Price Report ([MarketReport]).
class CbslMarket {
  CbslMarket({
    http.Client? client,
    Future<List<ReportChar>> Function(Uint8List pdf)? read,
  }) : _client = client ?? http.Client(),
       _read = read ?? _readWithFlutter;

  final http.Client _client;
  final Future<List<ReportChar>> Function(Uint8List pdf) _read;

  /// The days the listing has a report for, newest first.
  Future<List<DateTime>> listedDays() async => listedReportDays(
    utf8.decode((await _get(MarketReport.listing)).bodyBytes),
  );

  /// A day's report.
  Future<List<ReportRow>> report(DateTime day) async =>
      parseReport(await _read((await _get(MarketReport.of(day))).bodyBytes));

  Future<http.Response> _get(Uri uri) async {
    final response = await _client
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw SourceException('CBSL', response.statusCode);
    }
    return response;
  }

  static Future<List<ReportChar>> _readWithFlutter(Uint8List pdf) async {
    await pdfrxFlutterInitialize();
    return reportChars(pdf);
  }
}

/// The characters on a report's last page, where its table is, read with
/// PDFium (initialized by the caller).
Future<List<ReportChar>> reportChars(Uint8List pdf) async {
  final PdfDocument document;
  try {
    document = await PdfDocument.openData(pdf, sourceName: 'price report');
  } on PdfException catch (error) {
    throw FormatException('The report is not a readable PDF: $error');
  }
  try {
    final page = document.pages.last;
    final text = await page.loadText();
    if (text == null) {
      throw const FormatException('No text in the report');
    }
    return [
      for (final (index, rect) in text.charRects.indexed)
        (
          text: text.fullText[index],
          left: rect.left,
          right: rect.right,
          bottom: page.height - rect.bottom,
        ),
    ];
  } finally {
    await document.dispose();
  }
}

/// EDLCare's public outage map (`edlcare.edl.lk`, CEB's customer site), by CEB
/// area office. Unofficial: the site's own pages have moved to endpoints that
/// need a login, and these may go.
class EdlCare {
  EdlCare({http.Client? client}) : _client = client ?? http.Client();

  static final _base = Uri.parse('https://edlcare.edl.lk/api/incognito/');

  /// EDLCare's outage map, for people.
  static final outageMap = Uri.parse(
    'https://edlcare.edl.lk/incognito/outage-map',
  );

  final http.Client _client;

  Future<List<CebRegion>> provinces() async =>
      parseRegions(await _get('provinces'), 'province');

  Future<List<CebRegion>> areas(String provinceId) async =>
      parseRegions(await _get('areas', {'provinceId': provinceId}), 'area');

  /// The area's outages as EDLCare answers them ([parseOutages] reads them).
  Future<String> outages(String areaId) =>
      _get('outage-locations', {'areaId': areaId});

  /// The cuts at an account's meter from [from] to [to], days included, as
  /// EDLCare answers them ([parseCalendar] reads them).
  Future<String> calendar(
    String account, {
    required DateTime from,
    required DateTime to,
  }) => _get('calendar', {
    'acctNo': account,
    'from': isoDay(from),
    'to': isoDay(to),
  });

  Future<String> _get(String path, [Map<String, String>? query]) async {
    final response = await _client
        .get(
          _base.resolve(path).replace(queryParameters: query),
          headers: {'User-Agent': userAgent},
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw SourceException('EDLCare', response.statusCode);
    }
    return utf8.decode(response.bodyBytes);
  }
}

class SourceException implements Exception {
  const SourceException(this.source, this.statusCode);

  final String source;
  final int statusCode;

  @override
  String toString() => '$source answered $statusCode';
}
