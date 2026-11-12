import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../models.dart';
import '../templates/builtin_templates.dart';
import '../templates/template_models.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class EventFormScreen extends StatefulWidget {
  final BoothController controller;
  final EventProfile? initial;

  const EventFormScreen({super.key, required this.controller, this.initial});

  @override
  State<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends State<EventFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _client;
  late final TextEditingController _venue;
  late final TextEditingController _description;
  late final TextEditingController _startTime;
  late final TextEditingController _endTime;
  late DateTime _date;
  late EventStatus _newStatus;
  late int _photoCount;
  late int _countdown;
  late PhotoTemplate _template;
  bool _saving = false;
  String? _error;

  EventProfile? get _initial => widget.initial;

  @override
  void initState() {
    super.initState();
    final initial = _initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _client = TextEditingController(text: initial?.client ?? '');
    _venue = TextEditingController(text: initial?.venue ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _startTime = TextEditingController(text: initial?.startTime ?? '18:00');
    _endTime = TextEditingController(text: initial?.endTime ?? '22:00');
    _date =
        DateTime.tryParse(initial?.dateIso ?? '') ??
        DateTime.now().copyWith(
          hour: 0,
          minute: 0,
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );
    _newStatus = initial?.status ?? EventStatus.scheduled;
    _photoCount = (initial?.configuration.photoCount ?? 3).clamp(1, 4);
    _countdown = initial?.configuration.countdownSeconds ?? 3;
    _template = BuiltinTemplates.forPhotoCount(
      _photoCount,
      preferred: BuiltinTemplates.byId(
        initial?.configuration.templateId ?? BuiltinTemplates.defaultStrip.id,
      ),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _client.dispose();
    _venue.dispose();
    _description.dispose();
    _startTime.dispose();
    _endTime.dispose();
    super.dispose();
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _displayDate(DateTime date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final parts = controller.text.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 18,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() {
      controller.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Event name is required.');
      return;
    }
    if (_startTime.text.trim().isEmpty || _endTime.text.trim().isEmpty) {
      setState(() => _error = 'Start and end times are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final now = DateTime.now().toUtc();
    final base = _initial;
    final configuration =
        (_initial?.configuration ?? const EventConfiguration()).copyWith(
          templateId: _template.id,
          templateVersion: _template.version,
          photoCount: _photoCount,
          countdownSeconds: _countdown,
        );
    final event = EventProfile(
      id: base?.id ?? 'evt_${now.microsecondsSinceEpoch}',
      title: title,
      date: _displayDate(_date),
      dateIso: _isoDate(_date),
      client: _client.text.trim(),
      startTime: _startTime.text.trim(),
      endTime: _endTime.text.trim(),
      venue: _venue.text.trim(),
      description: _description.text.trim(),
      status: base?.status ?? _newStatus,
      configuration: configuration,
      createdAt: base?.createdAt ?? now,
      updatedAt: now,
      archivedAt: base?.archivedAt,
    );
    try {
      event.validate();
      final saved = base == null
          ? await widget.controller.createEventProfile(event)
          : await widget.controller.updateEvent(event);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } on EventValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Event could not be saved: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _initial != null;
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
                  eyebrow: editing ? 'Edit event' : 'New event',
                  title: editing ? 'Edit event' : 'Create event',
                  subtitle:
                      'Set the essentials now. Configuration is stored with the event and can be refined before the booth opens.',
                ),
                const SizedBox(height: TbSpace.lg),
                TbCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TbEyebrow('Event information'),
                      const SizedBox(height: TbSpace.md),
                      TextField(
                        controller: _title,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Event name *',
                          hintText: 'e.g. Kate & Jack',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _client,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Client or organisation',
                          hintText: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Event date *',
                                  suffixIcon: Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                ),
                                child: Text(_displayDate(_date)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _startTime,
                              readOnly: true,
                              onTap: () => _pickTime(_startTime),
                              decoration: const InputDecoration(
                                labelText: 'Start time *',
                                suffixIcon: Icon(Icons.schedule_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _endTime,
                              readOnly: true,
                              onTap: () => _pickTime(_endTime),
                              decoration: const InputDecoration(
                                labelText: 'End time *',
                                suffixIcon: Icon(Icons.schedule_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _venue,
                        decoration: const InputDecoration(
                          labelText: 'Venue',
                          hintText: 'Optional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Event description',
                          hintText: 'Optional notes for the operator',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: TbSpace.md),
                TbCard(
                  color: TbColors.surfaceRaised,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TbEyebrow('Booth configuration'),
                      const SizedBox(height: TbSpace.md),
                      if (_initial == null) ...[
                        DropdownButtonFormField<EventStatus>(
                          initialValue: _newStatus,
                          decoration: const InputDecoration(
                            labelText: 'Initial status',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: EventStatus.draft,
                              child: Text('Draft'),
                            ),
                            DropdownMenuItem(
                              value: EventStatus.scheduled,
                              child: Text('Scheduled'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _newStatus = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      DropdownButtonFormField<int>(
                        initialValue: _photoCount,
                        decoration: const InputDecoration(
                          labelText: 'Photos per session',
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 photo')),
                          DropdownMenuItem(value: 2, child: Text('2 photos')),
                          DropdownMenuItem(value: 3, child: Text('3 photos')),
                          DropdownMenuItem(value: 4, child: Text('4 photos')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _photoCount = value;
                            _template = BuiltinTemplates.forPhotoCount(
                              _photoCount,
                              preferred: _template,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _countdown,
                        decoration: const InputDecoration(
                          labelText: 'Countdown',
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 3, child: Text('3 seconds')),
                          DropdownMenuItem(value: 5, child: Text('5 seconds')),
                          DropdownMenuItem(
                            value: 10,
                            child: Text('10 seconds'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _countdown = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_photoCount == 3)
                        DropdownButtonFormField<PhotoTemplate>(
                          initialValue: _template,
                          decoration: const InputDecoration(
                            labelText: 'Photo layout',
                          ),
                          items: [
                            for (final template in BuiltinTemplates.all)
                              DropdownMenuItem(
                                value: template,
                                child: Text(template.name),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _template = value);
                            }
                          },
                        )
                      else
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Photo layout',
                          ),
                          child: Text(_template.name),
                        ),
                      const SizedBox(height: 12),
                      _configRow('Retake policy', 'Retake All'),
                      _configRow('Review', 'Operator review required'),
                      _configRow('Output', 'JPEG · local bridge'),
                      _configRow(
                        'Branding',
                        _initial?.configuration.branding.enabled == true
                            ? 'Configured per event'
                            : 'Default template branding',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Configuration is stored with the event. Options marked fixed reflect the current booth pipeline and are not fake controls.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (editing) ...[
                  const SizedBox(height: TbSpace.md),
                  Text(
                    'Editing event details does not change existing sessions or photos.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: TbSpace.md),
                  Text(_error!, style: const TextStyle(color: TbColors.red)),
                ],
                const SizedBox(height: TbSpace.lg),
                Row(
                  children: [
                    TbPrimaryButton(
                      label: _saving
                          ? 'Saving…'
                          : editing
                          ? 'Save changes'
                          : 'Create event',
                      icon: Icons.check_rounded,
                      onPressed: _saving ? null : _save,
                    ),
                    const SizedBox(width: 12),
                    TbSecondaryButton(
                      label: 'Cancel',
                      onPressed: _saving ? null : () => Navigator.pop(context),
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

  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
