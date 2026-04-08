import 'package:flutter_test/flutter_test.dart';
import 'package:cold_streets/main.dart'; // Adjust if your package name is different

void main() {
  testWidgets('Dashboard UI Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ColdStreetsApp());

    // Verify that our Dirty Cash counter starts at $1.
    expect(find.text('\$1'), findsOneWidget);
  });
}