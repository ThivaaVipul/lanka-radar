import 'package:flutter/material.dart';
import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/format/headlines.dart';
import 'package:lanka_radar/core/format/numbers.dart';
import 'package:lanka_radar/core/links.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';

/// The Now card above the feed: the six fuel prices, USD/LKR, the next holiday,
/// the latest LP gas list and exam timetable. Each part opens its detail.
class NowCard extends StatelessWidget {
  const NowCard({required this.data, this.open = openExternally, super.key});

  final NowData data;
  final OpenLink open;

  @override
  Widget build(BuildContext context) {
    final rate = data.rates.isEmpty ? null : data.rates.first;
    final holiday = data.holidays.isEmpty ? null : data.holidays.first;
    final gas = data.gas;
    final timetable = data.timetable;
    final today = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (data.fuel.isNotEmpty) ...[
            _FuelSection(data: data, open: open),
            const Divider(height: 1),
          ],
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Tile(
                    label: 'USD/LKR',
                    value: rate == null ? 'Not yet' : amount(rate.rate),
                    note: rate == null
                        ? null
                        : data.ratesFromBackup
                        ? 'as of ${cardDate(rate.day, today: today)}'
                        : cardDate(rate.day, today: today),
                    onTap: data.rates.isEmpty
                        ? null
                        : () => showRatesSheet(context, data, open),
                  ),
                ),
                Expanded(
                  child: _Tile(
                    label: 'Next holiday',
                    value: holiday?.name ?? 'Not yet',
                    note: holiday == null
                        ? null
                        : cardDate(holiday.day, today: today),
                    onTap: holiday == null
                        ? null
                        : () => showHolidaysSheet(context, data),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Tile(
                    label: 'LP gas',
                    value: gas == null
                        ? 'Not yet'
                        : 'List from '
                              '${cardDate(gas.effective ?? gas.published, today: today)}',
                    onTap: gas?.links['image'] == null
                        ? null
                        : () => open(Uri.parse(gas!.links['image']!)),
                  ),
                ),
                Expanded(
                  child: _Tile(
                    label: 'Exam timetable',
                    value: timetable == null
                        ? 'Not yet'
                        : displayHeadline(timetable),
                    onTap: timetable == null
                        ? null
                        : () => Navigator.of(
                            context,
                          ).push(ItemPage.route(timetable)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelSection extends StatelessWidget {
  const _FuelSection({required this.data, required this.open});

  final NowData data;
  final OpenLink open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final prices = data.fuel;
    return InkWell(
      onTap: () => showFuelSheet(context, data, open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Fuel', style: theme.textTheme.titleSmall),
                ),
                Text(fuelNote(data, today: DateTime.now()), style: quiet),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < prices.length; index += 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: _FuelPrice(price: prices[index])),
                    const SizedBox(width: 16),
                    Expanded(
                      child: index + 1 < prices.length
                          ? _FuelPrice(price: prices[index + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "changed 30 Sep", or "as of 14 Oct" when CEYPETCO hasn't answered for a
/// day or the prices come from a gazette.
String fuelNote(NowData data, {required DateTime today}) {
  final asOf = data.fuelAsOf;
  final changed = data.fuelChanged;
  final stale =
      data.fuelFromGazette ||
      asOf == null ||
      today.difference(asOf) > staleAfter;
  if (stale && asOf != null) {
    return 'as of ${cardDate(asOf, today: today)}';
  }
  return changed == null ? '' : 'changed ${cardDate(changed, today: today)}';
}

/// Names too long for half the card's width; the fuel sheet has them in full.
const _gridNames = {'Industrial kerosene': 'Ind. kerosene'};

class _FuelPrice extends StatelessWidget {
  const _FuelPrice({required this.price});

  final FuelNow price;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(
          child: Text(
            _gridNames[price.name] ?? price.name,
            style: body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          amount(price.price),
          style: body?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.note,
    this.onTap,
  });

  final String label;
  final String value;
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: quiet),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(note!, style: quiet),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showFuelSheet(BuildContext context, NowData data, OpenLink open) {
  final today = DateTime.now();
  final asOf = data.fuelAsOf;
  return _showSheet(
    context,
    title: 'Fuel prices',
    subtitle: data.fuelFromGazette && asOf != null
        ? 'From the ${shortDate(asOf)} gazette'
        : fuelNote(data, today: today).startsWith('as of')
        ? 'CEYPETCO, ${fuelNote(data, today: today)}'
        : 'CEYPETCO',
    children: [
      for (final price in data.fuel)
        _SheetRow(
          title: price.name,
          subtitle: 'since ${cardDate(price.since, today: today)}',
          value: amount(price.price),
          note: price.was == null ? null : 'was ${amount(price.was!)}',
        ),
    ],
    link: ('CEYPETCO prices', Ceypetco.page),
    open: open,
  );
}

Future<void> showRatesSheet(
  BuildContext context,
  NowData data,
  OpenLink open,
) => _showSheet(
  context,
  title: 'USD/LKR',
  subtitle: data.ratesFromBackup
      ? 'Last 30 days, from the backup copy'
      : 'Last 30 days, Central Bank of Sri Lanka',
  children: [
    for (final rate in data.rates)
      _SheetRow(title: weekdayDate(rate.day), value: amount(rate.rate)),
  ],
  link: ('Central Bank rates', Cbsl.page),
  open: open,
);

Future<void> showHolidaysSheet(BuildContext context, NowData data) =>
    _showSheet(
      context,
      title: 'Holidays',
      children: [
        for (final holiday in data.holidays)
          _SheetRow(
            title: holiday.tentative
                ? '${holiday.name} (tentative)'
                : holiday.name,
            subtitle: holiday.tamil,
            leading: weekdayDate(holiday.day),
          ),
      ],
    );

Future<void> _showSheet(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  String? subtitle,
  (String, String)? link,
  OpenLink? open,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
            if (link != null && open != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => open(Uri.parse(link.$2)),
                  child: Text(link.$1),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.title,
    this.subtitle,
    this.value,
    this.note,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final String? note;

  /// A date column on the left (holidays).
  final String? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null)
            SizedBox(
              width: 96,
              child: Text(leading!, style: theme.textTheme.bodyMedium),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge),
                if (subtitle != null) Text(subtitle!, style: quiet),
              ],
            ),
          ),
          if (value != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (note != null) Text(note!, style: quiet),
              ],
            ),
        ],
      ),
    );
  }
}
