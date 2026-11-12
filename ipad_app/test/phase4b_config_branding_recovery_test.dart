import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/event_report_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';
import 'package:terabooth_ipad/templates/builtin_templates.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  BoothController controllerFor(
    Directory temp, {
    TestCamera? camera,
    Duration countdownDelay = Duration.zero,
  }) => BoothController(
    camera: camera ?? TestCamera(bytes: jpeg),
    storage: StorageService(rootOverride: temp),
    bridge: BridgeClient(baseUrl: 'http://x'),
    countdownDelay: countdownDelay,
    pollInterval: Duration.zero,
  );

  EventProfile event({
    String id = 'evt_1',
    int photoCount = 3,
    int countdown = 3,
    EventBranding branding = const EventBranding(),
  }) => EventProfile(
    id: id,
    title: 'Kate & Jack',
    date: '14 November 2026',
    dateIso: '2026-11-14',
    status: EventStatus.scheduled,
    configuration: EventConfiguration(
      photoCount: photoCount,
      countdownSeconds: countdown,
      templateId: BuiltinTemplates.forPhotoCount(photoCount).id,
      templateVersion: 1,
      branding: branding,
    ),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test(
    'capture count 1, 2, 3 and 4 drives review and template slots',
    () async {
      for (final count in [1, 2, 3, 4]) {
        final temp = await Directory.systemTemp.createTemp('tb_4b_count_');
        addTearDown(() => temp.delete(recursive: true));
        final controller = controllerFor(temp);
        addTearDown(controller.dispose);
        await controller.createEventProfile(event(photoCount: count));
        await controller.startSession();
        expect(controller.phase, BoothPhase.review, reason: 'count $count');
        expect(controller.photos, hasLength(count));
        expect(controller.expectedPhotoCount, count);
        expect(controller.sessionTemplate!.slots, hasLength(count));
        final records = await controller.storage.readSessionsForEvent('evt_1');
        expect(records.single.photoCount, count);
        expect(records.single.expectedPhotoCount, count);
      }
    },
  );

  test('countdown Off captures without a countdown', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_no_countdown_');
    addTearDown(() => temp.delete(recursive: true));
    final camera = TestCamera(bytes: jpeg);
    final controller = controllerFor(temp, camera: camera);
    addTearDown(controller.dispose);
    await controller.createEventProfile(event(photoCount: 1, countdown: 0));
    await controller.startSession();
    expect(controller.phase, BoothPhase.review);
    expect(controller.countdownActive, isFalse);
    expect(camera.captureIds, hasLength(1));
  });

  test('countdown 3, 5 and 10 are carried into the session', () async {
    for (final seconds in [3, 5, 10]) {
      final temp = await Directory.systemTemp.createTemp('tb_4b_countdown_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);
      await controller.createEventProfile(
        event(photoCount: 1, countdown: seconds),
      );
      await controller.startSession();
      expect(controller.phase, BoothPhase.review);
      expect(controller.sessionCountdownSeconds, seconds);
    }
  });

  test('countdown can be cancelled before a capture', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_cancel_');
    addTearDown(() => temp.delete(recursive: true));
    final camera = TestCamera(bytes: jpeg);
    final controller = controllerFor(
      temp,
      camera: camera,
      countdownDelay: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await controller.createEventProfile(event(photoCount: 1, countdown: 10));
    final future = controller.startSession();
    for (var i = 0; i < 50 && !controller.countdownActive; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(controller.countdownActive, isTrue);
    await controller.cancelCountdown();
    await future;
    expect(controller.phase, BoothPhase.idle);
    expect(camera.captureIds, isEmpty);
    final records = await controller.storage.readSessionsForEvent('evt_1');
    expect(records.single.status, BoothSessionStatus.interrupted);
  });

  test('retake-all respects a two-photo session', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_retake_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    await controller.createEventProfile(event(photoCount: 2));
    await controller.startSession();
    final firstSession = controller.sessionId;
    await controller.retakeAll();
    expect(controller.phase, BoothPhase.review);
    expect(controller.photos, hasLength(2));
    expect(controller.sessionId, isNot(firstSession));
  });

  test('session stores its own configuration snapshot', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_snapshot_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    final created = await controller.createEventProfile(
      event(photoCount: 4, countdown: 5),
    );
    await controller.startSession();
    final records = await controller.storage.readSessionsForEvent(created.id);
    expect(records.single.expectedPhotoCount, 4);
    expect(records.single.countdownSeconds, 5);

    await controller.updateEvent(
      created.copyWith(
        configuration: created.configuration.copyWith(
          photoCount: 1,
          countdownSeconds: 0,
        ),
      ),
    );
    expect(controller.sessionPhotoCount, 4);
    expect(controller.sessionCountdownSeconds, 5);
  });

  test('branding and logo persist with the event', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_brand_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    final created = await controller.createEventProfile(event());
    final logoPath = await controller.storage.saveBrandingLogo(
      created.id,
      jpeg,
      'jpg',
    );
    final branding = EventBranding(
      enabled: true,
      title: 'Acme Events',
      tagline: 'Make it memorable',
      colorHex: '#123ABC',
      placement: BrandingPlacement.top,
      logoPath: logoPath,
    );
    branding.validate();
    await controller.updateEvent(
      created.copyWith(
        configuration: created.configuration.copyWith(branding: branding),
      ),
    );

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    final saved = restarted.currentEvent.configuration.branding;
    expect(saved.enabled, isTrue);
    expect(saved.title, 'Acme Events');
    expect(saved.logoPath, logoPath);
    expect(await restarted.storage.readBrandingLogo(logoPath), isNotNull);
  });

  test(
    'session keeps branding snapshot after event branding changes',
    () async {
      final temp = await Directory.systemTemp.createTemp('tb_4b_brand_snap_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);
      final branding = const EventBranding(
        enabled: true,
        title: 'Original Brand',
        tagline: 'Keep this',
        colorHex: '#112233',
      );
      final created = await controller.createEventProfile(
        event(photoCount: 1, branding: branding),
      );
      await controller.startSession();
      expect(controller.sessionBranding.title, 'Original Brand');
      await controller.updateEvent(
        created.copyWith(
          configuration: created.configuration.copyWith(
            branding: branding.copyWith(title: 'Changed Later'),
          ),
        ),
      );
      expect(controller.sessionBranding.title, 'Original Brand');
    },
  );

  test('report remains accurate after application restart', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_report_restart_');
    addTearDown(() => temp.delete(recursive: true));
    final first = controllerFor(temp);
    addTearDown(first.dispose);
    final created = await first.createEventProfile(event(photoCount: 2));
    final start = DateTime.utc(2026, 11, 14, 20);
    await first.storage.writeSessionMetadata(
      eventId: created.id,
      sessionId: 'ses_report',
      data: {
        'event_id': created.id,
        'session_id': 'ses_report',
        'status': BoothSessionStatus.approved,
        'approved': true,
        'started_at': start.toIso8601String(),
        'ended_at': start.add(const Duration(minutes: 3)).toIso8601String(),
        'photo_count': 2,
        'photo_count_expected': 2,
        'captures': [],
      },
    );

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    final sessions = await restarted.storage.readSessionsForEvent(created.id);
    final report = EventReport(event: created, sessions: sessions);
    expect(report.totalPhotos, 2);
    expect(report.approvedPhotos, 2);
    expect(report.totalDuration.inMinutes, 3);
    expect(report.toCsv(), contains('ses_report'));
  });

  test('partial interrupted session resumes only remaining photos', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_resume_');
    addTearDown(() => temp.delete(recursive: true));
    final first = controllerFor(temp);
    addTearDown(first.dispose);
    final created = await first.createEventProfile(event(photoCount: 3));
    final original = File('${temp.path}/slot1.jpg');
    await original.writeAsBytes(jpeg);
    await first.storage.writeSessionMetadata(
      eventId: created.id,
      sessionId: 'ses_partial',
      data: {
        'event_id': created.id,
        'session_id': 'ses_partial',
        'status': BoothSessionStatus.active,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'photo_count_expected': 3,
        'countdown_seconds': 3,
        'template': 'strip_2x6_3up_v1',
        'template_version': 1,
        'captures': [
          {
            'slot': 1,
            'id': 'cap_existing',
            'capture_id': 'cap_existing',
            'path': original.path,
            'width': 1200,
            'height': 1800,
            'captured_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      },
    );

    final camera = TestCamera(bytes: jpeg);
    final restarted = controllerFor(temp, camera: camera);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    expect(restarted.interruptedRecovery?.canResume, isTrue);
    expect(restarted.interruptedRecovery?.remaining, 2);
    await restarted.resumeInterruptedSession();
    expect(restarted.phase, BoothPhase.review);
    expect(restarted.photos, hasLength(3));
    expect(restarted.photos.first.captureId, 'cap_existing');
    expect(camera.captureIds, hasLength(2));
    expect(camera.captureIds, isNot(contains('cap_existing')));
  });

  test('missing original disables resume and close marks recovered', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_missing_');
    addTearDown(() => temp.delete(recursive: true));
    final first = controllerFor(temp);
    addTearDown(first.dispose);
    final created = await first.createEventProfile(event(photoCount: 2));
    await first.storage.writeSessionMetadata(
      eventId: created.id,
      sessionId: 'ses_missing',
      data: {
        'event_id': created.id,
        'session_id': 'ses_missing',
        'status': BoothSessionStatus.active,
        'photo_count_expected': 2,
        'captures': [
          {
            'slot': 1,
            'id': 'missing',
            'path': '${temp.path}/does-not-exist.jpg',
            'captured_at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      },
    );

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    expect(restarted.interruptedRecovery?.canResume, isFalse);
    expect(await restarted.resumeInterruptedSession(), isFalse);
    await restarted.closeInterruptedSession();
    expect(restarted.interruptedSession, isNull);
    final records = await restarted.storage.readSessionsForEvent(created.id);
    expect(records.single.status, BoothSessionStatus.recovered);
  });

  test(
    'branding rejects invalid colour and empty event report is explicit',
    () {
      expect(
        () => const EventBranding(colorHex: 'gold').validate(),
        throwsA(
          isA<EventValidationException>().having(
            (e) => e.code,
            'code',
            'BRANDING_COLOR_INVALID',
          ),
        ),
      );
      final report = EventReport(event: event(), sessions: const []);
      expect(report.totalPhotos, 0);
      expect(report.summary, contains('0 sessions'));
      expect(report.toCsv(), contains('session_id'));
    },
  );

  test('event report CSV contains accurate summary and persists', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4b_csv_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    final created = await controller.createEventProfile(event(photoCount: 2));
    final start = DateTime.utc(2026, 11, 14, 18);
    final records = [
      BoothSessionRecord(
        eventId: created.id,
        sessionId: 'ses_approved',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 2)),
        status: BoothSessionStatus.approved,
        photoCount: 2,
        expectedPhotoCount: 2,
        approved: true,
      ),
      BoothSessionRecord(
        eventId: created.id,
        sessionId: 'ses_interrupted',
        startedAt: start.add(const Duration(minutes: 5)),
        endedAt: start.add(const Duration(minutes: 6)),
        status: BoothSessionStatus.interrupted,
        photoCount: 1,
        expectedPhotoCount: 2,
      ),
    ];
    final report = EventReport(event: created, sessions: records);
    expect(report.totalPhotos, 3);
    expect(report.approvedPhotos, 2);
    expect(report.approvedSessions, 1);
    expect(report.totalDuration.inSeconds, 180);
    final csv = report.toCsv();
    expect(csv, contains('Kate & Jack'));
    expect(csv, contains('ses_approved'));
    expect(csv, contains('"yes"'));
    expect(csv, contains('"no"'));

    final path = await controller.storage.exportEventReportCsv(report);
    expect(await File(path).readAsString(), csv);
  });
}
