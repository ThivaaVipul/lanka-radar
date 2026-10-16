import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';

import '../../helpers/fake_sources.dart';

void main() {
  test('CEYPETCO: the six active fuel prices, fuel oils left out', () {
    final prices = parseFuelPrices(fixture('ceypetco_fuel_prices.json'));

    expect(
      [for (final price in prices) price.product],
      [
        'Lanka Auto Diesel',
        'Lanka Industrial Kerosene',
        'Lanka Kerosene',
        'Lanka Petrol 92 Octane',
        'Lanka Petrol 95 Octane Euro 4',
        'Lanka Super Diesel 4 Star Euro 4',
      ],
    );
    final petrol = prices[3];
    expect(petrol.price, 414);
    expect(petrol.effective, DateTime(2026, 9, 30));
  });

  test('CEYPETCO: an answer without success is an error', () {
    expect(
      () => parseFuelPrices('{"success": false, "data": []}'),
      throwsFormatException,
    );
  });

  test("CBSL: each day's rate from the results table", () {
    final rates = parseUsdRates(fixture('cbsl_usd_rates.html'));

    expect(rates, hasLength(12));
    expect(rates[DateTime(2026, 10, 16)], 331.286);
    expect(
      rates.keys.reduce((a, b) => a.isBefore(b) ? a : b),
      DateTime(2026, 10),
    );
  });

  test('CBSL: a page without the table is an error', () {
    expect(
      () => parseUsdRates('<html>Forbidden</html>'),
      throwsFormatException,
    );
  });
}
