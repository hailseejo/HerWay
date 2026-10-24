import 'package:flutter_test/flutter_test.dart';

import 'package:herway/main.dart';

void main() {
  testWidgets('renders the safety dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const HerWayApp(firebaseReady: true));

    expect(find.text('Good evening, Alex'), findsOneWidget);
    expect(find.text('PRESS & HOLD FOR SOS'), findsOneWidget);
    expect(find.text('Your safety circle'), findsOneWidget);
  });
}
