import 'package:flutter/widgets.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  final feed = FeedRepository(database: database, remote: DataBranch());
  final now = NowRepository(
    database: database,
    ceypetco: Ceypetco(),
    cbsl: Cbsl(),
  );
  runApp(LankaRadarApp(feed: feed, now: now));
}
