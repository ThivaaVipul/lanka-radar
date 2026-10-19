import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';

/// Dates: the year's remaining holidays, with the Tamil names, and the latest
/// school exam notices and timetables.
class DatesTab extends StatelessWidget {
  const DatesTab({super.key});

  /// How many exam items are listed.
  static const exams = 3;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        final now = state.nowCard;
        if (now == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = DateTime.now();
        final schoolExams = [
          for (final item in state.items ?? const <FeedItem>[])
            if (item.topic == 'exams' && item.data['kind'] != 'notice') item,
        ].take(exams);
        final theme = Theme.of(context);
        final muted = theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Section(
              title: 'Holidays',
              children: [
                if (now.holidays.isEmpty)
                  const ListTile(title: Text('Not yet')),
                for (final holiday in now.holidays)
                  ListTile(
                    leading: SizedBox(
                      width: 72,
                      child: Text(
                        weekdayDate(holiday.day),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    title: Text(
                      holiday.tentative
                          ? '${holiday.name} (tentative)'
                          : holiday.name,
                    ),
                    subtitle: holiday.tamil == null
                        ? null
                        : Text(holiday.tamil!),
                    trailing: Text(
                      inDays(holiday.day, today: today),
                      style: muted,
                    ),
                  ),
              ],
            ),
            if (schoolExams.isNotEmpty)
              Section(
                title: 'Exams',
                card: false,
                children: [
                  for (final item in schoolExams)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ItemCard(
                        item: item,
                        isNew: state.isNew(item),
                        onTap: () =>
                            Navigator.of(context).push(ItemPage.route(item)),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}
