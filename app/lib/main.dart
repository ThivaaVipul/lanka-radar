import 'package:flutter/widgets.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final feed = FeedRepository(database: AppDatabase(), remote: DataBranch());
  runApp(LankaRadarApp(feed: feed));
}
