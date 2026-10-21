import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lanka_radar/app/app.dart';
import 'package:lanka_radar/app/app_info.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/app/notification_router.dart';
import 'package:lanka_radar/background.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/alerts/notifier.dart';
import 'package:lanka_radar/core/data/data_branch.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/phone_sources.dart';
import 'package:lanka_radar/core/home_screen_widget.dart';
import 'package:lanka_radar/core/pdf_store.dart';
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
    market: CbslMarket(),
    edl: EdlCare(),
  );
  final tabs = TabSelection(
    tabFromWidget(await HomeScreenWidget.launchedWith()) ?? HomeTab.today,
  );
  final router = NotificationRouter(feed, tabs);
  HomeScreenWidget.taps.listen((link) {
    if (tabFromWidget(link) case final tab?) {
      router.showTab(tab);
    }
  });
  final notifier = await LocalNotifier.start(
    onTap: (payload) => unawaited(router.open(payload)),
  );
  router.pending = await notifier.launchPayload();
  await scheduleBackgroundSync();
  runApp(
    LankaRadarApp(
      feed: feed,
      now: now,
      alerts: AlertsRepository(database: database, notifier: notifier),
      pdfs: PdfStore(database: database),
      info: AppInfo(version: '${package.version} (${package.buildNumber})'),
      tabs: tabs,
      navigatorKey: router.navigatorKey,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(router.openPending()),
  );
}
