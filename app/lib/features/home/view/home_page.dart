import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/app/home_tabs.dart';
import 'package:lanka_radar/core/location.dart';
import 'package:lanka_radar/features/about/view/about_page.dart';
import 'package:lanka_radar/features/alerts/view/alerts_page.dart';
import 'package:lanka_radar/features/home/cubit/home_cubit.dart';
import 'package:lanka_radar/features/home/view/dates_tab.dart';
import 'package:lanka_radar/features/home/view/notices_tab.dart';
import 'package:lanka_radar/features/home/view/prices_tab.dart';
import 'package:lanka_radar/features/home/view/today_tab.dart';
import 'package:lanka_radar/features/power/cubit/power_cubit.dart';
import 'package:lanka_radar/features/power/view/power_tab.dart';
import 'package:lanka_radar/features/search/view/search_page.dart';
import 'package:lanka_radar/features/sources/view/sources_page.dart';

/// The home screen: Today, Prices, Notices, Dates and Power in a bottom bar,
/// with search, the source warning and the menu on top.
class HomePage extends StatelessWidget {
  const HomePage({required this.tabs, this.locate = locatePhone, super.key});

  final TabSelection tabs;
  final Locate locate;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => HomeCubit(
            context.read(),
            context.read(),
            context.read(),
            context.read(),
          )..watch(),
        ),
        BlocProvider(create: (context) => PowerCubit(context.read())),
      ],
      child: _HomeView(tabs: tabs, locate: locate),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView({required this.tabs, required this.locate});

  final TabSelection tabs;
  final Locate locate;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<HomeCubit>();
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(cubit.leave()),
      onShow: () => unawaited(cubit.resume()),
    );
    widget.tabs.addListener(_tabShown);
    _tabShown();
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_tabShown);
    _lifecycle.dispose();
    super.dispose();
  }

  /// Power looks for cuts each time it is shown.
  void _tabShown() {
    if (widget.tabs.value == HomeTab.power) {
      unawaited(context.read<PowerCubit>().show());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    return ValueListenableBuilder<HomeTab>(
      valueListenable: tabs,
      builder: (context, tab, _) => Scaffold(
        appBar: AppBar(
          title: Text(tab.label),
          actions: [
            BlocSelector<HomeCubit, HomeState, bool>(
              selector: (state) =>
                  state.health?.needsALook(DateTime.now()) ?? false,
              builder: (context, needsALook) => needsALook
                  ? IconButton(
                      tooltip: 'A source has gone quiet',
                      icon: Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      onPressed: () =>
                          Navigator.of(context).push(SourcesPage.route()),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () =>
                  Navigator.of(context).push(SearchPage.route(tabs)),
            ),
            PopupMenuButton<Route<void> Function()>(
              tooltip: 'More',
              onSelected: (route) => Navigator.of(context).push(route()),
              itemBuilder: (context) => const [
                PopupMenuItem(value: AlertsPage.route, child: Text('Alerts')),
                PopupMenuItem(value: SourcesPage.route, child: Text('Sources')),
                PopupMenuItem(value: AboutPage.route, child: Text('About')),
              ],
            ),
          ],
        ),
        body: MultiBlocListener(
          listeners: [
            BlocListener<HomeCubit, HomeState>(
              listenWhen: (before, now) =>
                  !before.failed &&
                  now.failed &&
                  (now.items?.isNotEmpty ?? false),
              listener: (context, state) => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Couldn't refresh"))),
            ),
            // Today's power cut cards follow what Power has read.
            BlocListener<PowerCubit, PowerState>(
              listenWhen: (before, now) =>
                  before.power != now.power || before.setup != now.setup,
              listener: (context, state) =>
                  unawaited(context.read<HomeCubit>().reloadNow()),
            ),
          ],
          child: IndexedStack(
            index: tab.index,
            children: [
              TodayTab(open: (tab) => tabs.value = tab),
              const PricesTab(),
              const NoticesTab(),
              const DatesTab(),
              PowerTab(locate: widget.locate),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (index) => tabs.value = HomeTab.values[index],
          destinations: [
            for (final tab in HomeTab.values)
              NavigationDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.selectedIcon),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}
