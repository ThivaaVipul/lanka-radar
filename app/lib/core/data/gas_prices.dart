import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:lanka_radar/core/data/feed_item.dart';

/// The districts in the LP gas price lists, as the workflow names them.
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

/// The district shown until another is picked: both companies' headline price.
const defaultGasDistrict = 'Colombo';

/// Where the Laugfs prices are, on the data branch.
const laugfsPath = 'datasets/laugfs-gas.json';

/// Laugfs's own price list.
const laugfsPage = 'https://www.laugfsgas.lk/pricelist.php';

/// Whether [item] is an LP gas price list, Litro's or Laugfs's.
bool isGasList(FeedItem item) =>
    item.source == 'gas' || item.source == 'laugfs';

/// One cylinder size's price in a district, with the one before it.
final class GasPrice extends Equatable {
  const GasPrice({required this.size, required this.price, this.before});

  /// "12.5 kg".
  final String size;
  final double price;

  /// From the prices before, when they are known.
  final double? before;

  @override
  List<Object?> get props => [size, price, before];
}

/// A district's prices from one company.
final class GasPrices extends Equatable {
  const GasPrices({
    required this.district,
    required this.prices,
    this.since,
    this.list,
  });

  final String district;
  final List<GasPrice> prices;

  /// When these prices started, when known.
  final DateTime? since;

  /// Litro's list they come from, with its image.
  final FeedItem? list;

  @override
  List<Object?> get props => [district, prices, since, list];
}

/// Laugfs's prices as the workflow keeps them: the current ones by district,
/// the ones before the last change, and when that change was seen.
final class GasTable extends Equatable {
  const GasTable({
    required this.sizes,
    required this.prices,
    this.before = const {},
    this.since,
  });

  final List<String> sizes;
  final Map<String, List<double>> prices;
  final Map<String, List<double>> before;
  final DateTime? since;

  /// The dataset's JSON; null when it isn't there or can't be read.
  static GasTable? parse(String? body) {
    if (body == null) {
      return null;
    }
    try {
      final json = jsonDecode(body) as Map<String, Object?>;
      final since = json['since'];
      return GasTable(
        sizes: _strings(json['sizes']),
        prices: _byDistrict(json['prices']),
        before: _byDistrict(json['before']),
        since: since is String ? DateTime.tryParse(since) : null,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// [district]'s prices, each against the one before the last change.
  GasPrices? at(String district) {
    final values = prices[district];
    if (values == null || values.length != sizes.length) {
      return null;
    }
    final earlier = before[district];
    final known = earlier != null && earlier.length == sizes.length;
    return GasPrices(
      district: district,
      since: since,
      prices: [
        for (final (index, size) in sizes.indexed)
          GasPrice(
            size: size,
            price: values[index],
            before: known ? earlier[index] : null,
          ),
      ],
    );
  }

  @override
  List<Object?> get props => [sizes, prices, before, since];
}

/// [district]'s prices in the latest Litro list that has them, each with its
/// price in the list before; null when no list has been read yet.
GasPrices? gasPrices(List<FeedItem> items, String district) {
  final lists = _lists(items, 'gas', district);
  if (lists.isEmpty) {
    return null;
  }
  final latest = lists.first;
  final sizes = _sizes(latest);
  final values = _pricesIn(latest.data['districts'], district)!;
  final before = lists.length > 1 && _same(_sizes(lists[1]), sizes)
      ? _pricesIn(lists[1].data['districts'], district)
      : null;
  if (sizes.length != values.length) {
    return null;
  }
  return GasPrices(
    district: district,
    since: _day(latest),
    list: latest,
    prices: [
      for (final (index, size) in sizes.indexed)
        GasPrice(size: size, price: values[index], before: before?[index]),
    ],
  );
}

/// [list] (Litro's or Laugfs's) with its key numbers for [district], against
/// the prices before (a Laugfs change carries them; for Litro, the list before
/// in [items]), in place of the workflow's, which are Colombo's.
FeedItem forDistrict(FeedItem list, List<FeedItem> items, String district) {
  final values = _pricesIn(list.data['districts'], district);
  final sizes = _sizes(list);
  if (values == null || values.length != sizes.length) {
    return list;
  }
  List<double>? before;
  if (list.data.containsKey('before')) {
    before = _pricesIn(list.data['before'], district);
  } else {
    final earlier = [
      for (final other in _lists(items, list.source, district))
        if (_day(other).isBefore(_day(list)) && _same(_sizes(other), sizes))
          other,
    ];
    before = earlier.isEmpty
        ? null
        : _pricesIn(earlier.first.data['districts'], district);
  }
  if (before != null && before.length != sizes.length) {
    before = null;
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
      for (final (index, size) in sizes.indexed)
        KeyNumber(
          label: size,
          value: values[index],
          unit: 'LKR',
          previous: before?[index],
        ),
    ],
    effective: list.effective,
    links: list.links,
    data: {...list.data, 'district': district},
    alert: list.alert,
    firstSeen: list.firstSeen,
  );
}

/// [source]'s lists that have prices for [district], newest first.
List<FeedItem> _lists(List<FeedItem> items, String source, String district) => [
  for (final item in items)
    if (item.source == source &&
        _pricesIn(item.data['districts'], district) != null)
      item,
]..sort((a, b) => _day(b).compareTo(_day(a)));

DateTime _day(FeedItem item) => item.effective ?? item.published;

List<String> _sizes(FeedItem item) => _strings(item.data['sizes']);

List<String> _strings(Object? value) => [
  if (value is List<Object?>)
    for (final text in value)
      if (text is String) text,
];

List<double>? _pricesIn(Object? districts, String district) {
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

Map<String, List<double>> _byDistrict(Object? value) => {
  if (value is Map<String, Object?>)
    for (final district in value.keys) district: ?_pricesIn(value, district),
};

bool _same(List<String> a, List<String> b) => a.join('|') == b.join('|');
