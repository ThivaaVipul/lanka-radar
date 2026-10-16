import 'package:flutter/widgets.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/app/app_info.dart';
import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  final database = AppDatabase();
  final feed = FeedRepository(database: database, remote: DataBranch());
  final now = NowRepository(
    database: database,
    ceypetco: Ceypetco(),
    cbsl: Cbsl(),
  );
  runApp(
    LankaRadarApp(
      feed: feed,
      now: now,
      info: AppInfo(version: '${package.version} (${package.buildNumber})'),
    ),
  );
}
