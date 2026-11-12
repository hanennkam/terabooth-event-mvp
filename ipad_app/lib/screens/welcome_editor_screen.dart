import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class WelcomeEditorScreen extends StatefulWidget {
  final BoothController controller;
  final EventProfile event;
  const WelcomeEditorScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  @override
  State<WelcomeEditorScreen> createState() => _WelcomeEditorScreenState();
}

class _WelcomeEditorScreenState extends State<WelcomeEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _button;
  late final TextEditingController _color;
  late EventWelcomeConfig _welcome;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _welcome = widget.event.configuration.welcome;
    _title = TextEditingController(
      text: _welcome.title.isEmpty ? widget.event.title : _welcome.title,
    );
    _subtitle = TextEditingController(text: _welcome.subtitle);
    _button = TextEditingController(text: _welcome.buttonLabel);
    _color = TextEditingController(text: _welcome.backgroundHex);
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _button.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool background}) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50
          ? 'png'
          : 'jpg';
      if (bytes.length > 8 * 1024 * 1024) {
        throw const FormatException('Image must be under 8 MB.');
      }
      final path = await widget.controller.storage.saveBrandingLogo(
        widget.event.id,
        bytes,
        ext,
      );
      if (!mounted) return;
      setState(() {
        _welcome = background
            ? _welcome.copyWith(
                backgroundImagePath: path,
                backgroundMode: WelcomeBackgroundMode.image,
              )
            : _welcome.copyWith(logoPath: path);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Image could not be used: $e');
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final color = _color.text.trim();
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      setState(() {
        _saving = false;
        _error = 'Use a six-digit hex colour.';
      });
      return;
    }
    final next = _welcome.copyWith(
      title: _title.text.trim(),
      subtitle: _subtitle.text.trim(),
      buttonLabel: _button.text.trim().isEmpty
          ? 'Start Session'
          : _button.text.trim(),
      backgroundHex: color,
    );
    try {
      final updated = widget.event.copyWith(
        configuration: widget.event.configuration.copyWith(welcome: next),
        updatedAt: DateTime.now().toUtc(),
      );
      await widget.controller.updateEvent(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Welcome screen could not be saved: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _welcome.copyWith(
      title: _title.text.trim(),
      subtitle: _subtitle.text.trim(),
      buttonLabel: _button.text.trim(),
      backgroundHex: _color.text.trim(),
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
                  eyebrow: 'Guest experience',
                  title: 'Welcome screen',
                  subtitle:
                      'This is what guests see before their session. Each event keeps its own welcome.',
                ),
                const SizedBox(height: TbSpace.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final form = TbCard(
                      child: Column(
                        children: [
                          TextField(
                            controller: _title,
                            decoration: const InputDecoration(
                              labelText: 'Event title',
                              prefixIcon: Icon(Icons.title),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _subtitle,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Welcome message',
                              prefixIcon: Icon(Icons.notes),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _button,
                            decoration: const InputDecoration(
                              labelText: 'Start button label',
                              prefixIcon: Icon(Icons.touch_app),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _color,
                            decoration: const InputDecoration(
                              labelText: 'Background colour',
                              hintText: '#111318',
                              prefixIcon: Icon(Icons.palette_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TbSecondaryButton(
                                  label: 'Logo',
                                  icon: Icons.image_outlined,
                                  onPressed: () =>
                                      _pickImage(background: false),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TbSecondaryButton(
                                  label: 'Background photo',
                                  icon: Icons.photo_outlined,
                                  onPressed: () => _pickImage(background: true),
                                ),
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
                    );
                    final previewCard = _WelcomePreview(
                      welcome: preview,
                      fallbackTitle: widget.event.title,
                    );
                    if (constraints.maxWidth < 900) {
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
                const SizedBox(height: TbSpace.lg),
                TbPrimaryButton(
                  label: _saving ? 'Saving…' : 'Save welcome screen',
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

class _WelcomePreview extends StatelessWidget {
  final EventWelcomeConfig welcome;
  final String fallbackTitle;
  const _WelcomePreview({required this.welcome, required this.fallbackTitle});

  @override
  Widget build(BuildContext context) {
    final title = welcome.title.isEmpty ? fallbackTitle : welcome.title;
    return ClipRRect(
      borderRadius: BorderRadius.circular(TbRadius.lg),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (welcome.backgroundMode == WelcomeBackgroundMode.image &&
                welcome.backgroundImagePath != null &&
                File(welcome.backgroundImagePath!).existsSync())
              Image.file(File(welcome.backgroundImagePath!), fit: BoxFit.cover)
            else
              ColoredBox(color: Color(welcome.backgroundValue)),
            Container(color: Colors.black.withValues(alpha: 0.35)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (welcome.logoPath != null &&
                      File(welcome.logoPath!).existsSync())
                    Image.file(
                      File(welcome.logoPath!),
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.displaySmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    welcome.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () {},
                    child: Text(welcome.buttonLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
