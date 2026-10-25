import 'package:flutter_test/flutter_test.dart';

import 'package:herway/main.dart';

void main() {
  testWidgets('renders the safety dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const HerWayApp(firebaseReady: true));

    expect(find.text('Good evening, Alex'), findsOneWidget);
    expect(find.text('CALL EMERGENCY SERVICES (112)'), findsOneWidget);
    expect(find.text('PRESS TO INFORM INNER CIRCLE'), findsOneWidget);
    expect(find.text('Your safety circle'), findsOneWidget);
  });
}
