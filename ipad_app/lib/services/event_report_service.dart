import '../models.dart';

class EventReport {
  final EventProfile event;
  final List<BoothSessionRecord> sessions;

  const EventReport({required this.event, required this.sessions});

  int get totalPhotos =>
      sessions.fold(0, (sum, session) => sum + session.photoCount);

  int get approvedSessions =>
      sessions.where((session) => session.approved).length;

  int get approvedPhotos => sessions
      .where((session) => session.approved)
      .fold(0, (sum, session) => sum + session.photoCount);

  int get interruptedSessions =>
      sessions.where((session) => session.status == 'interrupted').length;

  Duration get totalDuration {
    var seconds = 0;
    for (final session in sessions) {
      final start = session.startedAt;
      final end = session.endedAt;
      if (start != null && end != null && end.isAfter(start)) {
        seconds += end.difference(start).inSeconds;
      }
    }
    return Duration(seconds: seconds);
  }

  String get summary =>
      '${sessions.length} sessions · $totalPhotos photos · $approvedSessions approved';

  String toCsv() {
    final rows = <List<String>>[
      [
        'event_name',
        'event_date',
        'client',
        'venue',
        'session_id',
        'started_at',
        'ended_at',
        'duration_seconds',
        'photo_count',
        'approved',
        'status',
        'interrupted',
      ],
      for (final session in sessions)
        [
          event.title,
          event.date,
          event.client,
          event.venue,
          session.sessionId,
          session.startedAt?.toUtc().toIso8601String() ?? '',
          session.endedAt?.toUtc().toIso8601String() ?? '',
          _durationSeconds(session).toString(),
          session.photoCount.toString(),
          session.approved ? 'yes' : 'no',
          session.displayStatus,
          session.status == 'interrupted' ? 'yes' : 'no',
        ],
    ];
    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  int _durationSeconds(BoothSessionRecord session) {
    final start = session.startedAt;
    final end = session.endedAt;
    if (start == null || end == null || end.isBefore(start)) return 0;
    return end.difference(start).inSeconds;
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
