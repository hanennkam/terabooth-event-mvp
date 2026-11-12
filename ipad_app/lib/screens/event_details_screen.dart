import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../services/event_report_service.dart';
import '../templates/builtin_templates.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import 'branding_editor_screen.dart';
import 'event_form_screen.dart';

class EventDetailsScreen extends StatefulWidget {
  final BoothController controller;
  final EventProfile event;

  const EventDetailsScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  Future<List<BoothSessionRecord>>? _sessions;

  @override
  void initState() {
    super.initState();
    _reloadSessions();
  }

  void _reloadSessions() {
    _sessions = widget.controller.storage.readSessionsForEvent(widget.event.id);
  }

  EventProfile get _event => widget.controller.events.firstWhere(
    (item) => item.id == widget.event.id,
    orElse: () => widget.event,
  );

  Color _statusColor(EventStatus status) => switch (status) {
    EventStatus.active => TbColors.mint,
    EventStatus.scheduled => TbColors.gold,
    EventStatus.draft => TbColors.blue,
    EventStatus.completed => TbColors.muted,
    EventStatus.archived => TbColors.rose,
  };

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<EventProfile>(
      MaterialPageRoute(
        builder: (_) =>
            EventFormScreen(controller: widget.controller, initial: _event),
      ),
    );
    if (!mounted || saved == null) return;
    setState(_reloadSessions);
  }

  Future<void> _exportCsv() async {
    final sessions = await widget.controller.storage.readSessionsForEvent(
      _event.id,
    );
    if (!mounted) return;
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No sessions to export.')));
      return;
    }
    final report = EventReport(event: _event, sessions: sessions);
    try {
      final path = await widget.controller.storage.exportEventReportCsv(report);
      if (!mounted) return;
      final name = path.split('/').last;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report exported: $name')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _branding() async {
    final saved = await Navigator.of(context).push<EventProfile>(
      MaterialPageRoute(
        builder: (_) =>
            BrandingEditorScreen(controller: widget.controller, event: _event),
      ),
    );
    if (!mounted || saved == null) return;
    setState(_reloadSessions);
  }

  Future<void> _transition(EventStatus next, {bool confirm = false}) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Move to ${next.label}?'),
          content: Text(
            next == EventStatus.archived
                ? 'Archived events are read-only for booth sessions. Existing sessions and photos are preserved.'
                : 'This changes the event status. Sessions and photos are preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Move to ${next.label}'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.controller.transitionEventStatus(_event.id, next);
      if (mounted) setState(() {});
    } on EventValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete draft event?'),
        content: const Text(
          'Only an empty draft with no sessions can be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete draft'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.deleteDraftEvent(_event.id);
      if (mounted) Navigator.pop(context);
    } on EventValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _start() async {
    await widget.controller.selectEvent(_event);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.controller.startSession();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: c,
            builder: (context, _) {
              final event = _event;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(TbSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TbPageHeader(
                      showBack: true,
                      eyebrow: 'Event',
                      title: event.title,
                      subtitle: event.client.isEmpty
                          ? event.date
                          : '${event.client} · ${event.date}',
                      actions: [
                        TbPill(
                          label: event.status.label,
                          color: _statusColor(event.status),
                          icon: Icons.circle,
                          dense: true,
                        ),
                        TbSecondaryButton(
                          label: 'Branding',
                          icon: Icons.palette_outlined,
                          onPressed: _branding,
                        ),
                        TbSecondaryButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          onPressed: _edit,
                        ),
                      ],
                    ),
                    const SizedBox(height: TbSpace.lg),
                    TbCard(
                      color: TbColors.surfaceRaised,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const TbEyebrow('Event overview'),
                          const SizedBox(height: TbSpace.md),
                          Wrap(
                            spacing: TbSpace.xl,
                            runSpacing: TbSpace.md,
                            children: [
                              TbMetric(label: 'Date', value: event.date),
                              TbMetric(
                                label: 'Time',
                                value:
                                    '${event.startTime.isEmpty ? "—" : event.startTime} – ${event.endTime.isEmpty ? "—" : event.endTime}',
                              ),
                              TbMetric(
                                label: 'Venue',
                                value: event.venue.isEmpty ? '—' : event.venue,
                              ),
                              TbMetric(
                                label: 'Client',
                                value: event.client.isEmpty
                                    ? '—'
                                    : event.client,
                              ),
                              TbMetric(
                                label: 'Layout',
                                value: BuiltinTemplates.forPhotoCount(
                                  event.configuration.photoCount,
                                  preferred: BuiltinTemplates.byId(
                                    event.configuration.templateId,
                                  ),
                                ).name,
                              ),
                              TbMetric(
                                label: 'Sessions',
                                value: '${c.sessionHistory.length}',
                              ),
                              TbMetric(
                                label: 'Photos',
                                value:
                                    '${c.sessionHistory.fold<int>(0, (sum, session) => sum + session.photoCount)}',
                              ),
                            ],
                          ),
                          if (event.description.isNotEmpty) ...[
                            const SizedBox(height: TbSpace.lg),
                            Text(event.description),
                          ],
                          const SizedBox(height: TbSpace.lg),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (event.status == EventStatus.scheduled ||
                                  event.status == EventStatus.active)
                                TbPrimaryButton(
                                  label: 'Start booth session',
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: _start,
                                ),
                              if (event.status == EventStatus.draft)
                                TbSecondaryButton(
                                  label: 'Schedule event',
                                  onPressed: () =>
                                      _transition(EventStatus.scheduled),
                                ),
                              if (event.status == EventStatus.scheduled)
                                TbSecondaryButton(
                                  label: 'Activate',
                                  onPressed: () =>
                                      _transition(EventStatus.active),
                                ),
                              if (event.status == EventStatus.active)
                                TbSecondaryButton(
                                  label: 'Complete event',
                                  onPressed: () => _transition(
                                    EventStatus.completed,
                                    confirm: true,
                                  ),
                                ),
                              if (event.status != EventStatus.archived)
                                TbSecondaryButton(
                                  label: 'Archive',
                                  onPressed: () => _transition(
                                    EventStatus.archived,
                                    confirm: true,
                                  ),
                                ),
                              if (event.status == EventStatus.draft)
                                TbSecondaryButton(
                                  label: 'Delete draft',
                                  onPressed: _deleteDraft,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: TbSpace.md),
                    TbCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const TbEyebrow('Session history'),
                              const Spacer(),
                              TbSecondaryButton(
                                label: 'Export CSV',
                                icon: Icons.download_outlined,
                                onPressed: _exportCsv,
                              ),
                            ],
                          ),
                          const SizedBox(height: TbSpace.md),
                          FutureBuilder<List<BoothSessionRecord>>(
                            future: _sessions,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: LinearProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Text(
                                  'Session history unavailable: ${snapshot.error}',
                                  style: const TextStyle(color: TbColors.red),
                                );
                              }
                              final sessions = snapshot.data ?? const [];
                              if (sessions.isEmpty) {
                                return Text(
                                  'No sessions yet. Start the booth when the event opens.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                );
                              }
                              return Column(
                                children: [
                                  for (var i = 0; i < sessions.length; i++) ...[
                                    _sessionRow(context, sessions[i]),
                                    if (i < sessions.length - 1)
                                      const Divider(height: 24),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sessionRow(BuildContext context, BoothSessionRecord session) {
    final statusColor = session.approved
        ? TbColors.mint
        : session.status == BoothSessionStatus.interrupted
        ? TbColors.rose
        : session.status == BoothSessionStatus.active
        ? TbColors.gold
        : TbColors.muted;
    final started = session.startedAt;
    final subtitle = started == null
        ? 'Time unavailable'
        : '${started.toLocal().toString().split('.').first} · ${session.photoCount} photos';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.sessionId,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        TbPill(label: session.displayStatus, color: statusColor, dense: true),
      ],
    );
  }
}
