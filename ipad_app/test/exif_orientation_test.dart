import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/camera_pipeline.dart';
import 'package:terabooth_ipad/services/exif_orientation.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads all eight EXIF orientations and effective dimensions', () async {
    final validator = ImageValidator(
      policy: const ImageValidationPolicy(
        minBytes: 1,
        minLongEdge: 1,
        minShortEdge: 1,
      ),
    );
    for (var orientation = 1; orientation <= 8; orientation++) {
      final bytes = await File(
        'test/fixtures/exif_o$orientation.jpg',
      ).readAsBytes();
      expect(
        ExifOrientation.readJpeg(Uint8List.fromList(bytes)),
        orientation,
        reason: 'parser orientation $orientation',
      );
      final result = await validator.validate(
        Uint8List.fromList(bytes),
        allowPng: true,
      );
      expect(result.orientation, orientation);
      expect(result.rawWidth, 120);
      expect(result.rawHeight, 180);
      if (orientation >= 5) {
        expect(result.width, 180, reason: 'effective width for $orientation');
        expect(result.height, 120, reason: 'effective height for $orientation');
      } else {
        expect(result.width, 120, reason: 'effective width for $orientation');
        expect(result.height, 180, reason: 'effective height for $orientation');
      }
    }
  });

  test('Flutter display codec applies EXIF orientation without recompression', () async {
    for (var orientation = 1; orientation <= 8; orientation++) {
      final bytes = await File(
        'test/fixtures/exif_o$orientation.jpg',
      ).readAsBytes();
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      expect(
        frame.image.width,
        orientation >= 5 ? 180 : 120,
        reason: 'display width for $orientation',
      );
      expect(
        frame.image.height,
        orientation >= 5 ? 120 : 180,
        reason: 'display height for $orientation',
      );
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('ingestion preserves bytes and stores effective orientation metadata', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_exif_');
    addTearDown(() => temp.delete(recursive: true));
    final bytes = await File('test/fixtures/exif_o6.jpg').readAsBytes();
    final ingestor = ImageIngestor(
      storage: StorageService(rootOverride: temp),
      validator: const ImageValidator(
        policy: ImageValidationPolicy(
          minBytes: 1,
          minLongEdge: 1,
          minShortEdge: 1,
        ),
      ),
    );
    final saved = await ingestor.ingest(
      image: CapturedImage(
        id: 'cap_exif',
        bytes: Uint8List.fromList(bytes),
        width: 120,
        height: 180,
        capturedAt: DateTime.now(),
        captureId: 'cap_exif',
      ),
      eventId: 'evt',
      sessionId: 'ses',
      slot: 1,
      captureId: 'cap_exif',
      allowPng: false,
    );
    expect(saved.orientation, 6);
    expect(saved.width, 180);
    expect(saved.height, 120);
    expect(await File(saved.path!).readAsBytes(), equals(bytes));
  });
}
