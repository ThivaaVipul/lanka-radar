import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/feed_repository.dart';
import 'package:lanka_radar/features/home/view/home_page.dart';

class LankaRadarApp extends StatelessWidget {
  const LankaRadarApp({required this.feed, super.key});

  final FeedRepository feed;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: feed,
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
