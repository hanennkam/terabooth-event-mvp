import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/camera_contract.dart';
import 'package:terabooth_ipad/services/camera_pipeline.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  late Directory temp;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('terabooth_pipeline_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  CameraPipeline pipelineFor(TestCamera camera, {Duration? captureTimeout}) =>
      CameraPipeline(
        camera: camera,
        storage: StorageService(rootOverride: temp),
        captureTimeout: captureTimeout ?? const Duration(seconds: 2),
      );

  group('camera state machine', () {
    test('accepts valid connection and capture transitions', () {
      expect(
        CameraStateMachine.canTransitionConnection(
          CameraConnectionState.disconnected,
          CameraConnectionState.discovering,
        ),
        isTrue,
      );
      expect(
        CameraStateMachine.canTransitionConnection(
          CameraConnectionState.connecting,
          CameraConnectionState.connected,
        ),
        isTrue,
      );
      expect(
        CameraStateMachine.canTransitionCapture(
          CameraCaptureState.capturing,
          CameraCaptureState.transferring,
        ),
        isTrue,
      );
      expect(
        CameraStateMachine.canTransitionCapture(
          CameraCaptureState.transferring,
          CameraCaptureState.ready,
        ),
        isTrue,
      );
    });

    test('rejects invalid transitions', () {
      expect(
        () => CameraStateMachine.requireConnection(
          CameraConnectionState.disconnected,
          CameraConnectionState.connected,
        ),
        throwsA(isA<InvalidCameraStateTransition>()),
      );
      expect(
        () => CameraStateMachine.requireCapture(
          CameraCaptureState.idle,
          CameraCaptureState.transferring,
        ),
        throwsA(isA<InvalidCameraStateTransition>()),
      );
    });
  });

  test('connect exposes separate connection and capture state', () async {
    final camera = TestCamera(bytes: jpeg);
    final pipeline = pipelineFor(camera);
    addTearDown(pipeline.dispose);
    await pipeline.connect();
    expect(pipeline.connectionState, CameraConnectionState.connected);
    expect(pipeline.captureState, CameraCaptureState.idle);
    expect(pipeline.state.canCapture, isTrue);
  });

  test('capture is sequential and never overlaps', () async {
    final camera = TestCamera(bytes: jpeg)
      ..delay = const Duration(milliseconds: 25);
    final pipeline = pipelineFor(camera);
    addTearDown(pipeline.dispose);
    await pipeline.connect();

    final results = await Future.wait([
      pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 1),
      pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 2),
    ]);

    expect(results, hasLength(2));
    expect(camera.maxActive, 1);
    expect(camera.captureIds, hasLength(2));
    expect(camera.captureIds[0], isNot(camera.captureIds[1]));
  });

  test('duplicate capture for the same slot is rejected', () async {
    final camera = TestCamera(bytes: jpeg);
    final pending = Completer<CapturedImage>();
    camera.pending = pending;
    final pipeline = pipelineFor(camera);
    addTearDown(pipeline.dispose);
    await pipeline.connect();

    final first = pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 1);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 1),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.duplicateCapture,
        ),
      ),
    );
    expect(camera.captureIds, hasLength(1));

    pending.complete(camera.image(camera.captureIds.first));
    final saved = await first;
    expect(saved.path, isNotNull);
  });

  test('capture timeout fails without automatic retry', () async {
    final camera = TestCamera(bytes: jpeg);
    camera.pending = Completer<CapturedImage>();
    final pipeline = pipelineFor(
      camera,
      captureTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(pipeline.dispose);
    await pipeline.connect();

    await expectLater(
      pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 1),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.captureTimeout,
        ),
      ),
    );

    expect(camera.captureIds, hasLength(1));
    expect(pipeline.connectionState, CameraConnectionState.connected);
    expect(pipeline.captureState, CameraCaptureState.failed);
  });

  test(
    'late image after timeout cannot complete the expired capture',
    () async {
      final camera = TestCamera(bytes: jpeg);
      final pending = Completer<CapturedImage>();
      camera.pending = pending;
      final pipeline = pipelineFor(
        camera,
        captureTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(pipeline.dispose);
      await pipeline.connect();

      await expectLater(
        pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 1),
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.captureTimeout,
          ),
        ),
      );
      final captureId = camera.captureIds.single!;
      pending.complete(camera.image(captureId));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(pipeline.captureState, CameraCaptureState.failed);
      expect(
        await StorageService(rootOverride: temp).listOriginals('evt', 'ses'),
        isEmpty,
      );
    },
  );

  test(
    'disconnect during capture fails the capture, never reports success',
    () async {
      final camera = TestCamera(bytes: jpeg);
      final pending = Completer<CapturedImage>();
      camera.pending = pending;
      final pipeline = pipelineFor(camera);
      addTearDown(pipeline.dispose);
      await pipeline.connect();

      final capture = pipeline.capture(
        eventId: 'evt',
        sessionId: 'ses',
        slot: 1,
      );
      await Future<void>.delayed(Duration.zero);
      pipeline.notifyDisconnected(message: 'USB removed');

      await expectLater(
        capture,
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.disconnected,
          ),
        ),
      );
      expect(pipeline.connectionState, CameraConnectionState.failed);
      expect(pipeline.captureState, CameraCaptureState.failed);
      expect(
        await StorageService(rootOverride: temp).listOriginals('evt', 'ses'),
        isEmpty,
      );

      pending.complete(camera.image(camera.captureIds.first));
    },
  );

  test(
    'disconnect during image transfer fails without exposing success',
    () async {
      final gate = Completer<void>();
      final storage = _SlowStorage(root: temp, gate: gate);
      final camera = TestCamera(bytes: jpeg);
      final pipeline = CameraPipeline(
        camera: camera,
        storage: storage,
        captureTimeout: const Duration(seconds: 2),
      );
      addTearDown(pipeline.dispose);
      await pipeline.connect();

      final capture = pipeline.capture(
        eventId: 'evt',
        sessionId: 'ses',
        slot: 1,
      );
      for (
        var i = 0;
        i < 100 && pipeline.captureState != CameraCaptureState.transferring;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(pipeline.captureState, CameraCaptureState.transferring);

      pipeline.notifyDisconnected(message: 'USB removed during transfer');
      await expectLater(
        capture,
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.disconnected,
          ),
        ),
      );
      expect(pipeline.connectionState, CameraConnectionState.failed);
      expect(pipeline.captureState, CameraCaptureState.failed);
      gate.complete();
    },
  );

  test('capture failure leaves connection state separate', () async {
    final camera = TestCamera(bytes: jpeg)..failCapture = true;
    final pipeline = pipelineFor(camera);
    addTearDown(pipeline.dispose);
    await pipeline.connect();

    await expectLater(
      pipeline.capture(eventId: 'evt', sessionId: 'ses', slot: 1),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.captureFailed,
        ),
      ),
    );
    expect(pipeline.connectionState, CameraConnectionState.connected);
    expect(pipeline.captureState, CameraCaptureState.failed);
  });

  test(
    'background during capture fails the capture and does not auto-retry',
    () async {
      final camera = TestCamera(bytes: jpeg);
      final pending = Completer<CapturedImage>();
      camera.pending = pending;
      final pipeline = pipelineFor(camera);
      addTearDown(pipeline.dispose);
      await pipeline.connect();

      final capture = pipeline.capture(
        eventId: 'evt',
        sessionId: 'ses',
        slot: 1,
      );
      await Future<void>.delayed(Duration.zero);
      pipeline.handleAppBackgrounded();

      await expectLater(
        capture,
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.appBackgrounded,
          ),
        ),
      );
      expect(camera.captureIds, hasLength(1));
      expect(pipeline.connectionState, CameraConnectionState.recovering);
      expect(pipeline.captureState, CameraCaptureState.failed);
      pending.complete(camera.image(camera.captureIds.first));
    },
  );

  test('retake gets a new capture ID and a new original file', () async {
    final camera = TestCamera(bytes: jpeg);
    final pipeline = pipelineFor(camera);
    addTearDown(pipeline.dispose);
    await pipeline.connect();

    final first = await pipeline.capture(
      eventId: 'evt',
      sessionId: 'ses',
      slot: 1,
    );
    final retake = await pipeline.capture(
      eventId: 'evt',
      sessionId: 'ses',
      slot: 1,
    );

    expect(first.captureId, isNot(retake.captureId));
    expect(first.path, isNot(retake.path));
    expect(await File(first.path!).exists(), isTrue);
    expect(await File(retake.path!).exists(), isTrue);
    expect(
      await StorageService(rootOverride: temp).listOriginals('evt', 'ses'),
      hasLength(2),
    );
  });

  group('image ingestion', () {
    ImageIngestor ingestorFor() =>
        ImageIngestor(storage: StorageService(rootOverride: temp));

    Future<CapturedImage> ingest(
      ImageIngestor ingestor, {
      String captureId = 'cap_1',
      Uint8List? bytes,
      bool allowPng = true,
    }) {
      return ingestor.ingest(
        image: CapturedImage(
          id: captureId,
          bytes: bytes ?? jpeg,
          width: 1200,
          height: 1800,
          capturedAt: DateTime.now(),
          captureId: captureId,
        ),
        eventId: 'evt',
        sessionId: 'ses',
        slot: 1,
        captureId: captureId,
        allowPng: allowPng,
      );
    }

    test('valid JPEG is saved atomically and reopened', () async {
      final saved = await ingest(ingestorFor());
      expect(saved.path, isNotNull);
      expect(await File(saved.path!).readAsBytes(), equals(jpeg));
      expect(saved.width, 1200);
      expect(saved.height, 1800);
      expect(saved.captureId, 'cap_1');
    });

    test('duplicate image delivery is rejected', () async {
      final ingestor = ingestorFor();
      await ingest(ingestor);
      await expectLater(
        ingest(ingestor),
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.duplicateImage,
          ),
        ),
      );
      expect(ingestor.acceptedCaptureIds, {'cap_1'});
      expect(
        await StorageService(rootOverride: temp).listOriginals('evt', 'ses'),
        hasLength(1),
      );
    });

    test(
      'duplicate delivery is rejected after a new ingestor instance',
      () async {
        final storage = StorageService(rootOverride: temp);
        await ingest(ImageIngestor(storage: storage));
        await expectLater(
          ingest(ImageIngestor(storage: storage)),
          throwsA(
            isA<CameraPipelineException>().having(
              (e) => e.code,
              'code',
              CameraErrorCodes.duplicateImage,
            ),
          ),
        );
      },
    );

    test('invalid image data is rejected', () async {
      await expectLater(
        ingest(ingestorFor(), bytes: Uint8List.fromList([0, 1, 2, 3])),
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.invalidImage,
          ),
        ),
      );
    });

    test('low-resolution image is rejected', () async {
      final small = await File('test/fixtures/small_100x100.jpg').readAsBytes();
      await expectLater(
        ingest(ingestorFor(), bytes: Uint8List.fromList(small)),
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.invalidImage,
          ),
        ),
      );
    });

    test('PNG is rejected for a native camera', () async {
      final pngLike = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        ...List<int>.filled(2048, 0),
      ]);
      await expectLater(
        ingest(ingestorFor(), bytes: pngLike, allowPng: false),
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.unsupportedImage,
          ),
        ),
      );
    });

    test('storage failure is explicit', () async {
      final blocker = File('${temp.path}/not-a-directory');
      await blocker.writeAsString('x');
      final ingestor = ImageIngestor(
        storage: StorageService(rootOverride: Directory(blocker.path)),
      );
      await expectLater(
        ingest(ingestor),
        throwsA(
          isA<CameraPipelineException>().having(
            (e) => e.code,
            'code',
            CameraErrorCodes.storageFailed,
          ),
        ),
      );
    });
  });
}

class _SlowStorage extends StorageService {
  _SlowStorage({required Directory root, required this.gate})
    : super(rootOverride: root);

  final Completer<void> gate;

  @override
  Future<String> saveOriginal({
    required String eventId,
    required String sessionId,
    required int index,
    required Uint8List bytes,
    String? captureId,
    String extension = 'jpg',
  }) async {
    await gate.future;
    return super.saveOriginal(
      eventId: eventId,
      sessionId: sessionId,
      index: index,
      bytes: bytes,
      captureId: captureId,
      extension: extension,
    );
  }
}
