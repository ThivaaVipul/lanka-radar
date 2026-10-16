import 'package:flutter_test/flutter_test.dart';
import 'package:lanka_radar/app/app.dart';

void main() {
  testWidgets('opens on the empty home screen', (tester) async {
    await tester.pumpWidget(const LankaRadarApp());

    expect(find.text('Lanka Radar'), findsOneWidget);
    expect(find.text('Nothing yet'), findsOneWidget);
  });
}
