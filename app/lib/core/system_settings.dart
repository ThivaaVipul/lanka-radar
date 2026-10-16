import 'package:flutter/services.dart';

/// Opens the app's own pages in Android's settings (handled in MainActivity).
class SystemSettings {
  const SystemSettings();

  static const _channel = MethodChannel('app.lankaradar/settings');

  /// App info, with battery use (and Autostart on Xiaomi phones).
  Future<void> openApp() => _channel.invokeMethod<void>('app');

  /// The app's notification settings.
  Future<void> openNotifications() =>
      _channel.invokeMethod<void>('notifications');
}
