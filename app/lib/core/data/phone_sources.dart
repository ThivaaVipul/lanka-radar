import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lanka_radar/core/format/dates.dart';

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

class SourceException implements Exception {
  const SourceException(this.source, this.statusCode);

  final String source;
  final int statusCode;

  @override
  String toString() => '$source answered $statusCode';
}
