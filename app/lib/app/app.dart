import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/features/home/view/home_page.dart';

class LankaRadarApp extends StatelessWidget {
  const LankaRadarApp({required this.feed, required this.now, super.key});

  final FeedRepository feed;
  final NowRepository now;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: feed),
        RepositoryProvider.value(value: now),
      ],
      child: MaterialApp(
        title: 'Lanka Radar',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const HomePage(),
      ),
    );
  }
}
