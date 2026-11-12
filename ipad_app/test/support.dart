import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/camera_service.dart';

Future<Uint8List> loadJpegFixture() async {
  final bytes = await File('test/fixtures/sample_1200x1800.jpg').readAsBytes();
  return Uint8List.fromList(bytes);
}

class TestCamera implements CameraService {
  TestCamera({required this.bytes, this.isSimulated = true});

  final Uint8List bytes;

  @override
  final bool isSimulated;

  final List<String?> captureIds = [];
  Completer<CapturedImage>? pending;
  Duration? delay;
  bool failConnect = false;
  bool failCapture = false;
  int active = 0;
  int maxActive = 0;

  @override
  String get name => 'Test Camera';

  @override
  Future<void> connect() async {
    if (failConnect) throw StateError('test connect failure');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<CapturedImage> capture({String? captureId}) async {
    captureIds.add(captureId);
    active++;
    maxActive = math.max(maxActive, active);
    try {
      if (delay != null) await Future<void>.delayed(delay!);
      if (pending != null) return await pending!.future;
      if (failCapture) throw StateError('test capture failure');
      return image(captureId);
    } finally {
      active--;
    }
  }

  CapturedImage image(String? captureId) {
    final id = captureId ?? 'test_${captureIds.length}';
    return CapturedImage(
      id: id,
      bytes: bytes,
      width: 1200,
      height: 1800,
      capturedAt: DateTime.now(),
      captureId: id,
    );
  }
}
