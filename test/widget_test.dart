import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:herway/main.dart';

void main() {
  testWidgets('renders the safety dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const HerWayApp(firebaseReady: true));

    expect(find.text('Good evening, Alex'), findsOneWidget);
    expect(find.text('CALL EMERGENCY SERVICES (112)'), findsOneWidget);
    expect(find.text('PRESS TO INFORM INNER CIRCLE'), findsOneWidget);
    expect(find.text('Your safety circle'), findsOneWidget);
    expect(find.text('Record audio or video'), findsOneWidget);
  });

  testWidgets('opens the visible local recording screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HerWayApp(firebaseReady: true));

    await tester.ensureVisible(find.text('Record audio or video'));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Private recordings'), findsOneWidget);
    expect(
      find.textContaining(
          'Recording is visible and only starts when you press Record.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('saved privately inside HerWay on this device'),
      findsOneWidget,
    );
    expect(find.text('SAVED PRIVATELY IN HERWAY'), findsOneWidget);
    expect(find.text('Tap a saved recording to play it.'), findsOneWidget);
    expect(find.byTooltip('Share with a trusted contact'), findsNothing);
  });

  testWidgets('shows user details, trusted contacts, and nearby safe places',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HerWayApp(firebaseReady: true));

    await tester.tap(find.text('Profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Your safety details'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Trusted contacts'), findsOneWidget);
    expect(find.text('No trusted contacts yet. Add someone you trust.'),
        findsOneWidget);
    expect(find.text('Nearby safe places'), findsOneWidget);
  });

  testWidgets('simulates an incoming call and allows answering it',
      (WidgetTester tester) async {
    var ringtoneCount = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemSound.play') ringtoneCount++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const HerWayApp(firebaseReady: true));

    await tester.ensureVisible(find.text('Set up'));
    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('In 30 seconds'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Right now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set call'));
    await tester.pumpAndSettle();

    expect(find.text('Incoming call · mobile'), findsOneWidget);
    expect(ringtoneCount, greaterThan(0));
    await tester.tap(find.byIcon(Icons.call_rounded));
    await tester.pump();
    expect(find.text('00:00'), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
    final ringtoneCountAfterAnswer = ringtoneCount;
    await tester.pump(const Duration(seconds: 3));
    expect(ringtoneCount, ringtoneCountAfterAnswer);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Good evening, Alex'), findsOneWidget);
  });
}
