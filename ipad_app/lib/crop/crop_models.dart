import 'dart:math' as math;

class CropValidationException implements Exception {
  final String message;
  const CropValidationException(this.message);
  @override
  String toString() => message;
}

enum CropMode { smart, fit, manual }

extension CropModeJson on CropMode {
  String get wireName => switch (this) {
    CropMode.smart => 'smart',
    CropMode.fit => 'fit',
    CropMode.manual => 'manual',
  };

  static CropMode fromWire(String value) => switch (value) {
    'smart' => CropMode.smart,
    'fit' => CropMode.fit,
    'manual' => CropMode.manual,
    _ => throw CropValidationException('unknown crop mode: $value'),
  };
}

class NormalizedRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const NormalizedRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  static const full = NormalizedRect(x: 0, y: 0, width: 1, height: 1);

  void validate() {
    if (![x, y, width, height].every((v) => v.isFinite)) {
      throw const CropValidationException('crop values must be finite');
    }
    if (width <= 0 || height <= 0) {
      throw const CropValidationException(
        'crop width and height must be positive',
      );
    }
    if (x < -0.0001 ||
        y < -0.0001 ||
        x + width > 1.0001 ||
        y + height > 1.0001) {
      throw const CropValidationException(
        'crop rectangle is outside the image',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'x': _round(x),
    'y': _round(y),
    'w': _round(width),
    'h': _round(height),
  };

  static double _round(double value) =>
      double.parse(value.clamp(0.0, 1.0).toStringAsFixed(6));

  factory NormalizedRect.fromJson(Map<String, dynamic> json) {
    final rect = NormalizedRect(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['w'] as num?)?.toDouble() ?? 0,
      height: (json['h'] as num?)?.toDouble() ?? 0,
    );
    rect.validate();
    return rect;
  }
}

class FaceBox {
  final NormalizedRect box;
  final double confidence;

  const FaceBox({required this.box, required this.confidence});
}

class FaceDetectionResult {
  final List<FaceBox> faces;
  final String? error;

  const FaceDetectionResult({this.faces = const [], this.error});

  bool get unavailable => error != null;
}

class CropDecision {
  final String imageId;
  final String slotId;
  final String templateId;
  final int templateVersion;
  final CropMode mode;
  final NormalizedRect rect;
  final double zoom;
  final double offsetX;
  final double offsetY;
  final int faceCount;
  final String? fallbackReason;
  final DateTime updatedAt;

  const CropDecision({
    required this.imageId,
    required this.slotId,
    required this.templateId,
    required this.templateVersion,
    required this.mode,
    required this.rect,
    this.zoom = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.faceCount = 0,
    this.fallbackReason,
    required this.updatedAt,
  });

  void validate() {
    if (imageId.isEmpty || slotId.isEmpty || templateId.isEmpty) {
      throw const CropValidationException('crop identity fields are required');
    }
    if (templateVersion < 1) {
      throw const CropValidationException('template version must be >= 1');
    }
    if (!zoom.isFinite || zoom < 1 || zoom > 3) {
      throw const CropValidationException('zoom must be between 1 and 3');
    }
    if (!offsetX.isFinite || !offsetY.isFinite) {
      throw const CropValidationException('offset must be finite');
    }
    rect.validate();
  }

  Map<String, dynamic> toJson() => {
    'image_id': imageId,
    'slot_id': slotId,
    'template_id': templateId,
    'template_version': templateVersion,
    'mode': mode.wireName,
    'rect': rect.toJson(),
    'zoom': double.parse(zoom.toStringAsFixed(4)),
    'offset_x': double.parse(offsetX.toStringAsFixed(4)),
    'offset_y': double.parse(offsetY.toStringAsFixed(4)),
    'face_count': faceCount,
    'fallback_reason': fallbackReason,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory CropDecision.fromJson(Map<String, dynamic> json) {
    final updated =
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.now();
    final decision = CropDecision(
      imageId: json['image_id'] as String? ?? '',
      slotId: json['slot_id'] as String? ?? '',
      templateId: json['template_id'] as String? ?? '',
      templateVersion: (json['template_version'] as num?)?.toInt() ?? 0,
      mode: CropModeJson.fromWire(json['mode'] as String? ?? 'fit'),
      rect: NormalizedRect.fromJson(
        (json['rect'] as Map?)?.cast<String, dynamic>() ??
            const {'x': 0, 'y': 0, 'w': 1, 'h': 1},
      ),
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
      offsetX: (json['offset_x'] as num?)?.toDouble() ?? 0,
      offsetY: (json['offset_y'] as num?)?.toDouble() ?? 0,
      faceCount: (json['face_count'] as num?)?.toInt() ?? 0,
      fallbackReason: json['fallback_reason'] as String?,
      updatedAt: updated,
    );
    decision.validate();
    return decision;
  }

  CropDecision copyWith({
    CropMode? mode,
    NormalizedRect? rect,
    double? zoom,
    double? offsetX,
    double? offsetY,
    int? faceCount,
    String? fallbackReason,
  }) => CropDecision(
    imageId: imageId,
    slotId: slotId,
    templateId: templateId,
    templateVersion: templateVersion,
    mode: mode ?? this.mode,
    rect: rect ?? this.rect,
    zoom: zoom ?? this.zoom,
    offsetX: offsetX ?? this.offsetX,
    offsetY: offsetY ?? this.offsetY,
    faceCount: faceCount ?? this.faceCount,
    fallbackReason: fallbackReason ?? this.fallbackReason,
    updatedAt: DateTime.now(),
  );
}

abstract final class CropGeometry {
  /// Build a centered crop with the destination slot's pixel aspect ratio.
  /// Offsets are normalized -1..1 and zoom is 1..3.
  static NormalizedRect manual({
    required double imageAspect,
    required double slotAspect,
    required double zoom,
    required double offsetX,
    required double offsetY,
  }) {
    if (imageAspect <= 0 || slotAspect <= 0) {
      throw const CropValidationException('aspect ratios must be positive');
    }
    final z = zoom.clamp(1.0, 3.0);
    final targetRatio = slotAspect / imageAspect;
    final baseWidth = targetRatio >= 1 ? 1.0 : targetRatio;
    final baseHeight = targetRatio >= 1 ? 1 / targetRatio : 1.0;
    final width = (baseWidth / z).clamp(0.001, 1.0);
    final height = (baseHeight / z).clamp(0.001, 1.0);
    final cx = (0.5 + offsetX.clamp(-1.0, 1.0) * (1 - width) / 2).clamp(
      width / 2,
      1 - width / 2,
    );
    final cy = (0.5 + offsetY.clamp(-1.0, 1.0) * (1 - height) / 2).clamp(
      height / 2,
      1 - height / 2,
    );
    return NormalizedRect(
      x: cx - width / 2,
      y: cy - height / 2,
      width: width,
      height: height,
    );
  }

  static NormalizedRect union(FaceBox a, FaceBox b) {
    final left = math.min(a.box.x, b.box.x);
    final top = math.min(a.box.y, b.box.y);
    final right = math.max(a.box.x + a.box.width, b.box.x + b.box.width);
    final bottom = math.max(a.box.y + a.box.height, b.box.y + b.box.height);
    return NormalizedRect(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }
}
