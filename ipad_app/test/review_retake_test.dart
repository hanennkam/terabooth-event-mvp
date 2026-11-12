import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/screens/review_screen.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

class RecordingController extends BoothController {
  RecordingController({
    required super.camera,
    required super.storage,
    required super.bridge,
  });

  final List<int> retakes = [];
  int retakeAllCount = 0;

  @override
  Future<void> retakeOne(int index) async {
    retakes.add(index);
  }

  @override
  Future<void> retakeAll() async {
    retakeAllCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  late Directory temp;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('terabooth_ui_retake_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  testWidgets('event review presents Retake All only', (tester) async {
    final controller = RecordingController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
    );
    addTearDown(controller.dispose);
    controller.photos = [
      for (var i = 0; i < 3; i++)
        CapturedImage(
          id: 'cap_$i',
          bytes: jpeg,
          width: 1200,
          height: 1800,
          capturedAt: DateTime.now(),
          captureId: 'cap_$i',
        ),
    ];
    controller.sessionId = 'ses';
    controller.phase = BoothPhase.review;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReviewScreen(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.text('Retake 1'), findsNothing);
    expect(find.text('Retake 2'), findsNothing);
    expect(find.text('Retake 3'), findsNothing);
    expect(find.text('Retake all'), findsOneWidget);

    await tester.tap(find.text('Retake all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retake all photos'));
    await tester.pumpAndSettle();
    expect(controller.retakeAllCount, 1);
    expect(controller.retakes, isEmpty);
  });
}
