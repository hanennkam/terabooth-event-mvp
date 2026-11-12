import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import '../widgets/template_preview.dart';
import 'crop_editor_screen.dart';

class ReviewScreen extends StatelessWidget {
  final BoothController controller;
  const ReviewScreen({super.key, required this.controller});

  Future<void> _confirmRetakeAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retake the whole session?'),
        content: Text(
          'This will capture ${controller.expectedPhotoCount} new photos and replace the current review. Previous originals remain safely stored on this iPad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retake all photos'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.retakeAll();
    }
  }

  Future<void> _preview(BuildContext context) async {
    final c = controller;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 620,
          child: Padding(
            padding: const EdgeInsets.all(TbSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c.template.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close preview',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Template v${c.template.version} · ${c.template.outputWidth} × ${c.template.outputHeight} · ${c.template.dpi} dpi',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: TbSpace.md),
                TemplatePreview(
                  template: c.template,
                  photos: c.photos,
                  crops: c.crops,
                  eventTitle: c.eventTitle,
                  eventDate: c.eventDate,
                  branding: c.sessionBranding,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _adjustCrop(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CropEditorScreen(controller: controller, photoIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return TbBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TbSpace.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context, c),
                  const SizedBox(height: TbSpace.md),
                  if (c.retakeError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: TbColors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.retakeError!,
                              style: const TextStyle(color: TbColors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (wide)
                    Expanded(child: _photoRow(context, c))
                  else
                    SizedBox(height: 340, child: _photoRow(context, c)),
                  const SizedBox(height: TbSpace.md),
                  _actions(context, c),
                ],
              );
              if (wide) return content;
              return SingleChildScrollView(child: content);
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, BoothController c) {
    return Row(
      children: [
        const TbWordmark(compact: true),
        const SizedBox(width: TbSpace.md),
        Container(width: 1, height: 20, color: TbColors.line),
        const SizedBox(width: TbSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review session',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text(
                c.eventTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        TbPill(
          label: '${c.expectedPhotoCount} photos',
          color: TbColors.mint,
          icon: Icons.photo_library_outlined,
          dense: true,
        ),
        const SizedBox(width: 8),
        TbPill(
          label: c.template.name,
          color: TbColors.gold,
          icon: Icons.dashboard_customize_outlined,
          dense: true,
        ),
      ],
    );
  }

  Widget _photoRow(BuildContext context, BoothController c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < c.expectedPhotoCount; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == c.expectedPhotoCount - 1 ? 0 : 10,
              ),
              child: _photoCard(context, c, i),
            ),
          ),
      ],
    );
  }

  Widget _photoCard(BuildContext context, BoothController c, int index) {
    final hasPhoto = index < c.photos.length;
    return TbCard(
      padding: EdgeInsets.zero,
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(TbRadius.lg),
              ),
              child: hasPhoto
                  ? Image.memory(c.photos[index].bytes, fit: BoxFit.cover)
                  : Container(
                      color: TbColors.ink,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: TbColors.muted,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Photo ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Adjust crop ${index + 1}',
                  onPressed: hasPhoto
                      ? () => _adjustCrop(context, index)
                      : null,
                  icon: const Icon(Icons.crop_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                Icon(
                  hasPhoto ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: hasPhoto ? TbColors.mint : TbColors.muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, BoothController c) {
    final busy = c.retakingSlot != null;
    return Row(
      children: [
        TbSecondaryButton(
          label: 'Retake all',
          icon: Icons.refresh_rounded,
          onPressed: busy ? null : () => _confirmRetakeAll(context),
        ),
        const SizedBox(width: TbSpace.sm),
        TbSecondaryButton(
          label: 'Preview strip',
          icon: Icons.visibility_outlined,
          onPressed: busy ? null : () => _preview(context),
        ),
        const SizedBox(width: TbSpace.sm),
        Expanded(
          child: TbPrimaryButton(
            label: 'Approve & Print',
            icon: Icons.print_outlined,
            expanded: true,
            onPressed: busy ? null : c.approve,
          ),
        ),
      ],
    );
  }
}
