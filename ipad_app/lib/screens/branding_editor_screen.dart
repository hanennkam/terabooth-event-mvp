import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../templates/builtin_templates.dart';
import '../templates/template_models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import '../widgets/template_preview.dart';

class BrandingEditorScreen extends StatefulWidget {
  final BoothController controller;
  final EventProfile event;

  const BrandingEditorScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  @override
  State<BrandingEditorScreen> createState() => _BrandingEditorScreenState();
}

class _BrandingEditorScreenState extends State<BrandingEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _tagline;
  late final TextEditingController _color;
  late EventBranding _branding;
  late BrandingPlacement _placement;
  bool _enabled = false;
  bool _saving = false;
  bool _picking = false;
  String? _originalLogoPath;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _branding = widget.event.configuration.branding;
    _originalLogoPath = _branding.logoPath;
    _enabled = _branding.enabled;
    _placement = _branding.placement;
    _title = TextEditingController(text: _branding.title);
    _tagline = TextEditingController(text: _branding.tagline);
    _color = TextEditingController(text: _branding.colorHex);
  }

  @override
  void dispose() {
    if (!_saved &&
        _branding.logoPath != null &&
        _branding.logoPath != _originalLogoPath) {
      // A newly picked, unsaved logo must not become an orphaned event asset.
      unawaited(
        widget.controller.storage.deleteBrandingLogo(_branding.logoPath),
      );
    }
    _title.dispose();
    _tagline.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final extension = _extension(bytes);
      if (extension == null) {
        throw const FormatException('Choose a PNG or JPEG logo.');
      }
      if (bytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Logo must be smaller than 2 MB.');
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      final saved = await widget.controller.storage.saveBrandingLogo(
        widget.event.id,
        bytes,
        extension,
      );
      if (!mounted) return;
      setState(() {
        _branding = _branding.copyWith(logoPath: saved);
        _enabled = true;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Logo could not be used: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String? _extension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return null;
  }

  Future<void> _removeLogo() async {
    setState(() => _branding = _branding.copyWith(clearLogo: true));
  }

  Future<void> _save() async {
    if (_saving) return;
    final color = _color.text.trim().toUpperCase();
    final next = _branding.copyWith(
      enabled: _enabled,
      title: _title.text.trim(),
      tagline: _tagline.text.trim(),
      colorHex: color,
      placement: _placement,
    );
    try {
      next.validate();
      if (next.logoPath != null && !File(next.logoPath!).existsSync()) {
        throw const EventValidationException(
          'BRANDING_LOGO_MISSING',
          'The selected logo file is missing. Choose it again or remove it.',
        );
      }
    } on EventValidationException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = widget.event.copyWith(
        configuration: widget.event.configuration.copyWith(branding: next),
        updatedAt: DateTime.now().toUtc(),
      );
      await widget.controller.updateEvent(updated);
      _saved = true;
      if (_originalLogoPath != null && _originalLogoPath != next.logoPath) {
        await widget.controller.storage.deleteBrandingLogo(_originalLogoPath);
      }
      if (!mounted) return;
      Navigator.pop(context, updated);
    } on EventValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Branding could not be saved: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = BuiltinTemplates.forPhotoCount(
      widget.event.configuration.photoCount,
      preferred: BuiltinTemplates.byId(widget.event.configuration.templateId),
    );
    final preview = _branding.copyWith(
      enabled: _enabled,
      title: _title.text.trim(),
      tagline: _tagline.text.trim(),
      colorHex: _color.text.trim(),
      placement: _placement,
    );
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
                  eyebrow: 'Event output',
                  title: 'Branding',
                  subtitle:
                      'Branding is applied to the derived composition only. Camera originals remain unchanged.',
                ),
                const SizedBox(height: TbSpace.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final form = _form();
                    final previewCard = _preview(template, preview);
                    if (!wide) {
                      return Column(
                        children: [
                          previewCard,
                          const SizedBox(height: TbSpace.md),
                          form,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: form),
                        const SizedBox(width: TbSpace.md),
                        Expanded(flex: 2, child: previewCard),
                      ],
                    );
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: TbSpace.md),
                  Text(_error!, style: const TextStyle(color: TbColors.red)),
                ],
                const SizedBox(height: TbSpace.lg),
                Row(
                  children: [
                    TbPrimaryButton(
                      label: _saving ? 'Saving…' : 'Save branding',
                      icon: Icons.check_rounded,
                      onPressed: _saving ? null : _save,
                    ),
                    const SizedBox(width: 12),
                    TbSecondaryButton(
                      label: 'Reset to default',
                      icon: Icons.restart_alt_rounded,
                      onPressed: _saving || _picking
                          ? null
                          : () async {
                              if (!mounted) return;
                              setState(() {
                                _branding = const EventBranding();
                                _enabled = false;
                                _placement = BrandingPlacement.bottom;
                                _title.clear();
                                _tagline.clear();
                                _color.text = '#C8A464';
                              });
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return TbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TbEyebrow('Brand identity'),
          const SizedBox(height: TbSpace.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apply event branding'),
            subtitle: const Text(
              'Logo, title and tagline are drawn into the derived output.',
            ),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _branding.logoPath == null
                      ? 'No logo selected'
                      : 'Logo stored locally',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TbSecondaryButton(
                label: _picking ? 'Selecting…' : 'Choose logo',
                icon: Icons.image_outlined,
                onPressed: _picking ? null : _pickLogo,
              ),
              if (_branding.logoPath != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove logo',
                  onPressed: _removeLogo,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Brand title',
              hintText: 'Defaults to the event title',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagline,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Tagline',
              hintText: 'Optional short line',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _color,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Brand colour',
                    hintText: '#C8A464',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _previewColor(),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: TbColors.line),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BrandingPlacement>(
            initialValue: _placement,
            decoration: const InputDecoration(labelText: 'Brand placement'),
            items: const [
              DropdownMenuItem(
                value: BrandingPlacement.top,
                child: Text('Top'),
              ),
              DropdownMenuItem(
                value: BrandingPlacement.bottom,
                child: Text('Bottom'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _placement = value);
            },
          ),
        ],
      ),
    );
  }

  Color _previewColor() {
    try {
      return Color(EventBranding(colorHex: _color.text.trim()).colorValue);
    } catch (_) {
      return TbColors.gold;
    }
  }

  Widget _preview(PhotoTemplate template, EventBranding branding) {
    return TbCard(
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TbEyebrow('Composition preview'),
          const SizedBox(height: TbSpace.md),
          TemplatePreview(
            template: template,
            eventTitle: widget.event.title,
            eventDate: widget.event.date,
            branding: branding,
          ),
          const SizedBox(height: 10),
          Text(
            'Original photos are never modified. The preview uses the same branding fields sent to the output composer.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
