import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/screens/result_screen.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/share_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

class FakeShareService extends ShareService {
  final List<String> shared = [];
  @override
  Future<void> shareBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shared.add(filename);
  }
}

class AutoApproveController extends BoothController {
  AutoApproveController({
    required super.camera,
    required super.storage,
    required super.bridge,
  });
  int approveCalls = 0;
  @override
  Future<void> approve() async {
    approveCalls++;
    phase = BoothPhase.done;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  setUpAll(() async => jpeg = await loadJpegFixture());

  Future<BoothController> controller(Directory temp, http.Client client) async {
    final c = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x', client: client),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    c.phase = BoothPhase.done;
    c.compositionBytes = jpeg;
    c.sessionId = 'ses_test';
    c.job = const PrintJob(
      id: 'preview_1',
      state: 'completed',
      completion: 'preview',
      attempts: 0,
      printerMode: 'mock',
      gifState: 'pending',
    );
    return c;
  }

  testWidgets(
    'result exposes only GIF, AirDrop and Print with no QR/approval',
    (tester) async {
      tester.view.physicalSize = const Size(1180, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final temp = Directory.systemTemp.createTempSync('tb_result_');
      addTearDown(
        () => {if (temp.existsSync()) temp.deleteSync(recursive: true)},
      );
      final c = await controller(
        temp,
        MockClient((r) async => http.Response('{}', 200)),
      );
      addTearDown(c.dispose);
      final share = FakeShareService();
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(controller: c, shareService: share),
        ),
      );
      await tester.pump();
      expect(find.text('GIF'), findsOneWidget);
      expect(find.text('AirDrop'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.textContaining('QR'), findsNothing);
      expect(find.text('Approve & Print'), findsNothing);
      expect(find.text('Retake all'), findsNothing);
      await tester.tap(find.text('AirDrop'));
      await tester.pump();
      expect(share.shared.single, contains('terabooth-strip-'));
    },
  );

  testWidgets('GIF opens preview and only shares after explicit action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final temp = Directory.systemTemp.createTempSync('tb_result_gif_');
    addTearDown(
      () => {if (temp.existsSync()) temp.deleteSync(recursive: true)},
    );
    final c = await controller(
      temp,
      MockClient((r) async => http.Response('{}', 200)),
    );
    c.gifBytes = base64Decode(
      'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
    );
    addTearDown(c.dispose);
    final share = FakeShareService();
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(controller: c, shareService: share),
      ),
    );
    await tester.pump();
    expect(share.shared, isEmpty);
    await tester.tap(find.text('GIF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Animated GIF'), findsOneWidget);
    expect(find.text('AirDrop GIF'), findsOneWidget);
    expect(share.shared, isEmpty);
    await tester.tap(find.text('AirDrop GIF'));
    await tester.pump();
    expect(share.shared.single, endsWith('.gif'));
  });

  testWidgets('print quantity submits selected copies through reprint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final temp = Directory.systemTemp.createTempSync('tb_result_print_');
    addTearDown(
      () => {if (temp.existsSync()) temp.deleteSync(recursive: true)},
    );
    String? reprintUrl;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/reprint')) {
        reprintUrl = request.url.toString();
        return http.Response(
          jsonEncode({
            'job_id': 'print_2',
            'state': 'completed',
            'completion': 'confirmed',
            'attempts': 1,
            'printer_mode': 'mock',
            'copies': 2,
          }),
          202,
        );
      }
      return http.Response(
        jsonEncode({
          'job_id': 'print_2',
          'state': 'completed',
          'completion': 'confirmed',
          'attempts': 1,
          'printer_mode': 'mock',
          'copies': 2,
        }),
        200,
      );
    });
    final c = await controller(temp, client);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(controller: c, shareService: FakeShareService()),
      ),
    );
    await tester.tap(find.text('Print'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('How many prints?'), findsOneWidget);
    await tester.tap(find.text('2 copies'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Print').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(reprintUrl, contains('copies=2'));
  });

  testWidgets('review auto-advances without an approval action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final temp = Directory.systemTemp.createTempSync('tb_auto_approve_');
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    final c = AutoApproveController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(
        baseUrl: 'http://x',
        client: MockClient((r) async => http.Response('{}', 200)),
      ),
    );
    c.phase = BoothPhase.review;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AutoResultScreen(controller: c, shareService: FakeShareService()),
      ),
    );
    await tester.pump();
    expect(c.approveCalls, 1);
    expect(c.phase, BoothPhase.done);
  });
}
