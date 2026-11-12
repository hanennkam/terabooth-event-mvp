import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../crop/crop_models.dart';
import '../models.dart';
import '../templates/template_models.dart';
import '../theme/tb_theme.dart';

/// A faithful schematic/real-data preview of a template. Captured images are
/// drawn with the same normalized crop rectangle sent to the bridge.
class TemplatePreview extends StatefulWidget {
  final PhotoTemplate template;
  final List<CapturedImage> photos;
  final Map<String, CropDecision> crops;
  final bool showGuides;
  final String eventTitle;
  final String eventDate;
  final EventBranding? branding;

  const TemplatePreview({
    super.key,
    required this.template,
    this.photos = const [],
    this.crops = const {},
    this.showGuides = false,
    this.eventTitle = '',
    this.eventDate = '',
    this.branding,
  });

  @override
  State<TemplatePreview> createState() => _TemplatePreviewState();
}

class _TemplatePreviewState extends State<TemplatePreview> {
  final Map<String, ui.Image> _images = {};
  ui.Image? _logo;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    final path = widget.branding?.enabled == true
        ? widget.branding?.logoPath
        : null;
    if (path == null || path.isEmpty) return;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _logo?.dispose();
      setState(() => _logo = frame.image);
    } catch (_) {
      // Missing/invalid logos must not break review.
    }
  }

  @override
  void didUpdateWidget(covariant TemplatePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePhotos(oldWidget.photos, widget.photos)) {
      _disposeImages();
      _loadImages();
    }
    if (oldWidget.branding?.logoPath != widget.branding?.logoPath ||
        oldWidget.branding?.enabled != widget.branding?.enabled) {
      _logo?.dispose();
      _logo = null;
      _loadLogo();
    }
  }

  bool _samePhotos(List<CapturedImage> a, List<CapturedImage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Future<void> _loadImages() async {
    if (widget.photos.isEmpty || _loading) return;
    _loading = true;
    final loaded = <String, ui.Image>{};
    try {
      for (final photo in widget.photos) {
        final codec = await ui.instantiateImageCodec(photo.bytes);
        final frame = await codec.getNextFrame();
        loaded[photo.id] = frame.image;
      }
      if (!mounted) {
        for (final image in loaded.values) {
          image.dispose();
        }
        return;
      }
      _images.addAll(loaded);
      setState(() {});
    } catch (_) {
      // A preview failure must not break review or submission.
    } finally {
      _loading = false;
    }
  }

  void _disposeImages() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  @override
  void dispose() {
    _disposeImages();
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.template.aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TbRadius.sm),
        child: CustomPaint(
          painter: _TemplatePainter(
            template: widget.template,
            images: Map.of(_images),
            crops: widget.crops,
            showGuides: widget.showGuides,
            eventTitle: widget.eventTitle,
            eventDate: widget.eventDate,
            branding: widget.branding,
            logo: _logo,
            imageIds: [for (final photo in widget.photos) photo.id],
          ),
        ),
      ),
    );
  }
}

class _TemplatePainter extends CustomPainter {
  final PhotoTemplate template;
  final Map<String, ui.Image> images;
  final Map<String, CropDecision> crops;
  final bool showGuides;
  final String eventTitle;
  final String eventDate;
  final EventBranding? branding;
  final ui.Image? logo;
  final List<String> imageIds;

  _TemplatePainter({
    required this.template,
    required this.images,
    required this.crops,
    required this.showGuides,
    required this.eventTitle,
    required this.eventDate,
    required this.branding,
    required this.logo,
    required this.imageIds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / template.canvasWidth;
    final canvasH = template.canvasHeight * scale;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, canvasH),
      Paint()..color = template.background,
    );

    if (template.dividerY > 0) {
      final line = Paint()
        ..color = Color(template.dividerColor)
        ..strokeWidth = 2 * scale;
      for (var repeat = 0; repeat < template.repeatX; repeat++) {
        final offsetX = repeat * template.panelWidth;
        canvas.drawLine(
          Offset((offsetX + 24) * scale, template.dividerY * scale),
          Offset(
            (offsetX + template.panelWidth - 24) * scale,
            template.dividerY * scale,
          ),
          line,
        );
      }
    }

    for (var repeat = 0; repeat < template.repeatX; repeat++) {
      final offsetX = repeat * template.panelWidth;
      for (final slot in template.slots) {
        final dest = Rect.fromLTWH(
          (offsetX + slot.x) * scale,
          slot.y * scale,
          slot.width * scale,
          slot.height * scale,
        );
        _paintSlot(canvas, dest, slot);
      }
    }

    for (final text in template.texts) {
      for (var repeat = 0; repeat < template.repeatX; repeat++) {
        final offsetX = repeat * template.panelWidth;
        _paintText(canvas, scale, text, offsetX);
      }
    }

    _paintBranding(canvas, scale);

