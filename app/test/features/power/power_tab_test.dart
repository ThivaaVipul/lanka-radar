import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/theme.dart';
import 'package:lanka_radar/core/data/database.dart';
import 'package:lanka_radar/core/data/now_repository.dart';
import 'package:lanka_radar/core/data/power_cuts.dart';
import 'package:lanka_radar/core/location.dart';
import 'package:lanka_radar/core/sharing.dart';
import 'package:lanka_radar/features/power/cubit/power_cubit.dart';
import 'package:lanka_radar/features/power/view/map_picker_page.dart';
import 'package:lanka_radar/features/power/view/power_tab.dart';
import 'package:lanka_radar/features/power/widgets/osm.dart';
import 'package:lanka_radar/features/power/widgets/place_row.dart';

import '../../helpers/fake_branch.dart';
import '../../helpers/fake_sharing.dart';
import '../../helpers/fake_sources.dart';

void main() {
  late AppDatabase database;
  late FakeSources sources;
  late NowRepository phone;
  late FakeSharing sharing;

  setUp(() {
    database = memoryDatabase();
    sources = FakeSources();
    phone = sources.repository(database);
    sharing = FakeSharing();
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
  }

  Future<PowerCubit> open(
    WidgetTester tester, {
    Locate locate = _gampaha,
  }) async {
    // As with Android's "Remove animations": the rings stay still, so the
    // screen settles.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final cubit = PowerCubit(phone);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: phone),
          RepositoryProvider<Sharing>.value(value: sharing),
        ],
        child: NoMapTiles(
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: PowerTab(locate: locate),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(cubit.show);
    await settle(tester);
    return cubit;
  }

  Future<void> pick(WidgetTester tester, String tile, String option) async {
    await reach(tester, find.text(tile));
    await tester.tap(find.text(tile));
    await tester.pumpAndSettle();
    final choice = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(option),
    );
    await tester.scrollUntilVisible(
      choice,
      100,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(choice);
    await settle(tester);
  }

  Future<List<String>> saved(WidgetTester tester) async => [
    for (final place in (await tester.runAsync(phone.powerSetup))!.places)
      place.name,
  ];

  Finder button(String label) => find.widgetWithText(FilledButton, label);

  Finder row(String name) =>
      find.descendant(of: find.byType(PlaceRow), matching: find.text(name));

  testWidgets('starts by inviting a place', (tester) async {
    await open(tester);

    expect(find.text('Watch for power cuts'), findsOneWidget);
    await tester.tap(button('Add a place'));
    await settle(tester);
    expect(find.text('New place'), findsOneWidget);
  });

  testWidgets(
    'a new place is kept only on Save, and Save points out what is missing',
    (tester) async {
      await open(tester);
      await tester.tap(button('Add a place'));
      await settle(tester);

      await tester.tap(button('Add place'));
      await settle(tester);
      expect(find.text('Set where it is'), findsOneWidget);
      await reach(tester, find.text('Pick its CEB area'));
      expect(find.text('Pick its CEB area'), findsOneWidget);
      expect(await saved(tester), isEmpty);

      await tester.tap(find.text('Use my location'));
      await settle(tester);
      expect(find.text('Change'), findsOneWidget);
      await pick(tester, 'Province', 'Western Province North');
      await pick(tester, 'Area', 'Gampaha');
      await tester.tap(button('Add place'));
      await settle(tester);

      expect(find.text('Home added. Checking for cuts there.'), findsOneWidget);
      expect(await saved(tester), ['Home']);
      expect(find.text('Power cut at Home'), findsOneWidget);
      expect(find.text('Breakdown since 09:24'), findsOneWidget);
    },
  );

  testWidgets(
    'the map starts from the phone and takes the spot under the pin',
    (tester) async {
      await open(tester);
      await tester.tap(button('Add a place'));
      await settle(tester);

      await tester.tap(find.text('Pick on map'));
      await settle(tester);
      expect(find.byType(MapPickerPage), findsOneWidget);
      expect(find.text('Where is Home?'), findsOneWidget);
      expect(find.text('Put the pin on the building.'), findsOneWidget);

      await tester.tap(button('Use this spot'));
      await settle(tester);
      expect(find.text('Change'), findsOneWidget);
    },
  );

  testWidgets('a long press on a place with a cut shares the cut', (
    tester,
  ) async {
    await tester.runAsync(() => storePowerSetup(phone));
    await open(tester);

    await tester.longPress(row('Home'));

    expect(sharing.shared.single, startsWith('Power cut in Gampaha'));
    expect(sharing.shared.single, isNot(contains('Home')));
  });

  testWidgets('closing with changes asks first, and discards them', (
    tester,
  ) async {
    await tester.runAsync(() => storePowerSetup(phone));
    await open(tester);

    await tester.tap(row('Home'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(button('Discard'));
    await settle(tester);

    expect(find.byType(PlaceRow), findsOneWidget);
    expect(await saved(tester), ['Home']);
  });

  testWidgets('a renamed place is saved, with a word to say so', (
    tester,
  ) async {
    await tester.runAsync(() => storePowerSetup(phone));
    await open(tester);

    await tester.tap(row('Home'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Work'));
    await tester.pumpAndSettle();
    await tester.tap(button('Save changes'));
    await settle(tester);

    expect(find.text('Changes to Work saved'), findsOneWidget);
    expect(await saved(tester), ['Work']);
  });

  testWidgets("a place's page names the load shedding group it is in", (
    tester,
  ) async {
    await tester.runAsync(() => storePowerSetup(phone));
    await open(tester);

    await tester.tap(row('Home'));
    await settle(tester);

    final group = find.widgetWithText(ListTile, 'Load shedding group');
    await reach(tester, group);
    expect(
      find.descendant(of: group, matching: find.text('V')),
      findsOneWidget,
    );
  });

  testWidgets("a place's row lists its group's cuts to come", (tester) async {
    phone = sources.repository(database, now: () => DateTime(2026, 10, 20, 12));
    await tester.runAsync(() => storePowerSetup(phone));
    await open(tester);

    // Today's and tomorrow's: the day, the hours, what it is.
    final rows = find.byType(PlaceRow);
    expect(
      find.descendant(of: rows, matching: find.text('Load shedding')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: rows, matching: find.text('19:30 to 20:30')),
      findsOneWidget,
    );
  });

  testWidgets('removing asks first, and can be undone', (tester) async {
    await tester.runAsync(() => storePowerSetup(phone));
    await open(tester);

    await tester.tap(row('Home'));
    await settle(tester);
    await tester.tap(find.byTooltip('Remove place'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Home?'), findsOneWidget);
    await tester.tap(button('Remove'));
    await settle(tester);

    expect(find.text('Home removed'), findsOneWidget);
    expect(await saved(tester), isEmpty);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(await saved(tester), ['Home']);
    expect(find.byType(PlaceRow), findsOneWidget);
  });

  testWidgets('says why the location could not be read', (tester) async {
    await open(
      tester,
      locate: () async => throw const LocateException(LocateFailure.denied),
    );
    await tester.tap(button('Add a place'));
    await settle(tester);

    await tester.tap(find.text('Use my location'));
    await settle(tester);

    expect(
      find.text('Allow location for Lanka Radar to use it.'),
      findsOneWidget,
    );
  });

  testWidgets('says when EDLCare is not answering, and tries again', (
    tester,
  ) async {
    await tester.runAsync(() => storePowerSetup(phone));
    sources.offline = true;
    final cubit = await open(tester);

    expect(find.text("Couldn't reach EDLCare"), findsOneWidget);

    sources.offline = false;
    await tester.tap(button('Try again'));
    await settle(tester);
    expect(cubit.state.check, PowerCheck.done);
    expect(find.text('Power cut at Home'), findsOneWidget);
  });
}

/// Scrolls the place page until [finder] is on screen.
Future<void> reach(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<GeoPoint> _gampaha() async => gampahaHome;
