import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/camera_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  test('3-photo capture, review, retake and approve regression', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_controller_');
    addTearDown(() => temp.delete(recursive: true));
    final camera = TestCamera(bytes: jpeg);
    final client = MockClient((request) async {
      if (request.url.path == '/v1/print-jobs') {
        return http.Response(
          '{"job_id":"job_1","state":"queued","completion":"unknown","attempts":0,"delivery_url":"http://x/d/t"}',
          202,
        );
      }
      return http.Response(
        '{"job_id":"job_1","state":"completed","completion":"confirmed","attempts":1,"delivery_url":"http://x/d/t"}',
        200,
      );
    });
    final controller = BoothController(
      camera: camera,
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x', client: client),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
      captureTimeout: const Duration(seconds: 2),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    expect(controller.phase, BoothPhase.review);
    expect(controller.photos, hasLength(3));
    expect(camera.captureIds, hasLength(3));
    expect(camera.captureIds.toSet(), hasLength(3));
    for (final photo in controller.photos) {
      expect(photo.path, isNotNull);
      expect(photo.captureId, isNotNull);
      expect(File(photo.path!).existsSync(), isTrue);
      expect(await File(photo.path!).readAsBytes(), equals(jpeg));
    }

    final originalPath = controller.photos[1].path;
    final originalCaptureId = controller.photos[1].captureId;
    await controller.retakeOne(1);
    expect(controller.phase, BoothPhase.review);
    expect(controller.photos[1].captureId, isNot(originalCaptureId));
    expect(controller.photos[1].path, isNot(originalPath));
    expect(File(originalPath!).existsSync(), isTrue);
    expect(File(controller.photos[1].path!).existsSync(), isTrue);

    await controller.approve();
    expect(controller.phase, BoothPhase.done);
    expect(controller.job?.state, 'completed');
  });

  test(
    'mock camera workflow still works and retake-all creates a new session',
    () async {
      final temp = await Directory.systemTemp.createTemp('terabooth_mock_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = BoothController(
        camera: const MockCameraService(),
        storage: StorageService(rootOverride: temp),
        bridge: BridgeClient(baseUrl: 'http://x'),
        countdownDelay: Duration.zero,
        captureTimeout: const Duration(seconds: 5),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      expect(controller.phase, BoothPhase.review);
      expect(controller.photos, hasLength(3));
      final firstSession = controller.sessionId;
      final firstIds = controller.photos.map((p) => p.captureId).toList();
      for (final photo in controller.photos) {
        expect(photo.path, endsWith('.png'));
        expect(File(photo.path!).existsSync(), isTrue);
      }

      await controller.retakeAll();
      expect(controller.phase, BoothPhase.review);
      expect(controller.photos, hasLength(3));
      expect(controller.sessionId, isNot(firstSession));
      expect(
        controller.photos.map((p) => p.captureId).toList(),
        isNot(firstIds),
      );
    },
  );

  test('disconnect during capture surfaces an error, not a review', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_disconnect_');
    addTearDown(() => temp.delete(recursive: true));
    final camera = TestCamera(bytes: jpeg)
      ..delay = const Duration(milliseconds: 50);
    final controller = BoothController(
      camera: camera,
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
      countdownDelay: Duration.zero,
      captureTimeout: const Duration(seconds: 2),
    );
    addTearDown(controller.dispose);

    final future = controller.startSession();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.cameraPipeline.notifyDisconnected(message: 'USB unplugged');
    await future;

    expect(controller.phase, BoothPhase.error);
    expect(controller.photos, isEmpty);
    expect(controller.error, contains('USB unplugged'));
  });
}