    if (showGuides) {
      final guide = Paint()
        ..color = TbColors.rose.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var repeat = 0; repeat < template.repeatX; repeat++) {
        final offsetX = repeat * template.panelWidth;
        for (final slot in template.slots) {
          canvas.drawRect(
            Rect.fromLTWH(
              (offsetX + slot.x) * scale,
              slot.y * scale,
              slot.width * scale,
              slot.height * scale,
            ),
            guide,
          );
        }
      }
    }
  }

  void _paintBranding(Canvas canvas, double scale) {
    final branding = this.branding;
    if (branding == null || !branding.enabled) return;
    final color = Color(branding.colorValue);
    final top = branding.placement == BrandingPlacement.top;
    final titleY = top ? 132.0 : 1680.0;
    final taglineY = titleY + 34;
    final logoImage = logo;
    if (logoImage != null) {
      final maxW = 130.0;
      final maxH = 72.0;
      final ratio = (maxW / logoImage.width) < (maxH / logoImage.height)
          ? maxW / logoImage.width
          : maxH / logoImage.height;
      final w = logoImage.width * ratio;
      final h = logoImage.height * ratio;
      final dest = Rect.fromLTWH(
        54 * scale,
        (top ? 52.0 : 1640.0) * scale,
        w * scale,
        h * scale,
      );
      canvas.drawImageRect(
        logoImage,
        Rect.fromLTWH(
          0,
          0,
          logoImage.width.toDouble(),
          logoImage.height.toDouble(),
        ),
        dest,
        Paint(),
      );
    }
    final title = branding.title.trim().isEmpty
        ? eventTitle
        : branding.title.trim();
    if (title.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            color: color,
            fontSize: 27 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 900 * scale);
      painter.paint(
        canvas,
        Offset(
          (template.canvasWidth * scale - painter.width) / 2,
          titleY * scale,
        ),
      );
    }
    if (branding.tagline.trim().isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: branding.tagline.trim(),
          style: TextStyle(
            color: const Color(0xFF4A4640),
            fontSize: 17 * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 900 * scale);
      painter.paint(
        canvas,
        Offset(
          (template.canvasWidth * scale - painter.width) / 2,
          taglineY * scale,
        ),
      );
    }
  }

  void _paintSlot(Canvas canvas, Rect dest, TemplateSlot slot) {
    final image = slot.imageIndex >= 0 && slot.imageIndex < imageIds.length
        ? images[imageIds[slot.imageIndex]]
        : null;
    if (image == null) {
      canvas.drawRect(dest, Paint()..color = const Color(0xFFE5E0D6));
      final label = TextPainter(
        text: TextSpan(
          text: 'PHOTO ${slot.imageIndex + 1}',
          style: const TextStyle(
            color: Color(0xFF8B8478),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        dest.center - Offset(label.width / 2, label.height / 2),
      );
    } else {
      final crop = crops[slot.id];
      if (crop == null || crop.mode == CropMode.fit) {
        _drawContain(canvas, image, dest);
      } else {
        _drawCrop(canvas, image, dest, crop.rect);
      }
    }
    if (slot.borderWidth > 0) {
      canvas.drawRect(
        dest,
        Paint()
          ..color = Color(slot.borderColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = slot.borderWidth * (dest.width / slot.width),
      );
    }
  }

  void _drawContain(Canvas canvas, ui.Image image, Rect dest) {
    final scale = (dest.width / image.width) < (dest.height / image.height)
        ? dest.width / image.width
        : dest.height / image.height;
    final w = image.width * scale;
    final h = image.height * scale;
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(
      dest.left + (dest.width - w) / 2,
      dest.top + (dest.height - h) / 2,
      w,
      h,
    );
    canvas.drawImageRect(image, src, dst, Paint());
  }

  void _drawCrop(
    Canvas canvas,
    ui.Image image,
    Rect dest,
    NormalizedRect crop,
  ) {
    final src = Rect.fromLTWH(
      crop.x * image.width,
      crop.y * image.height,
      crop.width * image.width,
      crop.height * image.height,
    );
    canvas.drawImageRect(image, src, dest, Paint());
  }

  void _paintText(
    Canvas canvas,
    double scale,
    TemplateText text,
    double offsetX,
  ) {
    final value = switch (text.kind) {
      TemplateTextKind.literal => text.text,
      TemplateTextKind.eventTitle => _title,
      TemplateTextKind.eventDate => _date,
    };
    if (value.isEmpty) return;
    final painter =
        TextPainter(
          text: TextSpan(
            text: text.uppercase ? value.toUpperCase() : value,
            style: TextStyle(
              color: Color(text.color),
              fontSize: text.fontSize * scale,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: switch (text.align) {
            'left' => TextAlign.left,
            'right' => TextAlign.right,
            _ => TextAlign.center,
          },
        )..layout(
          maxWidth:
              (template.repeatX > 1
                  ? template.panelWidth
                  : template.canvasWidth) *
              scale,
        );
    final centerX = (offsetX + text.x) * scale;
    painter.paint(
      canvas,
      Offset(centerX - painter.width / 2, text.y * scale - painter.height / 2),
    );
  }

  String get _title => eventTitle;
  String get _date => eventDate;

  @override
  bool shouldRepaint(covariant _TemplatePainter oldDelegate) =>
      oldDelegate.template != template ||
      oldDelegate.branding != branding ||
      oldDelegate.logo != logo ||
      oldDelegate.images != images ||
      oldDelegate.crops != crops ||
      oldDelegate.showGuides != showGuides ||
      oldDelegate.imageIds != imageIds ||
      oldDelegate.eventTitle != eventTitle ||
      oldDelegate.eventDate != eventDate;
}
