import '../models.dart';
import '../templates/template_models.dart';
import '../services/face_detection_service.dart';
import 'crop_models.dart';

class SmartCropPlanner {
  final FaceDetector faceDetector;
  const SmartCropPlanner({required this.faceDetector});

  Future<CropDecision> plan({
    required CapturedImage image,
    required PhotoTemplate template,
    required TemplateSlot slot,
    CropMode mode = CropMode.smart,
  }) async {
    if (mode == CropMode.fit) return fit(image, template, slot);
    if (mode == CropMode.manual) {
      final rect = CropGeometry.manual(
        imageAspect: image.width / image.height,
        slotAspect: slot.aspect,
        zoom: 1,
        offsetX: 0,
        offsetY: 0,
      );
      return CropDecision(
        imageId: image.id,
        slotId: slot.id,
        templateId: template.id,
        templateVersion: template.version,
        mode: CropMode.manual,
        rect: rect,
        updatedAt: DateTime.now(),
      )..validate();
    }

    FaceDetectionResult detection;
    try {
      detection = await faceDetector.detect(image.bytes);
    } catch (e) {
      return fit(
        image,
        template,
        slot,
        fallbackReason: 'Face detection failed: $e',
      );
    }
    final faces = detection.faces
        .where((face) => face.confidence >= 0.5)
        .toList();
    if (detection.unavailable ||
        faces.isEmpty ||
        faces.length != detection.faces.length) {
      return fit(
        image,
        template,
        slot,
        fallbackReason: detection.unavailable
            ? 'Face detection unavailable'
            : 'No confident faces detected',
      );
    }

    var union = faces.first.box;
    for (final face in faces.skip(1)) {
      union = CropGeometry.union(FaceBox(box: union, confidence: 0), face);
    }
    if (union.x <= 0.01 ||
        union.y <= 0.01 ||
        union.x + union.width >= 0.99 ||
        union.y + union.height >= 0.99) {
      return fit(
        image,
        template,
        slot,
        fallbackReason: 'Faces too close to the image boundary',
      );
    }

    const margin = 0.055;
    const headroom = 0.035;
    final targetRatio = slot.aspect / (image.width / image.height);
    final requiredW = union.width + margin * 2;
    final requiredH = union.height + margin * 2 + headroom;
    final width =
        (requiredW > requiredH * targetRatio
                ? requiredW
                : requiredH * targetRatio)
            .clamp(0.001, 1.0);
    final height = (width / targetRatio).clamp(0.001, 1.0);
    if (width >= 0.999 || height >= 0.999) {
      return fit(
        image,
        template,
        slot,
        fallbackReason: 'Faces cannot fit safely in this slot',
      );
    }
    final cx = (union.x + union.width / 2).clamp(width / 2, 1 - width / 2);
    final cy = ((union.y + union.height / 2) - headroom / 2).clamp(
      height / 2,
      1 - height / 2,
    );
    final rect = NormalizedRect(
      x: cx - width / 2,
      y: cy - height / 2,
      width: width,
      height: height,
    );
    rect.validate();
    if (!_contains(rect, union, margin)) {
      return fit(
        image,
        template,
        slot,
        fallbackReason: 'Detected faces do not fit safely',
      );
    }
    return CropDecision(
      imageId: image.id,
      slotId: slot.id,
      templateId: template.id,
      templateVersion: template.version,
      mode: CropMode.smart,
      rect: rect,
      faceCount: faces.length,
      updatedAt: DateTime.now(),
    )..validate();
  }

  CropDecision fit(
    CapturedImage image,
    PhotoTemplate template,
    TemplateSlot slot, {
    String? fallbackReason,
  }) {
    return CropDecision(
      imageId: image.id,
      slotId: slot.id,
      templateId: template.id,
      templateVersion: template.version,
      mode: CropMode.fit,
      rect: NormalizedRect.full,
      fallbackReason: fallbackReason,
      updatedAt: DateTime.now(),
    )..validate();
  }

  bool _contains(NormalizedRect crop, NormalizedRect face, double margin) {
    return face.x >= crop.x + margin - 0.0001 &&
        face.y >= crop.y + margin - 0.0001 &&
        face.x + face.width <= crop.x + crop.width - margin + 0.0001 &&
        face.y + face.height <= crop.y + crop.height - margin + 0.0001;
  }
}
