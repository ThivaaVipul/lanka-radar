import 'package:lanka_radar/core/data/now_data.dart';
import 'package:lanka_radar/core/home_screen_widget.dart';

/// Keeps what the home-screen widget is given.
class FakeHomeScreenWidget extends HomeScreenWidget {
  final shown = <NowData>[];

  @override
  Future<void> show(NowData now) async => shown.add(now);
}
