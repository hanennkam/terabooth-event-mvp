import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../services/camera_pipeline.dart';
import '../theme/tb_theme.dart';
import '../widgets/session_clock.dart';
import '../widgets/tb_ui.dart';

class CaptureScreen extends StatelessWidget {
  final BoothController controller;
  const CaptureScreen({super.key, required this.controller});

  String _connectionLabel(CameraConnectionState state) {
    return switch (state) {
      CameraConnectionState.disconnected => 'Camera offline',
      CameraConnectionState.discovering => 'Finding camera',
      CameraConnectionState.connecting => 'Connecting camera',
      CameraConnectionState.connected => 'Camera ready',
      CameraConnectionState.recovering => 'Recovering camera',
      CameraConnectionState.failed => 'Camera error',
    };
  }

  Color _connectionColor(CameraConnectionState state) {
    return switch (state) {
      CameraConnectionState.connected => TbColors.mint,
      CameraConnectionState.connecting ||
      CameraConnectionState.discovering ||
      CameraConnectionState.recovering => TbColors.gold,
      _ => TbColors.red,
    };
  }

  String _captureLabel(BoothController c) {
    if (c.captureState == CameraCaptureState.capturing) {
      return 'Capturing photo ${c.activePhoto}…';
    }
    if (c.captureState == CameraCaptureState.transferring) {
      return 'Saving photo ${c.activePhoto}…';
    }
    if (c.countdown > 0) return 'Get ready';
    if (c.photos.isNotEmpty) return 'Photo ${c.photos.length} captured';
    return 'Connecting to camera';
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return TbBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TbSpace.lg),
          child: Column(
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
                  SessionClock(controller: c),
                  const SizedBox(width: 12),
                  TbPill(
                    label:
                        'Capture ${c.activePhoto.clamp(1, c.expectedPhotoCount)} of ${c.expectedPhotoCount}',
                    color: TbColors.gold,
                    icon: Icons.camera_alt_outlined,
                    dense: true,
                  ),
                  const SizedBox(width: 8),
                  const TbPill(
                    label: 'Simulated',
                    color: TbColors.rose,
                    icon: Icons.science_outlined,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: TbSpace.lg),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final viewfinder = _viewfinder(context, c);
                    final progress = _progressPanel(context, c);
                    if (!wide) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: 420, child: viewfinder),
                            const SizedBox(height: TbSpace.md),
                            progress,
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: viewfinder),
                        const SizedBox(width: TbSpace.md),
                        SizedBox(width: 380, child: progress),
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

  Widget _viewfinder(BuildContext context, BoothController c) {
    final connectionColor = _connectionColor(c.connectionState);
    return TbCard(
      padding: EdgeInsets.zero,
      color: const Color(0xFF101217),
      borderColor: TbColors.line,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(TbRadius.lg),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (c.liveViewFrame != null)
                    Positioned.fill(
                      child: Image.memory(
                        c.liveViewFrame!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    )
                  else ...[
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.1,
                          colors: [Color(0xFF262A33), Color(0xFF111318)],
                        ),
                      ),
                    ),
                    CustomPaint(painter: _ViewfinderPainter()),
                  ],
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            c.countdown > 0 ? '${c.countdown}' : '',
                            key: ValueKey(c.countdown),
                            style: const TextStyle(
                              color: TbColors.cream,
                              fontSize: 128,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: -4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _captureLabel(c),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.countdown > 0 ? 'Look at the camera' : 'Keep still',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 18,
                    left: 18,
                    child: TbPill(
                      label: _connectionLabel(c.connectionState),
                      color: connectionColor,
                      icon: Icons.circle,
                      dense: true,
                    ),
                  ),
                  Positioned(
                    top: 18,
                    right: 18,
                    child: TbPill(
                      label: c.isMock ? 'Mock viewfinder' : 'Live view',
                      color: c.isMock ? TbColors.rose : TbColors.mint,
                      icon: c.isMock
                          ? Icons.science_outlined
                          : Icons.videocam_outlined,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              color: TbColors.surface,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(TbRadius.lg),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  size: 20,
                  color: _connectionColor(c.connectionState),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.isMock
                        ? 'SIMULATED CAMERA — mock images, not Canon EOS 60D capture.'
                        : c.camera.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${c.photos.length}/3 captured',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, BoothController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text(
          'The active guest session will stop after any in-flight capture. Captured originals stay in session history; the session is marked interrupted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep session'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (ok == true) await c.endSession();
  }

  Widget _progressPanel(BuildContext context, BoothController c) {
    return TbCard(
      color: TbColors.surfaceRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TbEyebrow('Session progress'),
              const Spacer(),
              TbPill(
                label: c.sessionStatus == 'ending' ? 'Ending' : 'Active',
                color: c.sessionStatus == 'ending'
                    ? TbColors.rose
                    : TbColors.mint,
                icon: Icons.circle,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Photo ${c.activePhoto.clamp(1, c.expectedPhotoCount)}',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  'of ${c.expectedPhotoCount}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: TbColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (c.photos.length / c.expectedPhotoCount).clamp(0.0, 1.0),
              minHeight: 8,
            ),
          ),
          if (c.liveViewError != null) ...[
            const SizedBox(height: 10),
            Text(
              'Live View: ${c.liveViewError}',
              style: const TextStyle(color: TbColors.muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: TbSpace.lg),
          for (var i = 0; i < c.expectedPhotoCount; i++) ...[
            _stepRow(context, c, i),
            if (i < c.expectedPhotoCount - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: TbSpace.lg),
          Container(height: 1, color: TbColors.line),
          const SizedBox(height: TbSpace.lg),
          Row(
            children: [
              const TbSectionLabel('Captures'),
              const Spacer(),
              Text(
                c.captureState == CameraCaptureState.transferring
                    ? 'Transferring…'
                    : c.captureState == CameraCaptureState.capturing
                    ? 'Capturing…'
                    : 'Auto',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < c.expectedPhotoCount; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == c.expectedPhotoCount - 1 ? 0 : 8,
                    ),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: TbColors.ink,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: i == c.photos.length - 1
                                ? TbColors.gold
                                : TbColors.line,
                          ),
                          image: i < c.photos.length
                              ? DecorationImage(
                                  image: MemoryImage(c.photos[i].bytes),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: i < c.photos.length
                            ? const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: TbColors.mint,
                                  ),
                                ),
                              )
                            : Text(
                                '${i + 1}',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(color: TbColors.muted),
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: TbSpace.lg),
          if (c.countdownActive) ...[
            SizedBox(
              width: double.infinity,
              child: TbPrimaryButton(
                label: c.countdown > 0
                    ? 'Cancel countdown (${c.countdown})'
                    : 'Cancel countdown',
                icon: Icons.close_rounded,
                onPressed: c.cancelCountdown,
              ),
            ),
            const SizedBox(height: TbSpace.sm),
          ],
          SizedBox(
            width: double.infinity,
            child: TbSecondaryButton(
              label: c.sessionStatus == 'ending'
                  ? 'Ending after current capture…'
                  : 'End session',
              icon: Icons.stop_circle_outlined,
              onPressed: c.sessionStatus == 'ending'
                  ? null
                  : () => _confirmEnd(context, c),
            ),
          ),
          const SizedBox(height: TbSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: TbColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Capture is automatic. Do not close the app or leave this screen until all ${c.expectedPhotoCount} photos are saved.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepRow(BuildContext context, BoothController c, int index) {
    final done = index < c.photos.length;
    final active = index == c.photos.length && c.phase == BoothPhase.capturing;
    final color = done
        ? TbColors.mint
        : active
        ? TbColors.gold
        : TbColors.muted;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: done || active ? 0.16 : 0.06),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, size: 16, color: TbColors.mint)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            done
                ? 'Photo ${index + 1} saved'
                : active
                ? 'Capturing photo ${index + 1}'
                : 'Photo ${index + 1} pending',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: done || active ? TbColors.cream : TbColors.muted,
              fontWeight: done || active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final thirdW = size.width / 3;
    final thirdH = size.height / 3;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(thirdW * i, 0),
        Offset(thirdW * i, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, thirdH * i),
        Offset(size.width, thirdH * i),
        paint,
      );
    }
    final corner = Paint()
      ..color = TbColors.gold.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const len = 28.0;
    const inset = 22.0;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + len, rect.top)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left, rect.top + len),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + len),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - len)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + len, rect.bottom),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - len),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
