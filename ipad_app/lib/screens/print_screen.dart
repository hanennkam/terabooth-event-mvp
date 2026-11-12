import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../booth_controller.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class PrintScreen extends StatelessWidget {
  final BoothController controller;
  const PrintScreen({super.key, required this.controller});

  Future<void> _copyUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Delivery link copied')));
  }

  void _showComposition(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(36),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _showGif(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: TbColors.surface,
        insetPadding: const EdgeInsets.all(36),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(TbRadius.sm),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const TbPill(
                    label: 'Animated GIF',
                    color: TbColors.gold,
                    icon: Icons.gif_box_outlined,
                    dense: true,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close animated GIF',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmReprint(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a new print job?'),
        content: const Text(
          'Check the printer output first. This creates a new job and may produce another physical print. Unknown jobs are never resubmitted automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create reprint'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.reprint();
  }

  String _headerLabel(BoothController c) {
    if (c.phase == BoothPhase.error) return 'Needs attention';
    if (c.phase == BoothPhase.uploading || c.phase == BoothPhase.printing) {
      return 'In progress';
    }
    final state = c.job?.state;
    if (state == 'failed' || state == 'unknown') return 'Needs attention';
    if (state == 'completed') {
      return c.job?.printerMode == 'mock' ? 'Mock complete' : 'Completed';
    }
    return 'In progress';
  }

  _PrintStatus _status(BoothController c) {
    if (c.phase == BoothPhase.uploading) {
      return const _PrintStatus(
        title: 'Sending to print bridge…',
        body: 'The approved session is being uploaded. Keep the app open.',
        color: TbColors.gold,
        icon: Icons.cloud_upload_outlined,
      );
    }
    if (c.phase == BoothPhase.error) {
      return _PrintStatus(
        title: 'Print setup failed',
        body: c.error ?? 'The bridge did not accept the session.',
        color: TbColors.red,
        icon: Icons.error_outline,
      );
    }
    final job = c.job;
    if (job == null) {
      return const _PrintStatus(
        title: 'Waiting for the bridge…',
        body: 'The session is approved. Waiting for a print job response.',
        color: TbColors.gold,
        icon: Icons.hourglass_top_rounded,
      );
    }
    return switch (job.state) {
      'received' ||
      'validated' ||
      'composing' ||
      'queued' => const _PrintStatus(
        title: 'Preparing your photostrip…',
        body:
            'The bridge accepted the job. The composition has not been confirmed as printed yet.',
        color: TbColors.gold,
        icon: Icons.auto_awesome_outlined,
      ),
      'printing' => const _PrintStatus(
        title: 'Printing…',
        body:
            'The job has been submitted to the printer. Physical completion is not yet confirmed.',
        color: TbColors.gold,
        icon: Icons.print_outlined,
      ),
      'completed' =>
        job.printerMode == 'mock'
            ? const _PrintStatus(
                title: 'Mock print complete — no physical print',
                body:
                    'The mock printer completed the job. Nothing was sent to a DNP printer; do not hand this to a guest as a physical print.',
                color: TbColors.rose,
                icon: Icons.science_outlined,
              )
            : job.completion == 'confirmed'
            ? const _PrintStatus(
                title: 'Printed — take your strip',
                body:
                    'The bridge reports confirmed completion. Hand the guest both 2×6 strips.',
                color: TbColors.mint,
                icon: Icons.check_circle_outline,
              )
            : const _PrintStatus(
                title: 'Sent to printer — check the booth',
                body:
                    'The job was accepted, but physical completion is not confirmed. Inspect the printer before handing over a strip.',
                color: TbColors.gold,
                icon: Icons.print_outlined,
              ),
      'failed' => const _PrintStatus(
        title: 'Print failed',
        body:
            'No confirmed print. Check printer power, media and error lights. A new job is required after recovery.',
        color: TbColors.red,
        icon: Icons.error_outline,
      ),
      'unknown' => const _PrintStatus(
        title: 'Print status unknown',
        body:
            'Do not resubmit automatically. Inspect the printer and output first; only create a reprint after confirming no usable strip exists.',
        color: TbColors.rose,
        icon: Icons.help_outline,
      ),
      _ => _PrintStatus(
        title: job.state,
        body: 'The bridge returned an unrecognised job state.',
        color: TbColors.gold,
        icon: Icons.sync_problem_outlined,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final status = _status(c);
    return TbBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TbSpace.lg),
          child: Column(
            children: [
              _header(context, c, status),
              const SizedBox(height: TbSpace.lg),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (!wide) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            _statusPanel(context, c, status),
                            const SizedBox(height: TbSpace.md),
                            _compositionCard(context, c),
                            const SizedBox(height: TbSpace.md),
                            _gifCard(context, c),
                            const SizedBox(height: TbSpace.md),
                            _qrCard(context, c),
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            child: _statusPanel(context, c, status),
                          ),
                        ),
                        const SizedBox(width: TbSpace.md),
                        SizedBox(
                          width: 400,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _compositionCard(context, c),
                                const SizedBox(height: TbSpace.md),
                                _gifCard(context, c),
                                const SizedBox(height: TbSpace.md),
                                _qrCard(context, c),
                              ],
                            ),
                          ),
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
    );
  }

  Widget _header(BuildContext context, BoothController c, _PrintStatus status) {
    return Row(
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
        TbPill(
          label: _headerLabel(c),
          color: status.color,
          icon: status.icon,
          dense: true,
        ),
        if (c.job?.printerMode == 'mock') ...[
          const SizedBox(width: 8),
          const TbPill(
            label: 'Mock printer',
            color: TbColors.rose,
            icon: Icons.science_outlined,
            dense: true,
          ),
        ],
      ],
    );
  }

  Widget _statusPanel(
    BuildContext context,
    BoothController c,
    _PrintStatus status,
  ) {
    final job = c.job;
    final canReprint =
        c.phase == BoothPhase.done &&
        job != null &&
        (job.state == 'failed' || job.state == 'unknown');
    return TbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(status.icon, size: 28, color: status.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TbEyebrow(
                      c.phase == BoothPhase.done
                          ? 'Print result'
                          : 'Print progress',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      status.title,
                      style: Theme.of(
                        context,
                      ).textTheme.displaySmall?.copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status.body,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (c.error != null) ...[
            const SizedBox(height: TbSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TbColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(TbRadius.sm),
                border: Border.all(color: TbColors.red.withValues(alpha: 0.35)),
              ),
              child: Text(
                c.error!,
                style: const TextStyle(color: TbColors.red),
              ),
            ),
          ],
          if (c.submittedJobError != null) ...[
            const SizedBox(height: TbSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TbColors.rose.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(TbRadius.sm),
                border: Border.all(
                  color: TbColors.rose.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'Bridge status unavailable: ${c.submittedJobError}',
                style: const TextStyle(color: TbColors.rose),
              ),
            ),
          ],
          if (job != null) ...[
            const SizedBox(height: TbSpace.lg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TbColors.ink.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(TbRadius.md),
                border: Border.all(color: TbColors.line),
              ),
              child: Column(
                children: [
                  _jobRow('Job ID', job.id, mono: true),
                  const SizedBox(height: 10),
                  _jobRow('Bridge state', job.state),
                  const SizedBox(height: 10),
                  _jobRow(
                    'Completion',
                    job.completion,
                    color: job.completion == 'confirmed'
                        ? TbColors.mint
                        : TbColors.muted,
                  ),
                  const SizedBox(height: 10),
                  _jobRow('Attempts', '${job.attempts}'),
                ],
              ),
            ),
          ],
          if (canReprint) ...[
            const SizedBox(height: TbSpace.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: TbColors.rose),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    job.state == 'unknown'
                        ? 'Unknown is not failure. Check the printer output before creating a new print job.'
                        : 'The bridge did not confirm a print. Check the printer before creating a new job.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: TbSpace.xl),
          if (canReprint)
            TbSecondaryButton(
              label: 'Retry print (new job)',
              icon: Icons.replay_outlined,
              onPressed: () => _confirmReprint(context),
            ),
          if (c.submittedJob != null)
            TbSecondaryButton(
              label: c.submittedJobReconciling
                  ? 'Checking status…'
                  : 'Refresh status',
              icon: Icons.refresh_rounded,
              onPressed: c.submittedJobReconciling
                  ? null
                  : c.reconcileSubmittedJob,
            ),
          if (c.phase == BoothPhase.done) ...[
            if (canReprint) const SizedBox(height: TbSpace.sm),
            TbPrimaryButton(
              label: 'Next guest',
              icon: Icons.arrow_forward_rounded,
              expanded: true,
              onPressed: c.reset,
            ),
          ],
          if (c.phase == BoothPhase.error) ...[
            TbPrimaryButton(
              label: 'Back to start',
              icon: Icons.arrow_back_rounded,
              expanded: true,
              onPressed: c.reset,
            ),
          ],
          if (c.phase == BoothPhase.uploading ||
              c.phase == BoothPhase.printing) ...[
            const SizedBox(height: TbSpace.md),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Keep this screen open while the bridge responds.'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _jobRow(
    String label,
    String value, {
    bool mono = false,
    Color? color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(color: TbColors.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? TbColors.cream,
              fontSize: 12,
              fontFamily: mono ? 'Menlo' : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _compositionCard(BuildContext context, BoothController c) {
    return TbCard(
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: const [
              TbEyebrow('Final composition'),
              TbPill(label: '4×6 · 300 dpi', color: TbColors.gold, dense: true),
            ],
          ),
          const SizedBox(height: 14),
          if (c.compositionBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(TbRadius.sm),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Image.memory(c.compositionBytes!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            TbSecondaryButton(
              label: 'View final composition',
              icon: Icons.zoom_in_rounded,
              expanded: true,
              onPressed: () => _showComposition(context, c.compositionBytes!),
            ),
          ] else if (c.compositionLoading)
            const SizedBox(
              height: 240,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Preparing composition preview…'),
                  ],
                ),
              ),
            )
          else
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: TbColors.ink,
                borderRadius: BorderRadius.circular(TbRadius.sm),
                border: Border.all(color: TbColors.line),
              ),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  c.compositionError != null
                      ? 'Composition unavailable\n${c.compositionError}'
                      : 'The final 4×6 composition will appear here after the bridge composes it.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gifCard(BuildContext context, BoothController c) {
    final job = c.job;
    final state = job?.gifState ?? 'unknown';
    final ready = state == 'ready';
    final failed = state == 'failed';
    final pending = state == 'pending' || state == 'processing';
    return TbCard(
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TbEyebrow('Guest GIF'),
              const Spacer(),
              TbPill(
                label: ready
                    ? 'Ready'
                    : failed
                    ? 'Unavailable'
                    : pending
                    ? 'Preparing'
                    : 'Unknown',
                color: ready
                    ? TbColors.mint
                    : failed
                    ? TbColors.rose
                    : TbColors.gold,
                icon: ready
                    ? Icons.check_circle_outline
                    : failed
                    ? Icons.error_outline
                    : Icons.hourglass_top_rounded,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (c.gifBytes != null) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TbRadius.sm),
                child: SizedBox(
                  width: 150,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Image.memory(
                      c.gifBytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TbSecondaryButton(
              label: 'View animated GIF',
              icon: Icons.gif_box_outlined,
              expanded: true,
              onPressed: () => _showGif(context, c.gifBytes!),
            ),
          ] else if (failed)
            Text(
              c.gifError ?? 'Animated GIF could not be generated.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else if (pending || c.gifLoading)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preparing animated GIF… Photos, strip and QR are already available.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            )
          else if (c.gifError != null)
            Text(c.gifError!, style: Theme.of(context).textTheme.bodyMedium)
          else
            Text(
              'GIF status is not available from this bridge.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 10),
          Text(
            'The GIF is an independent guest download. It never blocks or changes the print result above.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRegenerate(
    BuildContext context,
    BoothController c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate guest link?'),
        content: const Text(
          'The current QR and link stop working. Guests who already scanned it must use the new link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (ok == true) await c.regenerateGuestAccess();
  }

  Future<void> _confirmRevoke(BuildContext context, BoothController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke guest access?'),
        content: const Text(
          'The QR and link stop working immediately. Photos remain on the booth and can be re-shared by regenerating a link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok == true) await c.revokeGuestAccess();
  }

  Widget _qrCard(BuildContext context, BoothController c) {
    final url = c.job?.deliveryUrl;
    return TbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TbEyebrow('Guest delivery'),
              const Spacer(),
              if (url != null)
                const TbPill(
                  label: 'Link ready',
                  color: TbColors.mint,
                  icon: Icons.link_rounded,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (url != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(TbRadius.md),
                ),
                child: QrImageView(
                  data: url,
                  size: 190,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Scan to download your photos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Guest downloads are served by the bridge over local Wi-Fi.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: TbColors.muted, fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy delivery link',
                  onPressed: () => _copyUrl(context, url),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TbSecondaryButton(
                  label: 'Copy guest link',
                  icon: Icons.copy_rounded,
                  onPressed: () => _copyUrl(context, url),
                ),
                TbSecondaryButton(
                  label: 'Regenerate link',
                  icon: Icons.refresh_rounded,
                  onPressed: () => _confirmRegenerate(context, c),
                ),
                TbSecondaryButton(
                  label: 'Revoke access',
                  icon: Icons.link_off_rounded,
                  onPressed: () => _confirmRevoke(context, c),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Session ${c.sessionId ?? "active"} · Local Wi-Fi only. Download counts are not tracked.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 6),
            Text(
              c.job?.gifState == 'ready'
                  ? 'Guest assets ready: photos, branded strip and GIF.'
                  : c.job?.gifState == 'failed'
                  ? 'Photos and branded strip are ready. GIF generation failed and is not offered.'
                  : 'Photos and branded strip are ready. GIF generation is in progress.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 11),
            ),
          ] else
            TbEmptyState(
              icon: Icons.qr_code_2_outlined,
              title: 'Guest access unavailable',
              message:
                  'No LAN-reachable guest link is active. Check the bridge LAN URL and regenerate access when the session is approved.',
              action: c.job == null
                  ? null
                  : TbSecondaryButton(
                      label: 'Generate guest link',
                      icon: Icons.link_rounded,
                      onPressed: c.regenerateGuestAccess,
                    ),
            ),
        ],
      ),
    );
  }
}

class _PrintStatus {
  final String title;
  final String body;
  final Color color;
  final IconData icon;
  const _PrintStatus({
    required this.title,
    required this.body,
    required this.color,
    required this.icon,
  });
}
