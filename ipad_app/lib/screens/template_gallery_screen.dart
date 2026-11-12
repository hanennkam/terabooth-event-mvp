import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../templates/builtin_templates.dart';
import '../templates/template_models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import '../widgets/template_preview.dart';

class TemplateGalleryScreen extends StatefulWidget {
  final BoothController controller;
  const TemplateGalleryScreen({super.key, required this.controller});

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  late PhotoTemplate _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.controller.template;
  }

  Future<void> _useTemplate() async {
    await widget.controller.selectTemplate(_selected);
    if (!mounted) return;
    Navigator.pop(context);
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
                  eyebrow: 'Session setup',
                  title: 'Choose a template',
                  subtitle:
                      'The selected template is locked to this session once capture begins.',
                  actions: [
                    TbPill(
                      label: _selected.name,
                      color: TbColors.gold,
                      icon: Icons.check_rounded,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: TbSpace.lg),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1000 ? 3 : 2;
                      return GridView.builder(
                        itemCount: BuiltinTemplates.all.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: TbSpace.md,
                          mainAxisSpacing: TbSpace.md,
                          childAspectRatio: columns == 3 ? 0.62 : 0.68,
                        ),
                        itemBuilder: (context, index) {
                          final template = BuiltinTemplates.all[index];
                          return _TemplateCard(
                            template: template,
                            selected: template.id == _selected.id,
                            onTap: () => setState(() => _selected = template),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: TbSpace.md),
                Row(
                  children: [
                    TbSecondaryButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    TbPrimaryButton(
                      label: 'Use this template',
                      icon: Icons.check_rounded,
                      onPressed: _useTemplate,
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
}

class _TemplateCard extends StatelessWidget {
  final PhotoTemplate template;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TbCard(
      padding: const EdgeInsets.all(14),
      borderColor: selected ? TbColors.gold : TbColors.line,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                TemplatePreview(template: template, showGuides: true),
                if (selected)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: TbPill(
                      label: 'Selected',
                      color: TbColors.gold,
                      icon: Icons.check_rounded,
                      dense: true,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TbPill(
                label: 'v${template.version}',
                color: TbColors.muted,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            template.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${template.outputWidth} × ${template.outputHeight} · ${template.dpi} dpi',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
