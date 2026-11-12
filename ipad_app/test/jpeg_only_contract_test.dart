import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    temp = await Directory.systemTemp.createTemp('terabooth_jpeg_contract_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  ImageIngestor ingestor() =>
      ImageIngestor(storage: StorageService(rootOverride: temp));

  Future<CapturedImage> ingest(
    Uint8List bytes, {
    String captureId = 'cap_1',
    bool allowPng = false,
  }) {
    return ingestor().ingest(
      image: CapturedImage(
        id: captureId,
        bytes: bytes,
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

  test(
    'valid original JPEG accepted and bytes/hash preserved exactly',
    () async {
      final saved = await ingest(jpeg);
      final file = File(saved.path!);
      final stored = await file.readAsBytes();
      expect(stored, equals(jpeg));
      expect(saved.sha256, sha256.convert(jpeg).toString());
      expect(sha256.convert(stored).toString(), saved.sha256);
      expect(saved.orientation, 1);
    },
  );

  test('CR2/RAW magic is rejected', () async {
    final cr2 = Uint8List(2048);
    cr2[0] = 0x49;
    cr2[1] = 0x49;
    cr2[2] = 0x2A;
    cr2[3] = 0x00;
    await expectLater(
      ingest(cr2),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.unsupportedImage,
        ),
      ),
    );
  });

  test('PNG is rejected for native camera', () async {
    final png = Uint8List.fromList([
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
      ingest(png),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.unsupportedImage,
        ),
      ),
    );
  });

  test('RAW content behind a .jpg/JPEG-looking contract is rejected', () async {
    // There is no filename/MIME trust in this path: content magic is decisive.
    final disguised = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE1, // JPEG-like prefix
      ...List<int>.filled(2048, 0x00),
      // no EOI
    ]);
    await expectLater(
      ingest(disguised),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.invalidImage,
        ),
      ),
    );
  });

  test('truncated JPEG without EOI is rejected', () async {
    final truncated = Uint8List.fromList(jpeg.sublist(0, jpeg.length - 2));
    await expectLater(
      ingest(truncated),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.invalidImage,
        ),
      ),
    );
  });

  test('empty payload is rejected', () async {
    await expectLater(
      ingest(Uint8List(0)),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.invalidImage,
        ),
      ),
    );
  });

  test('undersized JPEG dimensions are rejected', () async {
    final small = await File('test/fixtures/small_100x100.jpg').readAsBytes();
    await expectLater(
      ingest(Uint8List.fromList(small)),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.invalidImage,
        ),
      ),
    );
  });

  test('duplicate capture ID does not create a second original', () async {
    final storage = StorageService(rootOverride: temp);
    final processor = ImageIngestor(storage: storage);
    final image = CapturedImage(
      id: 'cap_same',
      bytes: jpeg,
      width: 1200,
      height: 1800,
      capturedAt: DateTime.now(),
      captureId: 'cap_same',
    );
    await processor.ingest(
      image: image,
      eventId: 'evt',
      sessionId: 'ses',
      slot: 1,
      captureId: 'cap_same',
      allowPng: false,
    );
    await expectLater(
      processor.ingest(
        image: image,
        eventId: 'evt',
        sessionId: 'ses',
        slot: 2,
        captureId: 'cap_same',
        allowPng: false,
      ),
      throwsA(
        isA<CameraPipelineException>().having(
          (e) => e.code,
          'code',
          CameraErrorCodes.duplicateImage,
        ),
      ),
    );
    expect(await storage.listOriginals('evt', 'ses'), hasLength(1));
  });

  test('native adapter transfers original data only; no preview fallback', () {
    final source = File(
      'ios/Runner/CascableCameraAdapter.swift',
    ).readAsStringSync();
    expect(source, contains('canProvide(.original)'));
    expect(source, contains('executeTransfer(for: .original)'));
    expect(source, contains('generateData(for: .original)'));
    expect(source, isNot(contains('executeTransfer(for: .preview)')));
    expect(source, isNot(contains('generateData(for: .preview)')));
  });
}
