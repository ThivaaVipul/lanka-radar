import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

/// The districts in Litro's price list, as the workflow names them.
const gasDistricts = [
  'Ampara',
  'Anuradhapura',
  'Badulla',
  'Batticaloa',
  'Colombo',
  'Galle',
  'Gampaha',
  'Hambantota',
  'Jaffna',
  'Kalutara',
  'Kandy',
  'Kegalle',
  'Kilinochchi',
  'Kurunegala',
  'Mannar',
  'Matale',
  'Matara',
  'Monaragala',
  'Mullaitivu',
  'Nuwara Eliya',
  'Polonnaruwa',
  'Puttalam',
  'Ratnapura',
  'Trincomalee',
  'Vavuniya',
];

/// The district shown until another is picked: Litro's own headline price.
const defaultGasDistrict = 'Colombo';

/// One cylinder size's price in a district, with the one before it.
final class GasPrice extends Equatable {
  const GasPrice({required this.size, required this.price, this.before});

  /// "12.5 kg".
  final String size;
  final double price;

  /// From the list before, when that one was read too.
  final double? before;

  @override
  List<Object?> get props => [size, price, before];
}

/// A district's prices in Litro's latest list read off its image.
final class GasPrices extends Equatable {
  const GasPrices({
    required this.list,
    required this.district,
    required this.prices,
  });

  final FeedItem list;
  final String district;
  final List<GasPrice> prices;

  @override
  List<Object?> get props => [list, district, prices];
}

/// [district]'s prices in the latest Litro list that has them, each with its
/// price in the list before; null when no list has been read yet.
GasPrices? gasPrices(List<FeedItem> items, String district) {
  final lists = [
    for (final item in items)
      if (item.source == 'gas' && _prices(item, district) != null) item,
  ]..sort((a, b) => _day(b).compareTo(_day(a)));
  if (lists.isEmpty) {
    return null;
  }
  final latest = lists.first;
  final sizes = _sizes(latest);
  final values = _prices(latest, district)!;
  final before = lists.length > 1 && _same(_sizes(lists[1]), sizes)
      ? _prices(lists[1], district)
      : null;
  if (sizes.length != values.length) {
    return null;
  }
  return GasPrices(
    list: latest,
    district: district,
    prices: [
      for (final (index, size) in sizes.indexed)
        GasPrice(size: size, price: values[index], before: before?[index]),
    ],
  );
}

/// [list] with its key numbers for [district] (its prices, against the list
/// before in [items]) in place of the workflow's, which are Colombo's.
FeedItem forDistrict(FeedItem list, List<FeedItem> items, String district) {
  final prices = gasPrices(items, district);
  if (prices == null || prices.list.id != list.id) {
    return list;
  }
  return FeedItem(
    id: list.id,
    source: list.source,
    topic: list.topic,
    headlineEn: list.headlineEn,
    published: list.published,
    issuer: list.issuer,
    headlineTa: list.headlineTa,
    keyNumbers: [
      for (final price in prices.prices)
        KeyNumber(
          label: price.size,
          value: price.price,
          unit: 'LKR',
          previous: price.before,
        ),
    ],
    effective: list.effective,
    links: list.links,
    data: {...list.data, 'district': district},
    alert: list.alert,
    firstSeen: list.firstSeen,
  );
}

DateTime _day(FeedItem item) => item.effective ?? item.published;

List<String> _sizes(FeedItem item) => [
  if (item.data['sizes'] case final List<Object?> sizes)
    for (final size in sizes)
      if (size is String) size,
];

List<double>? _prices(FeedItem item, String district) {
  final districts = item.data['districts'];
  if (districts is! Map<String, Object?>) {
    return null;
  }
  final values = districts[district];
  if (values is! List<Object?>) {
    return null;
  }
  return [
    for (final value in values)
      if (value is num) value.toDouble(),
  ];
}

bool _same(List<String> a, List<String> b) => a.join('|') == b.join('|');
