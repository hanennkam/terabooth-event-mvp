import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../services/share_service.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import 'gif_preview_screen.dart';

class ResultScreen extends StatelessWidget {
  final BoothController controller;
  final ShareService shareService;
  const ResultScreen({
    super.key,
    required this.controller,
    this.shareService = const ShareService(),
  });

  Future<void> _shareStrip(BuildContext context) async {
    final bytes = controller.compositionBytes;
    if (bytes == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await shareService.shareBytes(
      bytes: bytes,
      filename: 'terabooth-strip-${controller.sessionId ?? 'guest'}.jpg',
      mimeType: 'image/jpeg',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  Future<void> _print(BuildContext context) async {
    if (controller.phase != BoothPhase.done) return;
    final copies = await showDialog<int>(
      context: context,
      builder: (context) => _CopiesDialog(),
    );
    if (copies == null || !context.mounted) return;
    await controller.reprint(copies: copies);
  }

  void _openGif(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GifPreviewScreen(
          controller: controller,
          shareService: shareService,
        ),
      ),
    );
  }

  String _statusLabel(BoothController c) {
    if (c.phase == BoothPhase.uploading) return 'Preparing your photo strip';
    if (c.phase == BoothPhase.printing) return 'Printing your photo strip';
    if (c.phase == BoothPhase.error) return 'Something needs attention';
    final state = c.job?.state;
    if (state == 'completed' && c.job?.completion == 'preview') {
      return 'Your photo strip is ready';
    }
    if (state == 'completed') {
      return c.job?.printerMode == 'mock'
          ? 'Mock print complete — no physical print'
          : 'Print sent';
    }
    if (state == 'failed' || state == 'unknown') {
      return 'Print status needs a check';
    }
    return 'Preparing your photo strip';
  }

  @override
  Widget build(BuildContext context) {
    return TbBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TbSpace.lg),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final c = controller;
              final busy =
                  c.phase == BoothPhase.uploading ||
                  c.phase == BoothPhase.printing;
              final hasStrip = c.compositionBytes != null;
              return Column(
                children: [
                  Row(
                    children: [
                      const TbWordmark(compact: true),
                      const SizedBox(width: TbSpace.md),
                      Container(width: 1, height: 20, color: TbColors.line),
                      const SizedBox(width: TbSpace.md),
                      Flexible(
                        child: Text(
                          c.eventTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Spacer(),
                      const TbPill(
                        label: 'YOUR PHOTO STRIP',
                        color: TbColors.gold,
                        icon: Icons.auto_awesome,
                        dense: true,
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: busy ? null : c.reset,
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: TbSpace.md),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 900;
                        final preview = _PreviewPanel(
                          controller: c,
                          status: _statusLabel(c),
                        );
                        final actions = _actions(
                          context,
                          c,
                          hasStrip: hasStrip,
                          busy: busy,
                        );
                        if (!wide) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                preview,
                                const SizedBox(height: TbSpace.md),
                                actions,
                              ],
                            ),
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 3, child: preview),
                            const SizedBox(width: TbSpace.lg),
                            SizedBox(
                              width: 360,
                              child: SingleChildScrollView(child: actions),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    BoothController c, {
    required bool hasStrip,
    required bool busy,
  }) {
    return TbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TbEyebrow('Take it with you'),
          const SizedBox(height: 8),
          Text(
            'Choose how to share or print your strip.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: TbSpace.lg),
          TbPrimaryButton(
            label: 'GIF',
            icon: Icons.gif_box_outlined,
            expanded: true,
            onPressed: busy ? null : () => _openGif(context),
          ),
          const SizedBox(height: 12),
          TbPrimaryButton(
            label: 'AirDrop',
            icon: Icons.ios_share_rounded,
            expanded: true,
            onPressed: busy || !hasStrip ? null : () => _shareStrip(context),
          ),
          const SizedBox(height: 12),
          TbPrimaryButton(
            label: busy ? 'Printing…' : 'Print',
            icon: Icons.print_outlined,
            expanded: true,
            onPressed: busy || !hasStrip || c.phase != BoothPhase.done
                ? null
                : () => _print(context),
          ),
          if (!hasStrip) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(child: Text('Your strip is being prepared.')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final BoothController controller;
  final String status;
  const _PreviewPanel({required this.controller, required this.status});

  @override
  Widget build(BuildContext context) {
    final bytes = controller.compositionBytes;
    return TbCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (controller.job?.printerMode == 'mock')
                const TbPill(
                  label: 'MOCK PRINTER',
                  color: TbColors.rose,
                  icon: Icons.science_outlined,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: TbSpace.md),
          Expanded(
            child: Center(
              child: bytes == null
                  ? (controller.phase == BoothPhase.error
                        ? TbEmptyState(
                            icon: Icons.error_outline,
                            title: 'Strip not available',
                            message:
                                controller.error ??
                                'The bridge did not return the composition.',
                          )
                        : const CircularProgressIndicator())
                  : Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(TbRadius.md),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 24),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(TbRadius.md),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
            ),
          ),
          if (bytes != null) ...[
            const SizedBox(height: 12),
            Text(
              '4 × 6 inch photo strip',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: TbColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CopiesDialog extends StatefulWidget {
  @override
  State<_CopiesDialog> createState() => _CopiesDialogState();
}

class _CopiesDialogState extends State<_CopiesDialog> {
  int _copies = 1;
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How many prints?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Choose the number of 4×6 photo strips.'),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 1,
                label: Text('1 copy'),
                icon: Icon(Icons.looks_one_outlined),
              ),
              ButtonSegment(
                value: 2,
                label: Text('2 copies'),
                icon: Icon(Icons.looks_two_outlined),
              ),
            ],
            selected: {_copies},
            onSelectionChanged: (v) => setState(() => _copies = v.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _copies),
          child: const Text('Print'),
        ),
      ],
    );
  }
}

/// Automatically advances a completed capture into the Result Screen. The
/// controller retains an explicit review transition internally for recovery,
/// but guests never see an approval step.
class AutoResultScreen extends StatefulWidget {
  final BoothController controller;
  final ShareService shareService;
  const AutoResultScreen({
    super.key,
    required this.controller,
    this.shareService = const ShareService(),
  });

  @override
  State<AutoResultScreen> createState() => _AutoResultScreenState();
}

class _AutoResultScreenState extends State<AutoResultScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.phase == BoothPhase.review) {
        widget.controller.approve();
      }
    });
  }

  @override
  Widget build(BuildContext context) => ResultScreen(
    controller: widget.controller,
    shareService: widget.shareService,
  );
}
