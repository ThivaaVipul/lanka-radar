import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/format/dates.dart';
import 'package:lanka_radar/core/system_settings.dart';
import 'package:lanka_radar/features/alerts/cubit/alerts_cubit.dart';

/// The alert switches, quiet hours, and the battery settings with when the
/// background sync last ran.
class AlertsPage extends StatelessWidget {
  const AlertsPage({this.settings = const SystemSettings(), super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (context) => const AlertsPage());

  /// A background sync older than this suggests Android is holding it back.
  static const syncLate = Duration(hours: 12);

  final SystemSettings settings;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AlertsCubit(context.read(), context.read())..load(),
      child: _AlertsView(settings: settings),
    );
  }
}

class _AlertsView extends StatefulWidget {
  const _AlertsView({required this.settings});

  final SystemSettings settings;

  @override
  State<_AlertsView> createState() => _AlertsViewState();
}

class _AlertsViewState extends State<_AlertsView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<AlertsCubit>();
    // Back from Android's settings, notifications may be allowed now.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(cubit.load()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: BlocBuilder<AlertsCubit, AlertsState>(
        builder: (context, state) {
          if (!state.loaded) {
            return const SizedBox.shrink();
          }
          final cubit = context.read<AlertsCubit>();
          final colors = Theme.of(context).colorScheme;
          final quiet = state.quiet;
          final lastSync = state.lastSync;
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (!state.notificationsAllowed)
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.notifications_off_outlined,
                      color: colors.tertiary,
                    ),
                    title: const Text('Notifications are off'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => unawaited(settings.openNotifications()),
                  ),
                ),
              _Section(
                title: 'Topics',
                children: [
                  for (final alert in topicSwitches)
                    _SwitchTile(alert: alert, on: state.on.contains(alert)),
                ],
              ),
              _Section(
                title: 'Gazettes',
                children: [
                  for (final alert in gazetteSwitches)
                    _SwitchTile(alert: alert, on: state.on.contains(alert)),
                ],
              ),
              _Section(
                title: 'Quiet hours',
                children: [
                  SwitchListTile(
                    title: const Text('Hold alerts'),
                    value: quiet.on,
                    onChanged: (on) =>
                        unawaited(cubit.setQuietHours(quiet.copyWith(on: on))),
                  ),
                  _TimeTile(
                    label: 'Start',
                    minutes: quiet.start,
                    enabled: quiet.on,
                    onPicked: (start) => unawaited(
                      cubit.setQuietHours(quiet.copyWith(start: start)),
                    ),
                  ),
                  _TimeTile(
                    label: 'End',
                    minutes: quiet.end,
                    enabled: quiet.on,
                    onPicked: (end) => unawaited(
                      cubit.setQuietHours(quiet.copyWith(end: end)),
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'Background',
                children: [
                  ListTile(
                    title: const Text('Battery'),
                    subtitle: Text(
                      lastSync == null
                          ? 'No background sync yet'
                          : 'Last sync ${dayTime(lastSync, today: now)}',
                      style:
                          lastSync != null &&
                              now.difference(lastSync) > AlertsPage.syncLate
                          ? TextStyle(color: colors.tertiary)
                          : null,
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => unawaited(settings.openApp()),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.alert, required this.on});

  final AlertSwitch alert;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(alert.label),
      value: on,
      onChanged: (on) =>
          unawaited(context.read<AlertsCubit>().setSwitch(alert, on: on)),
    );
  }
}

/// A quiet hours time, picked on a 24-hour clock like the rest of the app.
class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.minutes,
    required this.enabled,
    required this.onPicked,
  });

  final String label;
  final int minutes;
  final bool enabled;
  final void Function(int minutes) onPicked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      title: Text(label),
      trailing: Text(clock(minutes)),
      leadingAndTrailingTextStyle: Theme.of(context).textTheme.bodyLarge,
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (picked != null) {
          onPicked(picked.hour * 60 + picked.minute);
        }
      },
    );
  }
}
