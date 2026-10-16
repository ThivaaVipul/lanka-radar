import 'package:equatable/equatable.dart';

/// A number an item carries, such as a price with the one before it.
final class KeyNumber extends Equatable {
  const KeyNumber({
    required this.label,
    required this.value,
    required this.unit,
    this.previous,
  });

  factory KeyNumber.fromJson(Map<String, Object?> json) => KeyNumber(
    label: json['label']! as String,
    value: (json['value']! as num).toDouble(),
    unit: json['unit']! as String,
    previous: (json['previous'] as num?)?.toDouble(),
  );

  final String label;
  final double value;
  final String unit;
  final double? previous;

  @override
  List<Object?> get props => [label, value, unit, previous];
}

/// A feed item as the workflow publishes it on the data branch.
final class FeedItem extends Equatable {
  const FeedItem({
    required this.id,
    required this.source,
    required this.topic,
    required this.headlineEn,
    required this.published,
    this.issuer,
    this.headlineTa,
    this.keyNumbers = const [],
    this.effective,
    this.links = const {},
    this.data = const {},
    this.alert = false,
    this.firstSeen,
  });

  /// [firstSeen] comes from the phone's database, not the published item.
  factory FeedItem.fromJson(Map<String, Object?> json, {DateTime? firstSeen}) {
    final headline = json['headline']! as Map<String, Object?>;
    final numbers = (json['keyNumbers'] as List<Object?>?) ?? const [];
    final links = (json['links'] as Map<String, Object?>?) ?? const {};
    final effective = json['effective'] as String?;
    return FeedItem(
      id: json['id']! as String,
      source: json['source']! as String,
      topic: json['topic']! as String,
      issuer: json['issuer'] as String?,
      headlineEn: headline['en']! as String,
      headlineTa: headline['ta'] as String?,
      keyNumbers: [
        for (final number in numbers)
          KeyNumber.fromJson(number! as Map<String, Object?>),
      ],
      published: DateTime.parse(json['published']! as String),
      effective: effective == null ? null : DateTime.parse(effective),
      links: {
        for (final MapEntry(:key, :value) in links.entries)
          if (value is String) key: value,
      },
      data: (json['data'] as Map<String, Object?>?) ?? const {},
      alert: json['alert'] as bool? ?? false,
      firstSeen: firstSeen,
    );
  }

  final String id;
  final String source;

  /// One of prices, gazettes, rates, holidays, exams.
  final String topic;
  final String? issuer;
  final String headlineEn;
  final String? headlineTa;
  final List<KeyNumber> keyNumbers;

  /// Dates only, at midnight.
  final DateTime published;
  final DateTime? effective;

  /// page, pdf_en, pdf_ta, pdf_si, image.
  final Map<String, String> links;
  final Map<String, Object?> data;
  final bool alert;

  /// When the phone first stored the item.
  final DateTime? firstSeen;

  @override
  List<Object?> get props => [
    id,
    source,
    topic,
    issuer,
    headlineEn,
    headlineTa,
    keyNumbers,
    published,
    effective,
    links,
    data,
    alert,
    firstSeen,
  ];
}
