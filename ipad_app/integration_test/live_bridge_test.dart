import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terabooth_ipad/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Timed out waiting for $finder');
  }

  testWidgets('live HTTP event -> capture -> print -> composition', (
    tester,
  ) async {
    const bridgeUrl = String.fromEnvironment('TERABOOTH_BRIDGE_URL');
    const apiToken = String.fromEnvironment('TERABOOTH_API_TOKEN');
    expect(bridgeUrl, isNotEmpty, reason: 'Pass TERABOOTH_BRIDGE_URL');
    expect(apiToken, isNotEmpty, reason: 'Pass TERABOOTH_API_TOKEN');

    await tester.pumpWidget(const TeraboothApp());
    await tester.pump();
    // Create/select a fresh event through the real UI.
    await tester.tap(find.text('Change event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create new event'));
    await tester.pumpAndSettle();
    final eventFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(eventFields.at(0), 'Live Integration Event');
    await tester.enterText(eventFields.at(1), '10 Nov 2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await waitFor(
      tester,
      find.text('Live Integration Event'),
      timeout: const Duration(seconds: 10),
    );

    final startFinder = find.widgetWithText(FilledButton, 'Start Session');
    await tester.ensureVisible(startFinder.first);
    await tester.tap(startFinder.first);
    await tester.pump(const Duration(seconds: 2));
    await waitFor(
      tester,
      find.text('Approve & Print'),
      timeout: const Duration(seconds: 60),
    );

    await tester.tap(find.text('Approve & Print'));
    await waitFor(
      tester,
      find.text('View final composition'),
      timeout: const Duration(seconds: 60),
    );
    await waitFor(
      tester,
      find.textContaining('Mock print complete'),
      timeout: const Duration(seconds: 10),
    );
    expect(find.textContaining('no physical print'), findsOneWidget);
    expect(find.textContaining('Print failed'), findsNothing);
    expect(find.textContaining('status unknown'), findsNothing);
    expect(find.byType(SelectableText), findsAtLeastNWidgets(1));
    await waitFor(
      tester,
      find.text('View animated GIF'),
      timeout: const Duration(seconds: 60),
    );
  });
}
