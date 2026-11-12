import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../crop/crop_models.dart';
import '../models.dart';
import '../templates/template_models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class CropEditorScreen extends StatefulWidget {
  final BoothController controller;
  final int photoIndex;

  const CropEditorScreen({
    super.key,
    required this.controller,
    required this.photoIndex,
  });

  @override
  State<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends State<CropEditorScreen> {
  late CapturedImage _image;
  late TemplateSlot _slot;
  late CropMode _mode;
  late NormalizedRect _rect;
  double _zoom = 1;
  double _offsetX = 0;
  double _offsetY = 0;
  int _faceCount = 0;
  String? _fallbackReason;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _image = widget.controller.photos[widget.photoIndex];
    _slot = widget.controller.template.slotsForImage(widget.photoIndex).first;
    final current = widget.controller.cropForSlot(_slot.id);
    _mode = current?.mode ?? CropMode.smart;
    _rect = current?.rect ?? NormalizedRect.full;
    _zoom = current?.zoom ?? 1;
    _offsetX = current?.offsetX ?? 0;
    _offsetY = current?.offsetY ?? 0;
    _faceCount = current?.faceCount ?? 0;
    _fallbackReason = current?.fallbackReason;
  }

  void _setManualRect() {
    _rect = CropGeometry.manual(
      imageAspect: _image.width / _image.height,
      slotAspect: _slot.aspect,
      zoom: _zoom,
      offsetX: _offsetX,
      offsetY: _offsetY,
    );
  }

  Future<void> _resetTo(CropMode mode) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final decision = await widget.controller.planCropForImage(
        widget.photoIndex,
        mode: mode,
      );
      if (!mounted) return;
      setState(() {
        _mode = decision.mode;
        _rect = decision.rect;
        _faceCount = decision.faceCount;
        _fallbackReason = decision.fallbackReason;
        _zoom = decision.zoom;
        _offsetX = decision.offsetX;
        _offsetY = decision.offsetY;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      CropDecision decision;
      if (_mode == CropMode.smart || _mode == CropMode.fit) {
        decision = await widget.controller.planCropForImage(
          widget.photoIndex,
          mode: _mode,
        );
      } else {
        _setManualRect();
        decision = CropDecision(
          imageId: _image.id,
          slotId: _slot.id,
          templateId: widget.controller.template.id,
          templateVersion: widget.controller.template.version,
          mode: CropMode.manual,
          rect: _rect,
          zoom: _zoom,
          offsetX: _offsetX,
          offsetY: _offsetY,
          updatedAt: DateTime.now(),
        )..validate();
      }
      await widget.controller.updateCrop(decision);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not apply crop: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(TbSpace.lg),
            child: Column(
              children: [
                TbPageHeader(
                  showBack: true,
                  eyebrow: 'Photo ${widget.photoIndex + 1}',
                  title: 'Adjust crop',
                  subtitle: widget.controller.template.name,
                  actions: [
                    TbPill(
                      label: switch (_mode) {
                        CropMode.smart => 'Smart crop',
                        CropMode.fit => 'Fit / contain',
                        CropMode.manual => 'Manual crop',
                      },
                      color: _mode == CropMode.fit
                          ? TbColors.mint
                          : _mode == CropMode.manual
                          ? TbColors.blue
                          : TbColors.gold,
                      icon: _mode == CropMode.fit
                          ? Icons.fit_screen_outlined
                          : _mode == CropMode.manual
                          ? Icons.open_with_rounded
                          : Icons.auto_awesome_outlined,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: TbSpace.lg),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final image = _sourceWithBoundary(context);
                      final controls = _controls(context);
                      if (!wide) {
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(height: 420, child: image),
                              const SizedBox(height: TbSpace.md),
                              controls,
                            ],
                          ),
                        );
                      }
                      return Row(
                        children: [
                          Expanded(flex: 3, child: image),
                          const SizedBox(width: TbSpace.md),
                          SizedBox(
                            width: 380,
                            child: SingleChildScrollView(child: controls),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceWithBoundary(BuildContext context) {
    return TbCard(
      padding: const EdgeInsets.all(14),
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TbEyebrow('Source frame'),
              const Spacer(),
              Text(
                '${_image.width} × ${_image.height}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _image.width / _image.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(TbRadius.sm),
                      child: Image.memory(_image.bytes, fit: BoxFit.cover),
                    ),
                    CustomPaint(
                      painter: _CropBoundaryPainter(
                        rect: _mode == CropMode.fit
                            ? NormalizedRect.full
                            : _rect,
                        mode: _mode,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _mode == CropMode.fit
                ? 'Full image is preserved. Background fill may appear in the slot.'
                : 'The bright frame is the area sent to the bridge.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _controls(BuildContext context) {
    return TbCard(
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TbEyebrow('Crop mode'),
          const SizedBox(height: 12),
          SegmentedButton<CropMode>(
            segments: const [
              ButtonSegment(
                value: CropMode.smart,
                icon: Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text('Smart'),
              ),
              ButtonSegment(
                value: CropMode.fit,
                icon: Icon(Icons.fit_screen_outlined, size: 18),
                label: Text('Fit'),
              ),
              ButtonSegment(
                value: CropMode.manual,
                icon: Icon(Icons.open_with_rounded, size: 18),
                label: Text('Manual'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _busy
                ? null
                : (values) {
                    setState(() {
                      _mode = values.first;
                      if (_mode == CropMode.manual) _setManualRect();
                    });
                  },
          ),
          const SizedBox(height: 12),
          if (_mode == CropMode.smart)
            Text(
              _faceCount > 0
                  ? '$_faceCount face${_faceCount == 1 ? '' : 's'} detected. Smart crop keeps them in frame.'
                  : 'No confident face detected. Safe fallback is Fit / contain.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else if (_mode == CropMode.fit)
            Text(
              'The complete original is preserved. No pixels are cropped.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Text(
              'Manual crop. Position and zoom are sent as normalized metadata.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (_fallbackReason != null) ...[
            const SizedBox(height: 8),
            Text(
              _fallbackReason!,
              style: const TextStyle(color: TbColors.rose, fontSize: 12),
            ),
          ],
          if (_mode == CropMode.manual) ...[
            const SizedBox(height: 16),
            _slider('Zoom', _zoom, 1, 3, (v) {
              setState(() {
                _zoom = v;
                _setManualRect();
              });
            }),
            _slider('Horizontal', _offsetX, -1, 1, (v) {
              setState(() {
                _offsetX = v;
                _setManualRect();
              });
            }),
            _slider('Vertical', _offsetY, -1, 1, (v) {
              setState(() {
                _offsetY = v;
                _setManualRect();
              });
            }),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TbSecondaryButton(
                  label: 'Reset to Smart',
                  onPressed: _busy ? null : () => _resetTo(CropMode.smart),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TbSecondaryButton(
                  label: 'Reset to Fit',
                  onPressed: _busy ? null : () => _resetTo(CropMode.fit),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TbPrimaryButton(
            label: _busy ? 'Applying…' : 'Apply crop',
            icon: Icons.check_rounded,
            expanded: true,
            onPressed: _busy ? null : _apply,
          ),
          const SizedBox(height: 12),
          Text(
            'Originals never change. Crop metadata is stored separately and sent with the template.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              value.toStringAsFixed(2),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: _busy ? null : onChanged,
        ),
      ],
    );
  }
}

class _CropBoundaryPainter extends CustomPainter {
  final NormalizedRect rect;
  final CropMode mode;

  _CropBoundaryPainter({required this.rect, required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == CropMode.fit) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = TbColors.mint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    final crop = Rect.fromLTWH(
      rect.x * size.width,
      rect.y * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.48);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, crop.top), shade);
    canvas.drawRect(
      Rect.fromLTWH(0, crop.bottom, size.width, size.height - crop.bottom),
      shade,
    );
    canvas.drawRect(Rect.fromLTWH(0, crop.top, crop.left, crop.height), shade);
    canvas.drawRect(
      Rect.fromLTWH(crop.right, crop.top, size.width - crop.right, crop.height),
      shade,
    );
    canvas.drawRect(
      crop,
      Paint()
        ..color = TbColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropBoundaryPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.mode != mode;
}
