import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models.dart';
import '../templates/template_models.dart';

/// Composes a Canva-style layout entirely on the iPad. Captured originals are
/// never modified; the composed 1200x1800 asset is returned separately.
class CustomTemplateComposer {
  static const canvasWidth = 1200.0;
  static const canvasHeight = 1800.0;

  Future<Uint8List> compose({
    required EventCustomTemplate design,
    required Uint8List artworkBytes,
    required List<CapturedImage> photos,
  }) async {
    if (design.slots.isEmpty) {
      throw StateError('Custom template has no photo slots.');
    }
    final artwork = await _decode(artworkBytes);
    final images = <ui.Image>[];
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    try {
      for (final photo in photos) {
        images.add(await _decode(photo.bytes));
      }
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      if (design.layerMode == TemplateLayerMode.background) {
        _drawArtwork(canvas, artwork);
      }
      for (var i = 0; i < design.slots.length; i++) {
        final slot = design.slots[i];
        if (slot.captureOrder < 0 || slot.captureOrder >= images.length) {
          throw StateError('Photo slot ${slot.id} has no captured photo.');
        }
        _drawPhoto(canvas, images[slot.captureOrder], slot);
      }
      if (design.layerMode == TemplateLayerMode.overlay) {
        _drawArtwork(canvas, artwork);
      }
      final picture = recorder.endRecording();
      final output = await picture.toImage(
        canvasWidth.toInt(),
        canvasHeight.toInt(),
      );
      picture.dispose();
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      if (data == null) throw StateError('Could not encode composed template.');
      return data.buffer.asUint8List();
    } finally {
      artwork.dispose();
      for (final image in images) {
        image.dispose();
      }
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  void _drawArtwork(ui.Canvas canvas, ui.Image artwork) {
    final aw = artwork.width.toDouble();
    final ah = artwork.height.toDouble();
    final scale = (canvasWidth / aw) < (canvasHeight / ah)
        ? canvasWidth / aw
        : canvasHeight / ah;
    final dw = aw * scale;
    final dh = ah * scale;
    canvas.drawImageRect(
      artwork,
      ui.Rect.fromLTWH(0, 0, aw, ah),
      ui.Rect.fromLTWH((canvasWidth - dw) / 2, (canvasHeight - dh) / 2, dw, dh),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
  }

  void _drawPhoto(ui.Canvas canvas, ui.Image image, CustomPhotoSlot slot) {
    final rect = ui.Rect.fromLTWH(
      slot.x * canvasWidth,
      slot.y * canvasHeight,
      slot.width * canvasWidth,
      slot.height * canvasHeight,
    );
    canvas.save();
    canvas.clipRect(rect);
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final baseScale = slot.contain
        ? (rect.width / iw < rect.height / ih
              ? rect.width / iw
              : rect.height / ih)
        : (rect.width / iw > rect.height / ih
              ? rect.width / iw
              : rect.height / ih);
    final scale = baseScale * slot.zoom.clamp(1.0, 3.0);
    final dw = iw * scale;
    final dh = ih * scale;
    final dx = rect.left + (rect.width - dw) / 2 + slot.offsetX * rect.width;
    final dy = rect.top + (rect.height - dh) / 2 + slot.offsetY * rect.height;
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, iw, ih),
      ui.Rect.fromLTWH(dx, dy, dw, dh),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    canvas.restore();
  }
}

extension EventCustomTemplatePreview on EventCustomTemplate {
  PhotoTemplate toPhotoTemplate({String id = 'custom_design'}) => PhotoTemplate(
    id: id,
    name: 'Custom Canva Layout',
    description: 'Event-specific Canva layout',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    slots: [
      for (var i = 0; i < slots.length; i++)
        TemplateSlot(
          id: slots[i].id,
          imageIndex: slots[i].captureOrder,
          x: slots[i].x * 1200,
          y: slots[i].y * 1800,
          width: slots[i].width * 1200,
          height: slots[i].height * 1800,
        ),
    ],
  );
}
