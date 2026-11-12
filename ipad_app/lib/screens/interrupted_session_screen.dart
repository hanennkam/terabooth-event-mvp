import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class InterruptedSessionScreen extends StatelessWidget {
  final BoothController controller;

  const InterruptedSessionScreen({super.key, required this.controller});

  Future<void> _resume(BuildContext context) async {
    final ok = await controller.resumeInterruptedSession();
    if (!context.mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _close(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close and recover this session?'),
        content: const Text(
          'Valid originals stay on this iPad and the session is marked recovered. The session will not be resumed automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close & recover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.closeInterruptedSession();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final recovery = controller.interruptedRecovery;
    final record = controller.interruptedSession;
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TbSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TbPageHeader(
                  showBack: true,
                  eyebrow: 'Session recovery',
                  title: 'Interrupted session',
                  subtitle:
                      'Choose explicitly how to proceed. Nothing is resumed or completed automatically.',
                ),
                const SizedBox(height: TbSpace.lg),
                TbCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TbEyebrow(record?.sessionId ?? 'Session'),
                      const SizedBox(height: 10),
                      if (recovery == null)
                        const Text('Recovery details are unavailable.')
                      else ...[
                        Text(
                          '${recovery.photos.length} of ${record?.expectedPhotoCount ?? 0} photos are valid.',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          recovery.canResume
                              ? 'Resume will keep the existing photos and capture only the remaining slots.'
                              : 'One or more original files are missing or invalid. Safe resume is disabled; close and recover keeps the valid files.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (recovery.photos.isNotEmpty) ...[
                          const SizedBox(height: TbSpace.md),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final photo in recovery.photos)
                                SizedBox(
                                  width: 100,
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        photo.bytes,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: TbSpace.lg),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          TbPrimaryButton(
                            label: 'Resume session',
                            icon: Icons.play_arrow_rounded,
                            onPressed: recovery?.canResume == true
                                ? () => _resume(context)
                                : null,
                          ),
                          TbSecondaryButton(
                            label: 'Close & recover',
                            icon: Icons.archive_outlined,
                            onPressed: recovery == null
                                ? null
                                : () => _close(context),
                          ),
                          TbSecondaryButton(
                            label: 'Cancel',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
