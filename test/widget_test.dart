import 'package:flutter_test/flutter_test.dart';
import 'package:cold_streets/main.dart';

void main() {
  testWidgets('Cold Streets opens on the login screen', (tester) async {
    await tester.pumpWidget(const ColdStreetsApp());

    // The app launches in AuthView, not the post-login dashboard.
    expect(find.text('COLD STREETS'), findsOneWidget);
    expect(find.text('ENTER THE SYNDICATE'), findsOneWidget);
  });
}
