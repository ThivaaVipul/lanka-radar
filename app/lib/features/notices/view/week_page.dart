import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/alerts/weekly_alerts.dart';
import 'package:lanka_radar/core/data/feed_item.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/features/home/widgets/pieces.dart';
import 'package:lanka_radar/features/item/view/item_page.dart';
import 'package:lanka_radar/features/item/widgets/item_card.dart';

/// A weekly gazette's notices, as its notification counted them: the vacancies,
/// then the examinations, in the order the gazette prints them.
class WeekPage extends StatelessWidget {
  const WeekPage({required this.week, super.key});

  static Route<void> route(DateTime week) =>
      MaterialPageRoute(builder: (context) => WeekPage(week: week));

  /// The gazette's date.
  final DateTime week;

  @override
  Widget build(BuildContext context) {
    final feed = context.read<FeedRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Gazette of ${shortDate(week)}')),
      body: StreamBuilder<List<FeedItem>>(
        stream: feed.watchItems(),
        builder: (context, snapshot) {
          final items = snapshot.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final notices = weekNotices(items, week);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              for (final (title, topic) in const [
                ('Vacancies', 'jobs'),
                ('Examinations', 'exams'),
              ])
                if (notices.where((item) => item.topic == topic).toList()
                    case final group when group.isNotEmpty)
                  Section(
                    title: title,
                    card: false,
                    children: [
                      ItemGroup(
                        children: [
                          for (final item in group)
                            ItemTile(
                              item: item,
                              onTap: () => Navigator.of(
                                context,
                              ).push(ItemPage.route(item)),
                            ),
                        ],
                      ),
                    ],
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// The weekly gazette notices of [week], in the gazette's page order.
List<FeedItem> weekNotices(List<FeedItem> items, DateTime week) => [
  for (final item in items)
    if (item.source == 'weekly' && weekOf(item) == week) item,
]..sort((a, b) => _page(a).compareTo(_page(b)));

int _page(FeedItem item) => switch (item.data['page']) {
  final int page => page,
  _ => 0,
};
