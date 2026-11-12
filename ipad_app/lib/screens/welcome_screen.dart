import 'dart:io';

import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../templates/builtin_templates.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import 'event_details_screen.dart';
import 'interrupted_session_screen.dart';
import 'events_screen.dart';
import 'settings_screen.dart';
import 'template_gallery_screen.dart';

class WelcomeScreen extends StatelessWidget {
  final BoothController controller;
  const WelcomeScreen({super.key, required this.controller});

  Future<void> _changeEvent(BuildContext context, BoothController c) async {
    final selected = await Navigator.of(context).push<EventProfile>(
      MaterialPageRoute(builder: (_) => EventsScreen(controller: c)),
    );
    if (!context.mounted || selected == null) return;
    await c.selectEvent(selected);
  }

  void _openEventDetails(BuildContext context, BoothController c) {
    if (!c.hasSelectedEvent) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EventDetailsScreen(controller: c, event: c.currentEvent),
      ),
    );
  }

  void _changeTemplate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplateGalleryScreen(controller: controller),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return TbBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(TbSpace.xl),
          child: Column(
            children: [
              _header(context, c),
              const SizedBox(height: TbSpace.lg),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final eventPanel = _eventPanel(context, c);
                    final boothPanel = _boothPanel(
                      context,
                      c,
                      scrollable: wide,
                    );
                    if (!wide) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            eventPanel,
                            const SizedBox(height: TbSpace.md),
                            boothPanel,
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: eventPanel),
                        const SizedBox(width: TbSpace.md),
                        Expanded(flex: 2, child: boothPanel),
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

  Widget _header(BuildContext context, BoothController c) {
    return Row(
      children: [
        const TbWordmark(),
        const SizedBox(width: TbSpace.md),
        Container(width: 1, height: 22, color: TbColors.line),
        const SizedBox(width: TbSpace.md),
        Text(
          'OPERATOR CONSOLE',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: TbColors.muted,
            letterSpacing: 2.0,
            fontSize: 10,
          ),
        ),
        const Spacer(),
        if (c.hasSelectedEvent)
          const TbPill(
            label: 'Event ready',
            color: TbColors.mint,
            icon: Icons.event_available_outlined,
            dense: true,
          )
        else
          const TbPill(
            label: 'Setup required',
            color: TbColors.rose,
            icon: Icons.event_busy_outlined,
            dense: true,
          ),
        const SizedBox(width: TbSpace.sm),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => _openSettings(context),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _eventPanel(BuildContext context, BoothController c) {
    if (!c.hasSelectedEvent) {
      return TbCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const TbEyebrow('Current event'),
            const SizedBox(height: 16),
            TbEmptyState(
              icon: Icons.event_note_outlined,
              title: 'No event selected',
              message:
                  'Create the event once, then the booth is ready for the first guest. Event selection is stored locally on this iPad.',
              action: Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  TbPrimaryButton(
                    label: 'Create event',
                    icon: Icons.add_rounded,
                    onPressed: () => _changeEvent(context, c),
                  ),
                  TbSecondaryButton(
                    label: 'Change event',
                    icon: Icons.event_outlined,
                    onPressed: () => _changeEvent(context, c),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return TbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TbEyebrow('Current event'),
              const Spacer(),
              TbPill(
                label: c.currentEvent.status.label,
                color: switch (c.currentEvent.status) {
                  EventStatus.active => TbColors.mint,
                  EventStatus.scheduled => TbColors.gold,
                  EventStatus.draft => TbColors.blue,
                  EventStatus.completed => TbColors.muted,
                  EventStatus.archived => TbColors.rose,
                },
                icon: Icons.circle,
                dense: true,
              ),
            ],
          ),
          if (MediaQuery.sizeOf(context).height >= 700) ...[
            const SizedBox(height: 18),
            _welcomeBanner(context, c),
            const SizedBox(height: 18),
          ],
          Text(
            c.currentEvent.configuration.welcome.title.trim().isEmpty
                ? c.eventTitle
                : c.currentEvent.configuration.welcome.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 10),
          Text(
            c.eventDate,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: TbColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: TbSpace.xl),
          Container(height: 1, color: TbColors.line),
          const SizedBox(height: TbSpace.lg),
          Row(
            children: [
              Expanded(
                child: TbMetric(
                  label: 'Session format',
                  value:
                      '${c.currentEvent.configuration.photoCount} photos · ${BuiltinTemplates.forPhotoCount(c.currentEvent.configuration.photoCount, preferred: BuiltinTemplates.byId(c.currentEvent.configuration.templateId)).name}',
                ),
              ),
              const SizedBox(width: TbSpace.md),
              Expanded(
                child: TbMetric(label: 'Delivery', value: 'Local QR · 24 h'),
              ),
            ],
          ),
          const SizedBox(height: TbSpace.lg),
          TbMetric(label: 'Event ID', value: c.eventId),
          const SizedBox(height: TbSpace.xl),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              TbSecondaryButton(
                label: 'Event details',
                icon: Icons.info_outline,
                onPressed: () => _openEventDetails(context, c),
              ),
              TbSecondaryButton(
                label: 'Change event',
                icon: Icons.event_repeat_rounded,
                onPressed: () => _changeEvent(context, c),
              ),
              TbSecondaryButton(
                label: 'Change template',
                icon: Icons.dashboard_customize_outlined,
                onPressed: () => _changeTemplate(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _welcomeBanner(BuildContext context, BoothController c) {
    final w = c.currentEvent.configuration.welcome;
    final hasImage =
        w.backgroundMode == WelcomeBackgroundMode.image &&
        w.backgroundImagePath != null &&
        File(w.backgroundImagePath!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(TbRadius.md),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: Color(w.backgroundValue),
          image: hasImage
              ? DecorationImage(
                  image: FileImage(File(w.backgroundImagePath!)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (w.logoPath != null && File(w.logoPath!).existsSync())
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Image.file(
                    File(w.logoPath!),
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.subtitle.trim().isEmpty
                          ? 'Welcome! Tap Start to begin your photo session.'
                          : w.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GUEST WELCOME PREVIEW',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boothPanel(
    BuildContext context,
    BoothController c, {
    required bool scrollable,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TbEyebrow('Booth console'),
        const SizedBox(height: 10),
        Text(
          c.hasSelectedEvent
              ? 'Ready for the next guest'
              : 'Set up the event first',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'The app captures three photos, lets the operator review, and submits one 4×6 composition to the local bridge.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (c.submittedJob != null) ...[
          const SizedBox(height: TbSpace.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: TbColors.rose.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(TbRadius.md),
              border: Border.all(color: TbColors.rose.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, color: TbColors.rose),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Submitted print job awaits reconciliation.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  c.submittedJobError ??
                      'Bridge status is unavailable. The job reference is preserved locally; no resubmission will occur.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TbSecondaryButton(
                      label: c.submittedJobReconciling
                          ? 'Checking…'
                          : 'Refresh status',
                      onPressed: c.submittedJobReconciling
                          ? null
                          : c.reconcileSubmittedJob,
                    ),
                    TbSecondaryButton(
                      label: 'Dismiss',
                      onPressed: c.dismissSubmittedJob,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (c.interruptedSession != null) ...[
          const SizedBox(height: TbSpace.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: TbColors.rose.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(TbRadius.md),
              border: Border.all(color: TbColors.rose.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: TbColors.rose),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'An interrupted session was found on this iPad. Its photos are preserved in session history; it was not resumed automatically.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      TbSecondaryButton(
                        label: 'Review recovery',
                        icon: Icons.restore_rounded,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                InterruptedSessionScreen(controller: c),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (c.restorableSession != null) ...[
          const SizedBox(height: TbSpace.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: TbColors.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(TbRadius.md),
              border: Border.all(color: TbColors.gold.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.restore_rounded, color: TbColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A previous unsubmitted review is stored on this iPad.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TbSecondaryButton(
                  label: 'Resume',
                  onPressed: c.restorePreviousSession,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: TbSpace.lg),
        _statusRow(
          context,
          icon: Icons.videocam_outlined,
          title: c.isMock ? 'Simulated camera' : c.camera.name,
          detail: c.isMock
              ? 'Mock capture — no Canon EOS 60D connection.'
              : 'Camera service connected.',
          color: c.isMock ? TbColors.rose : TbColors.mint,
          badge: c.isMock ? 'SIMULATED CAMERA' : 'CAMERA',
        ),
        const SizedBox(height: 12),
        _statusRow(
          context,
          icon: Icons.print_outlined,
          title: 'Local bridge',
          detail: c.bridge.baseUrl,
          color: TbColors.gold,
          badge: 'SETTINGS',
        ),
        const SizedBox(height: TbSpace.xl),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: TbColors.ink.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(TbRadius.md),
            border: Border.all(color: TbColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: TbColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Retake All is the event workflow. Original captures are never overwritten.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: TbSpace.md),
        TbPrimaryButton(
          label:
              c.hasSelectedEvent &&
                  c.currentEvent.configuration.welcome.buttonLabel
                      .trim()
                      .isNotEmpty
              ? c.currentEvent.configuration.welcome.buttonLabel
              : 'Start Session',
          icon: Icons.camera_alt_outlined,
          expanded: true,
          onPressed:
              c.hasSelectedEvent &&
                  c.submittedJob == null &&
                  (c.currentEvent.status == EventStatus.scheduled ||
                      c.currentEvent.status == EventStatus.active)
              ? c.startSession
              : null,
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            c.submittedJob != null
                ? 'Resolve the previous submitted job first'
                : c.hasSelectedEvent
                ? '${c.currentEvent.configuration.photoCount} photos · '
                      '${c.currentEvent.configuration.countdownSeconds == 0 ? "no countdown" : "${c.currentEvent.configuration.countdownSeconds}s countdown"}'
                : 'Create or select an event to continue',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
    return TbCard(
      color: TbColors.surfaceRaised,
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _statusRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    required Color color,
    required String badge,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TbPill(label: badge, color: color, dense: true),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
