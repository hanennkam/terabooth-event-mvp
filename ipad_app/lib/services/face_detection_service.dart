import 'dart:io';

import 'package:flutter/services.dart';

import '../crop/crop_models.dart';

abstract class FaceDetector {
  Future<FaceDetectionResult> detect(Uint8List bytes);
}

class NoopFaceDetector implements FaceDetector {
  const NoopFaceDetector();

  @override
  Future<FaceDetectionResult> detect(Uint8List bytes) async =>
      const FaceDetectionResult(
        error: 'Vision is unavailable on this platform',
      );
}

class VisionFaceDetector implements FaceDetector {
  static const MethodChannel _channel = MethodChannel('com.terabooth/vision');
  const VisionFaceDetector();

  @override
  Future<FaceDetectionResult> detect(Uint8List bytes) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('detectFaces', {
        'bytes': bytes,
      });
      final faces = <FaceBox>[];
      for (final item in result ?? const <dynamic>[]) {
        if (item is! Map) continue;
        final map = item.cast<Object?, Object?>();
        final x = (map['x'] as num?)?.toDouble();
        final y = (map['y'] as num?)?.toDouble();
        final w = (map['w'] as num?)?.toDouble();
        final h = (map['h'] as num?)?.toDouble();
        final confidence = (map['confidence'] as num?)?.toDouble();
        if (x == null || y == null || w == null || h == null) continue;
        try {
          final rect = NormalizedRect(x: x, y: y, width: w, height: h)
            ..validate();
          faces.add(FaceBox(box: rect, confidence: confidence ?? 0));
        } on CropValidationException {
          continue;
        }
      }
      return FaceDetectionResult(faces: faces);
    } on MissingPluginException {
      return const FaceDetectionResult(error: 'Vision plugin not installed');
    } on PlatformException catch (e) {
      return FaceDetectionResult(error: e.message ?? e.code);
    } catch (e) {
      return FaceDetectionResult(error: e.toString());
    }
  }
}

class FixtureFaceDetector implements FaceDetector {
  final List<FaceBox> faces;
  final Object? error;

  const FixtureFaceDetector({this.faces = const [], this.error});

  @override
  Future<FaceDetectionResult> detect(Uint8List bytes) async {
    if (error != null) return FaceDetectionResult(error: error.toString());
    return FaceDetectionResult(faces: faces);
  }
}

FaceDetector defaultFaceDetector() {
  if (Platform.isIOS) return const VisionFaceDetector();
  return const NoopFaceDetector();
}
