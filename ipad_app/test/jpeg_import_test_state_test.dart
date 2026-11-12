import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/camera_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';
import 'package:terabooth_ipad/templates/builtin_templates.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  late Directory temp;
  setUpAll(() async => jpeg = await loadJpegFixture());
  setUp(() async => temp = await Directory.systemTemp.createTemp('tb_import_'));
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('import preparation creates an isolated solo review, no submission', () {
    final controller = BoothController(
      camera: const MockCameraService(),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://127.0.0.1:8787'),
    );
    addTearDown(controller.dispose);
    final image = CapturedImage(
      id: 'test_1',
      bytes: jpeg,
      width: 1200,
      height: 1800,
      capturedAt: DateTime.now(),
      captureId: 'test_1',
      sha256: 'a' * 64,
    );
    controller.prepareImportedTestReview(
      image: image,
      testEventId: 'evt_import_1',
      testSessionId: 'ses_import_1',
    );
    expect(controller.phase, BoothPhase.review);
    expect(controller.photos, hasLength(1));
    expect(controller.expectedPhotoCount, 1);
    expect(controller.sessionTemplate?.id, BuiltinTemplates.solo.id);
    expect(controller.job, isNull);
  });

  test('bridge job parses original image hashes for preservation check', () {
    final job = PrintJob.fromJson({
      'job_id': 'job_1',
      'state': 'completed',
      'completion': 'confirmed',
      'attempts': 1,
      'images': [
        {'sha256': 'abc123', 'width': 1200, 'height': 1800},
      ],
    });
    expect(job.imageHashes, ['abc123']);
  });
}
