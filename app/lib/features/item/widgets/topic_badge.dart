import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/gas_prices.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/format/labels.dart';

/// How an item's kind looks: its icon, and whether it takes the ochre tint of
/// prices, the teal of rates, or the plain one of notices.
enum TopicLook {
  fuel(Icons.local_gas_station_outlined, _Tint.ochre),
  prices(Icons.sell_outlined, _Tint.ochre),
  gas(Icons.propane_tank_outlined, _Tint.ochre),
  market(Icons.shopping_basket_outlined, _Tint.ochre),
  rates(Icons.currency_exchange, _Tint.teal),
  exams(Icons.school_outlined, _Tint.teal),
  jobs(Icons.badge_outlined, _Tint.teal),
  holiday(Icons.event_outlined, _Tint.teal),
  taxes(Icons.receipt_long_outlined, _Tint.plain),
  energy(Icons.bolt_outlined, _Tint.plain),
  labour(Icons.work_outline, _Tint.plain),
  elections(Icons.how_to_vote_outlined, _Tint.plain),
  notice(Icons.description_outlined, _Tint.plain);

  const TopicLook(this.icon, this._tint);

  final IconData icon;
  final _Tint _tint;

  static TopicLook of(FeedItem item) {
    if (isGasList(item)) {
      return gas;
    }
    return switch (item.topic) {
      'prices'
          when item.keyNumbers.any(
            (number) => fuelOrder.contains(shortLabel(number.label)),
          ) =>
        fuel,
      'prices' => prices,
      'rates' => rates,
      'exams' => exams,
      'jobs' => jobs,
      _ => switch (item.data['group']) {
        'prices-taxes' => taxes,
        'energy' => energy,
        'labour' => labour,
        'elections' => elections,
        _ => notice,
      },
    };
  }

  /// The badge's background and icon colours.
  (Color, Color) colors(ColorScheme scheme) => switch (_tint) {
    _Tint.ochre => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    _Tint.teal => (scheme.primaryContainer, scheme.onPrimaryContainer),
    _Tint.plain => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
  };
}

enum _Tint { ochre, teal, plain }

/// A topic's icon on a small tinted square, at the start of a row.
class TopicBadge extends StatelessWidget {
  const TopicBadge(this.look, {super.key});

  final TopicLook look;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = look.colors(Theme.of(context).colorScheme);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(look.icon, size: 18, color: foreground),
    );
  }
}
