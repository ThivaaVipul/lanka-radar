import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/app_info.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/home_screen_widget.dart';
import 'package:lanka_radar/features/home/view/home_page.dart';

class LankaRadarApp extends StatelessWidget {
  const LankaRadarApp({
    required this.feed,
    required this.now,
    required this.alerts,
    required this.tabs,
    this.info = const AppInfo(version: ''),
    this.homeWidget = const HomeScreenWidget(),
    this.navigatorKey,
    super.key,
  });

  final FeedRepository feed;
  final NowRepository now;
  final AlertsRepository alerts;

  /// The home screen's tab, which notifications can change.
  final TabSelection tabs;
  final AppInfo info;
  final HomeScreenWidget homeWidget;

  /// Lets a tapped notification open its item.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: feed),
        RepositoryProvider.value(value: now),
        RepositoryProvider.value(value: alerts),
        RepositoryProvider.value(value: info),
        RepositoryProvider.value(value: homeWidget),
      ],
      child: MaterialApp(
        title: 'Lanka Radar',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: HomePage(tabs: tabs),
      ),
    );
  }
}
