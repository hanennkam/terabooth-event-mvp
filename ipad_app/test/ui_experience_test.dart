import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/screens/capture_screen.dart';
import 'package:terabooth_ipad/screens/print_screen.dart';
import 'package:terabooth_ipad/screens/welcome_screen.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  BoothController controllerFor(Directory temp, {BridgeClient? bridge}) {
    return BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: bridge ?? BridgeClient(baseUrl: 'http://x'),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
  }

  void useLandscape(WidgetTester tester) {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  test('settings persistence reloads the bridge URL', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_settings_');
    addTearDown(() => temp.delete(recursive: true));
    final first = controllerFor(temp);
    addTearDown(first.dispose);
    await first.saveBridgeUrl('http://192.168.8.77:8787');
    expect(first.bridge.baseUrl, 'http://192.168.8.77:8787');

    final second = controllerFor(temp);
    addTearDown(second.dispose);
    await second.loadSettings();
    expect(second.bridge.baseUrl, 'http://192.168.8.77:8787');
  });

  test(
    'empty persisted event catalog disables the booth event state',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'terabooth_empty_catalog_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);
      await controller.loadEvents();
      expect(controller.hasSelectedEvent, isFalse);
      expect(controller.events, isEmpty);
    },
  );

  test('bridge health exposes reported printer state', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_health_');
    addTearDown(() => temp.delete(recursive: true));
    final bridge = BridgeClient(
      baseUrl: 'http://x',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'service': 'terabooth-print',
            'version': '0.1.0',
            'printer': {
              'name': 'Mock Printer',
              'state': 'ready',
              'mode': 'mock',
              'note': 'NOT a physical printer',
            },
          }),
          200,
        );
      }),
    );
    final controller = controllerFor(temp, bridge: bridge);
    addTearDown(controller.dispose);
    await controller.checkBridge();
    expect(controller.bridgeCheckError, isNull);
    expect(controller.bridgeHealth?.service, 'terabooth-print');
    expect(controller.bridgeHealth?.printer['mode'], 'mock');
    expect(
      controller.bridgeHealth?.printer['note'],
      contains('NOT a physical'),
    );
  });

  testWidgets('empty event state is clear and actionable', (tester) async {
    useLandscape(tester);
    final temp = Directory('/tmp');
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    await tester.runAsync(() => controller.loadEvents());
    expect(controller.hasSelectedEvent, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WelcomeScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No event selected'), findsOneWidget);
    expect(find.text('Create event'), findsOneWidget);
    expect(find.text('Start Session'), findsOneWidget);
    expect(find.textContaining('SIMULATED CAMERA'), findsOneWidget);
  });

  testWidgets('offline submitted job is visible and blocks a new session', (
    tester,
  ) async {
    useLandscape(tester);
    final controller = controllerFor(Directory('/tmp'));
    addTearDown(controller.dispose);
    controller.submittedJob = SubmittedJob(
      eventId: 'evt_demo',
      sessionId: 'ses_1',
      jobId: 'job_offline',
      submittedAt: DateTime.now(),
      deliveryUrl: 'http://x/d/token',
    );
    controller.submittedJobError = 'bridge offline';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WelcomeScreen(controller: controller)),
      ),
    );
    await tester.pump();
    expect(
      find.text('Submitted print job awaits reconciliation.'),
      findsOneWidget,
    );
    expect(find.text('Refresh status'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(
      find.text('Resolve the previous submitted job first'),
      findsOneWidget,
    );
  });

  testWidgets('welcome opens settings and reports diagnostics', (tester) async {
    useLandscape(tester);
    final temp = Directory('/tmp');
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WelcomeScreen(controller: controller)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Bridge URL'), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.textContaining('SIMULATED'), findsAtLeastNWidgets(1));
  });

  testWidgets('capture screen shows progress and simulated status', (
    tester,
  ) async {
    useLandscape(tester);
    final temp = Directory('/tmp');
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    controller.phase = BoothPhase.capturing;
    controller.activePhoto = 2;
    controller.photos = [
      CapturedImage(
        id: 'cap_1',
        bytes: jpeg,
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
        captureId: 'cap_1',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CaptureScreen(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.text('CAPTURE 2 OF 3'), findsOneWidget);
    expect(find.text('Photo 2'), findsOneWidget);
    expect(find.textContaining('SIMULATED CAMERA'), findsOneWidget);
    expect(find.text('1/3 captured'), findsOneWidget);
  });

  testWidgets('mock printer completion never claims a physical print', (
    tester,
  ) async {
    useLandscape(tester);
    final controller = controllerFor(Directory('/tmp'));
    addTearDown(controller.dispose);
    controller.phase = BoothPhase.done;
    controller.job = const PrintJob(
      id: 'job_mock',
      state: 'completed',
      completion: 'confirmed',
      attempts: 1,
      printerMode: 'mock',
      deliveryUrl: 'http://192.168.8.50:8787/d/token',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrintScreen(controller: controller)),
      ),
    );
    await tester.pump();
    expect(
      find.text('Mock print complete — no physical print'),
      findsOneWidget,
    );
    expect(find.text('Printed — take your strip'), findsNothing);
    expect(find.text('MOCK PRINTER'), findsOneWidget);
  });

  testWidgets('unknown print status is terminal and warns before reprint', (
    tester,
  ) async {
    useLandscape(tester);
    final temp = Directory('/tmp');
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    controller.phase = BoothPhase.done;
    controller.job = const PrintJob(
      id: 'job_unknown',
      state: 'unknown',
      completion: 'unknown',
      attempts: 1,
      deliveryUrl: 'http://192.168.8.50:8787/d/token',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PrintScreen(controller: controller)),
      ),
    );
    await tester.pump();

    expect(find.text('Print status unknown'), findsOneWidget);
    expect(find.text('Retry print (new job)'), findsOneWidget);
    expect(
      find.textContaining('Do not resubmit automatically'),
      findsOneWidget,
    );
    expect(find.text('job_unknown'), findsOneWidget);
  });
}
