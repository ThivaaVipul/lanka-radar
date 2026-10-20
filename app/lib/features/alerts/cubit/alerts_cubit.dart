import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lanka_radar/core/alerts/alert_switches.dart';
import 'package:lanka_radar/core/alerts/alerts_repository.dart';
import 'package:lanka_radar/core/alerts/quiet_hours.dart';
import 'package:lanka_radar/core/data/now_repository.dart';

part 'alerts_state.dart';

class AlertsCubit extends Cubit<AlertsState> {
  AlertsCubit(this._alerts, this._phone, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const AlertsState());

  final AlertsRepository _alerts;
  final NowRepository _phone;
  final DateTime Function() _now;

  /// Reads the switches, quiet hours, the last background sync and whether
  /// notifications are allowed; again on coming back from Android's settings.
  Future<void> load() async {
    final on = await _alerts.switchesOn();
    final quiet = await _alerts.quietHours();
    final lastSync = await _alerts.lastSync();
    final allowed = await _alerts.notifier.enabled();
    if (!isClosed) {
      emit(
        AlertsState(
          loaded: true,
          on: on,
          quiet: quiet,
          lastSync: lastSync,
          notificationsAllowed: allowed,
        ),
      );
    }
  }

  Future<void> setSwitch(AlertSwitch alert, {required bool on}) async {
    emit(
      state.copyWith(
        on: {
          for (final other in state.on)
            if (other != alert) other,
          if (on) alert,
        },
      ),
    );
    await _alerts.setSwitch(alert, on: on);
    if (alert == AlertSwitch.holidays) {
      await _alerts.remindHolidays(
        await _phone.upcomingHolidays(),
        now: _now(),
      );
    }
    if (alert == AlertSwitch.power) {
      await _alerts.remindCuts(await _phone.powerNow(), now: _now());
    }
  }

  Future<void> setQuietHours(QuietHours quiet) async {
    emit(state.copyWith(quiet: quiet));
    await _alerts.setQuietHours(quiet);
  }
}
