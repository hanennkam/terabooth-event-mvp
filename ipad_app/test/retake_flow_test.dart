import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  Future<(BoothController, TestCamera, Directory)> started({
    Duration captureTimeout = const Duration(seconds: 2),
  }) async {
    final temp = await Directory.systemTemp.createTemp('terabooth_retake_');
    final camera = TestCamera(bytes: jpeg);
    final controller = BoothController(
      camera: camera,
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
      countdownDelay: Duration.zero,
      captureTimeout: captureTimeout,
    );
    await controller.startSession();
    expect(controller.phase, BoothPhase.review);
    return (controller, camera, temp);
  }

  test('successful retake replaces only the selected slot', () async {
    final (controller, camera, temp) = await started();
    addTearDown(() => temp.delete(recursive: true));
    addTearDown(controller.dispose);

    final before = controller.photos.map((p) => p.captureId).toList();
    final oldPath = controller.photos[1].path;
    await controller.retakeOne(1);

    expect(controller.phase, BoothPhase.review);
    expect(controller.retakeError, isNull);
    expect(controller.retakingSlot, isNull);
    expect(controller.photos[0].captureId, before[0]);
    expect(controller.photos[2].captureId, before[2]);
    expect(controller.photos[1].captureId, isNot(before[1]));
    expect(controller.photos[1].path, isNot(oldPath));
    expect(await File(oldPath!).exists(), isTrue);
    expect(await File(controller.photos[1].path!).exists(), isTrue);
    expect(camera.captureIds.toSet(), hasLength(4));
  });

  test(
    'failed retake preserves the previous approved image and recovers',
    () async {
      final (controller, camera, temp) = await started();
      addTearDown(() => temp.delete(recursive: true));
      addTearDown(controller.dispose);

      final before = List<CapturedImage>.from(controller.photos);
      camera.failCapture = true;
      await controller.retakeOne(1);

      expect(controller.phase, BoothPhase.review);
      expect(controller.retakingSlot, isNull);
      expect(controller.retakeError, isNotNull);
      expect(controller.photos[1].captureId, before[1].captureId);
      expect(controller.photos[1].path, before[1].path);
      expect(await File(before[1].path!).exists(), isTrue);

      camera.failCapture = false;
      await controller.retakeOne(1);
      expect(controller.phase, BoothPhase.review);
      expect(controller.retakeError, isNull);
      expect(controller.photos[1].captureId, isNot(before[1].captureId));
    },
  );

  test('failed metadata write restores the previous slot', () async {
    final (controller, camera, temp) = await started();
    addTearDown(() => temp.delete(recursive: true));
    addTearDown(controller.dispose);

    final before = controller.photos[1];
    // Make the session metadata path unwritable after the capture succeeds.
    final sessionDir = Directory(
      '${temp.path}/events/evt_demo/sessions/${controller.sessionId}',
    );
    final metadata = File('${sessionDir.path}/session.json');
    await metadata.delete();
    await Directory(metadata.path).create(recursive: true);

    await controller.retakeOne(1);
    expect(controller.phase, BoothPhase.review);
    expect(controller.retakeError, isNotNull);
    expect(controller.photos[1].captureId, before.captureId);
    expect(controller.photos[1].path, before.path);
  });

  test('retake timeout leaves the slot unchanged', () async {
    final (controller, camera, temp) = await started(
      captureTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(() => temp.delete(recursive: true));
    addTearDown(controller.dispose);

    final before = controller.photos[1];
    final pending = Completer<CapturedImage>();
    camera.pending = pending;
    await controller.retakeOne(1);

    expect(controller.phase, BoothPhase.review);
    expect(controller.retakeError, contains('timed out'));
    expect(controller.photos[1].captureId, before.captureId);
    expect(controller.photos[1].path, before.path);
    pending.complete(camera.image(camera.captureIds.last));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.photos[1].captureId, before.captureId);
  });

  test('late image after retake timeout cannot overwrite the slot', () async {
    final (controller, camera, temp) = await started(
      captureTimeout: const Duration(milliseconds: 40),
    );
    addTearDown(() => temp.delete(recursive: true));
    addTearDown(controller.dispose);

    final before = List<CapturedImage>.from(controller.photos);
    final pending = Completer<CapturedImage>();
    camera.pending = pending;
    await controller.retakeOne(1);
    final late = camera.image(camera.captureIds.last);
    pending.complete(late);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.photos[1].captureId, before[1].captureId);
    expect(controller.photos[1].path, before[1].path);
    expect(controller.photos[0].captureId, before[0].captureId);
    expect(controller.photos[2].captureId, before[2].captureId);
    expect(
      await StorageService(
        rootOverride: temp,
      ).listOriginals('evt_demo', controller.sessionId!),
      hasLength(3),
    );
  });

  test('repeated retakes use new IDs and never touch other slots', () async {
    final (controller, camera, temp) = await started();
    addTearDown(() => temp.delete(recursive: true));
    addTearDown(controller.dispose);

    final before = controller.photos.map((p) => p.captureId).toList();
    await controller.retakeOne(0);
    final firstRetake = controller.photos[0];
    await controller.retakeOne(0);
    final secondRetake = controller.photos[0];

    expect(firstRetake.captureId, isNot(before[0]));
    expect(secondRetake.captureId, isNot(firstRetake.captureId));
    expect(secondRetake.path, isNot(firstRetake.path));
    expect(controller.photos[1].captureId, before[1]);
    expect(controller.photos[2].captureId, before[2]);
    expect(await File(firstRetake.path!).exists(), isTrue);
    expect(await File(secondRetake.path!).exists(), isTrue);
    expect(camera.captureIds.toSet(), hasLength(5));
  });
}
