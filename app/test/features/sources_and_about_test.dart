import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/app_info.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/features/about/view/about_page.dart';
import 'package:lanka_radar/features/sources/view/sources_page.dart';

import '../helpers/fake_branch.dart';
import '../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeSources sources;
  late NowRepository phone;

  setUp(() {
    database = memoryDatabase();
    sources = FakeSources();
    phone = sources.repository(database);
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 3; round++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('Sources lists what GitHub and the phone read, with failures', (
    tester,
  ) async {
    final checked = DateTime.now().toUtc().toIso8601String();
    await tester.runAsync(() async {
      await database.saveFile(
        FileRow(
          path: 'status.json',
          body: jsonEncode({
            'schema': 1,
            'checked': checked,
            'sources': {
              'gazettes': {
                'lastRun': checked,
                'lastSuccess': checked,
                'lastError': null,
                'failures': 0,
              },
            },
          }),
          fetchedAt: DateTime.now(),
        ),
      );
      sources.offline = true;
      await phone.refresh();
    });

    await tester.pumpWidget(
      RepositoryProvider.value(
        value: phone,
        child: MaterialApp(theme: AppTheme.light, home: const SourcesPage()),
      ),
    );
    await settle(tester);

    expect(find.text('Read by GitHub'), findsOneWidget);
    expect(find.text('Gazettes'), findsOneWidget);
    expect(find.textContaining('Last run'), findsOneWidget);
    expect(find.text('Read by this phone'), findsOneWidget);
    expect(find.text('Fuel prices'), findsOneWidget);
    expect(find.textContaining('Never answered'), findsNWidgets(2));
    expect(find.textContaining('Last try failed'), findsNWidgets(2));
  });

  testWidgets('About shows the version and opens the source code', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: const AppInfo(version: '0.1.0 (1)'),
        child: MaterialApp(
          theme: AppTheme.light,
          home: AboutPage(
            open: (link) async {
              opened.add(link);
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Version 0.1.0 (1)'), findsOneWidget);

    await tester.tap(find.text('Source code'));
    expect(opened, [Uri.parse(AboutPage.repository)]);
  });
}
