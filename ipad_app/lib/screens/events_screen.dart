import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';
import 'event_details_screen.dart';
import 'event_form_screen.dart';

class EventsScreen extends StatefulWidget {
  final BoothController controller;
  const EventsScreen({super.key, required this.controller});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  final _search = TextEditingController();
  EventStatus? _filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<EventProfile> _visibleEvents(BoothController c) {
    final query = _search.text.trim().toLowerCase();
    return c.events.where((event) {
      if (_filter != null && event.status != _filter) return false;
      if (query.isEmpty) return true;
      return event.title.toLowerCase().contains(query) ||
          event.client.toLowerCase().contains(query) ||
          event.venue.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _create() async {
    final result = await Navigator.of(context).push<EventProfile>(
      MaterialPageRoute(
        builder: (_) => EventFormScreen(controller: widget.controller),
      ),
    );
    if (!mounted || result == null) return;
    await widget.controller.selectEvent(result);
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _select(EventProfile event) async {
    await widget.controller.selectEvent(event);
    if (mounted) Navigator.pop(context, event);
  }

  Future<void> _openDetails(EventProfile event) async {
    final selected = await Navigator.of(context).push<EventProfile>(
      MaterialPageRoute(
        builder: (_) =>
            EventDetailsScreen(controller: widget.controller, event: event),
      ),
    );
    if (!mounted || selected == null) return;
    await widget.controller.selectEvent(selected);
    if (mounted) Navigator.pop(context, selected);
  }

  Color _statusColor(EventStatus status) => switch (status) {
    EventStatus.active => TbColors.mint,
    EventStatus.scheduled => TbColors.gold,
    EventStatus.draft => TbColors.blue,
    EventStatus.completed => TbColors.muted,
    EventStatus.archived => TbColors.rose,
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(TbSpace.xl),
            child: AnimatedBuilder(
              animation: c,
              builder: (context, _) {
                final visible = _visibleEvents(c);
                return Column(
                  children: [
                    TbPageHeader(
                      showBack: true,
                      eyebrow: 'Operator',
                      title: 'Select event',
                      subtitle:
                          'Create once, configure the booth, and keep every guest session in one place.',
                      actions: [
                        TbPrimaryButton(
                          label: 'Create new event',
                          icon: Icons.add_rounded,
                          onPressed: _create,
                        ),
                      ],
                    ),
                    const SizedBox(height: TbSpace.lg),
                    TbCard(
                      color: TbColors.surface,
                      child: Column(
                        children: [
                          TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Search name, client or venue',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _filterChip(null, 'All'),
                                for (final status in EventStatus.values)
                                  _filterChip(status, status.label),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: TbSpace.lg),
                    Expanded(
                      child: c.eventsLoading
                          ? const Center(child: CircularProgressIndicator())
                          : c.eventsError != null
                          ? SingleChildScrollView(
                              child: TbEmptyState(
                                icon: Icons.error_outline,
                                title: 'Events unavailable',
                                message: c.eventsError!,
                                action: TbSecondaryButton(
                                  label: 'Retry',
                                  onPressed: c.loadEvents,
                                ),
                              ),
                            )
                          : visible.isEmpty
                          ? SingleChildScrollView(
                              child: TbEmptyState(
                                icon: Icons.event_note_outlined,
                                title: c.events.isEmpty
                                    ? 'No events yet'
                                    : 'No matching events',
                                message: c.events.isEmpty
                                    ? 'Create your first event to configure a booth session.'
                                    : 'Adjust the search or status filter.',
                                action: c.events.isEmpty
                                    ? TbPrimaryButton(
                                        label: 'Create event',
                                        onPressed: _create,
                                      )
                                    : null,
                              ),
                            )
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: TbSpace.sm),
                              itemBuilder: (context, index) {
                                final event = visible[index];
                                final selected = event.id == c.eventId;
                                return TbCard(
                                  color: selected
                                      ? TbColors.surfaceRaised
                                      : TbColors.surface,
                                  borderColor: selected
                                      ? TbColors.gold.withValues(alpha: 0.55)
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: _statusColor(
                                            event.status,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.event_outlined,
                                          color: _statusColor(event.status),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              event.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleLarge,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              [
                                                event.date,
                                                if (event.client.isNotEmpty)
                                                  event.client,
                                                if (event.venue.isNotEmpty)
                                                  event.venue,
                                              ].join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      TbPill(
                                        label: event.status.label,
                                        color: _statusColor(event.status),
                                        dense: true,
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Event details',
                                        onPressed: () => _openDetails(event),
                                        icon: const Icon(
                                          Icons.chevron_right_rounded,
                                        ),
                                      ),
                                      TbSecondaryButton(
                                        label: selected ? 'Selected' : 'Use',
                                        onPressed: selected
                                            ? null
                                            : () => _select(event),
                                      ),
                                    ],
                                  ),
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
      ),
    );
  }

  Widget _filterChip(EventStatus? status, String label) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filter = status),
      ),
    );
  }
}
