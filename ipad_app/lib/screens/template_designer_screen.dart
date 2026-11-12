import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class TemplateDesignerScreen extends StatefulWidget {
  final BoothController controller;
  final EventProfile event;
  const TemplateDesignerScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  @override
  State<TemplateDesignerScreen> createState() => _TemplateDesignerScreenState();
}

class _TemplateDesignerScreenState extends State<TemplateDesignerScreen> {
  late EventCustomTemplate _design;
  int _selected = 0;
  bool _saving = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _design =
        widget.event.configuration.customTemplate ??
        const EventCustomTemplate(
          slots: [
            CustomPhotoSlot(
              id: 'slot_1',
              captureOrder: 0,
              x: .08,
              y: .08,
              width: .84,
              height: .24,
            ),
            CustomPhotoSlot(
              id: 'slot_2',
              captureOrder: 1,
              x: .08,
              y: .38,
              width: .84,
              height: .24,
            ),
            CustomPhotoSlot(
              id: 'slot_3',
              captureOrder: 2,
              x: .08,
              y: .68,
              width: .84,
              height: .24,
            ),
          ],
        );
  }

  CustomPhotoSlot get _slot => _design.slots[_selected];

  void _replace(CustomPhotoSlot value) {
    final next = [..._design.slots];
    next[_selected] = value;
    setState(() => _design = _design.copyWith(slots: next));
  }

  Future<void> _pickArtwork() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length < 8 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4E ||
          bytes[3] != 0x47) {
        throw const FormatException('Choose a PNG exported from Canva.');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      final path = await widget.controller.storage.saveBrandingLogo(
        widget.event.id,
        bytes,
        'png',
      );
      if (!mounted) return;
      setState(() {
        _design = _design.copyWith(
          artworkPath: path,
          artworkWidth: width,
          artworkHeight: height,
        );
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'PNG could not be imported: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _addSlot() {
    if (_design.slots.length >= 4) return;
    final order = _design.slots.length;
    final next = [
      ..._design.slots,
      CustomPhotoSlot(
        id: 'slot_${DateTime.now().millisecondsSinceEpoch}',
        captureOrder: order,
        x: .15,
        y: .15,
        width: .55,
        height: .25,
      ),
    ];
    setState(() {
      _design = _design.copyWith(slots: next);
      _selected = next.length - 1;
    });
  }

  void _removeSlot() {
    if (_design.slots.length <= 1) return;
    final next = [..._design.slots]..removeAt(_selected);
    setState(() {
      _design = _design.copyWith(slots: next);
      _selected = 0;
    });
  }

  Future<void> _save() async {
    if (_design.artworkPath == null) {
      setState(() => _error = 'Import a Canva PNG before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = widget.event.copyWith(
        configuration: widget.event.configuration.copyWith(
          customTemplate: _design,
          photoCount: _design.slots.length,
          templateId: 'custom_design',
          templateVersion: 1,
        ),
        updatedAt: DateTime.now().toUtc(),
      );
      await widget.controller.updateEvent(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) setState(() => _error = 'Layout could not be saved: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TbSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TbPageHeader(
                  showBack: true,
                  eyebrow: 'Canva template',
                  title: 'Photo layout',
                  subtitle:
                      'Import a PNG, place photo slots, then drag and resize them. Coordinates are stored in template space, not screen pixels.',
                ),
                const SizedBox(height: TbSpace.lg),
                TbCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const TbEyebrow('Canvas'),
                          const Spacer(),
                          SegmentedButton<TemplateLayerMode>(
                            segments: const [
                              ButtonSegment(
                                value: TemplateLayerMode.overlay,
                                label: Text('PNG overlay'),
                              ),
                              ButtonSegment(
                                value: TemplateLayerMode.background,
                                label: Text('Background'),
                              ),
                            ],
                            selected: {_design.layerMode},
                            onSelectionChanged: (v) => setState(
                              () => _design = _design.copyWith(
                                layerMode: v.first,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;
                            Widget slotBox(int index) {
                              final s = _design.slots[index];
                              final selected = index == _selected;
                              return Positioned(
                                left: s.x * w,
                                top: s.y * h,
                                width: s.width * w,
                                height: s.height * h,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selected = index),
                                  onPanUpdate: (d) {
                                    if (index != _selected) return;
                                    _replace(
                                      s.copyWith(
                                        x: (s.x + d.delta.dx / w).clamp(
                                          0.0,
                                          1 - s.width,
                                        ),
                                        y: (s.y + d.delta.dy / h).clamp(
                                          0.0,
                                          1 - s.height,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: TbColors.blue.withValues(
                                        alpha: .20,
                                      ),
                                      border: Border.all(
                                        color: selected
                                            ? TbColors.gold
                                            : TbColors.line,
                                        width: selected ? 3 : 1,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Center(
                                          child: Text(
                                            'PHOTO ${s.captureOrder + 1}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        if (selected)
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: GestureDetector(
                                              onPanUpdate: (d) => _replace(
                                                s.copyWith(
                                                  width:
                                                      (s.width + d.delta.dx / w)
                                                          .clamp(.08, 1 - s.x),
                                                  height:
                                                      (s.height +
                                                              d.delta.dy / h)
                                                          .clamp(.08, 1 - s.y),
                                                ),
                                              ),
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                color: TbColors.gold,
                                                child: const Icon(
                                                  Icons.open_in_full,
                                                  size: 18,
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }

                            return ClipRect(
                              child: Stack(
                                children: [
                                  Container(color: const Color(0xFF20242E)),
                                  if (_design.artworkPath != null &&
                                      File(_design.artworkPath!).existsSync())
                                    Positioned.fill(
                                      child: Opacity(
                                        opacity:
                                            _design.layerMode ==
                                                TemplateLayerMode.overlay
                                            ? .55
                                            : .8,
                                        child: Image.file(
                                          File(_design.artworkPath!),
                                          fit: BoxFit.fill,
                                        ),
                                      ),
                                    ),
                                  for (var i = 0; i < _design.slots.length; i++)
                                    slotBox(i),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          TbSecondaryButton(
                            label: _picking ? 'Importing…' : 'Import Canva PNG',
                            icon: Icons.upload_file,
                            onPressed: _picking ? null : _pickArtwork,
                          ),
                          TbSecondaryButton(
                            label: 'Add slot',
                            icon: Icons.add_box_outlined,
                            onPressed: _design.slots.length >= 4
                                ? null
                                : _addSlot,
                          ),
                          TbSecondaryButton(
                            label: 'Remove slot',
                            icon: Icons.delete_outline,
                            onPressed: _design.slots.length <= 1
                                ? null
                                : _removeSlot,
                          ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: TbColors.red),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: TbSpace.md),
                TbCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TbEyebrow('Selected slot · ${_selected + 1}'),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: _slot.captureOrder,
                        decoration: const InputDecoration(
                          labelText: 'Capture order',
                        ),
                        items: [
                          for (var i = 0; i < _design.slots.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text('Photo ${i + 1}'),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            _replace(_slot.copyWith(captureOrder: v));
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Cover')),
                          ButtonSegment(value: true, label: Text('Contain')),
                        ],
                        selected: {_slot.contain},
                        onSelectionChanged: (v) =>
                            _replace(_slot.copyWith(contain: v.first)),
                      ),
                      Text('Zoom ${_slot.zoom.toStringAsFixed(2)}×'),
                      Slider(
                        value: _slot.zoom,
                        min: 1,
                        max: 3,
                        onChanged: (v) => _replace(_slot.copyWith(zoom: v)),
                      ),
                      Text('Horizontal position'),
                      Slider(
                        value: _slot.offsetX,
                        min: -.5,
                        max: .5,
                        onChanged: (v) => _replace(_slot.copyWith(offsetX: v)),
                      ),
                      Text('Vertical position'),
                      Slider(
                        value: _slot.offsetY,
                        min: -.5,
                        max: .5,
                        onChanged: (v) => _replace(_slot.copyWith(offsetY: v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: TbSpace.lg),
                TbPrimaryButton(
                  label: _saving ? 'Saving…' : 'Save Canva layout',
                  icon: Icons.save_outlined,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
