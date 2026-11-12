import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/screens/capture_screen.dart';
import 'package:terabooth_ipad/screens/events_screen.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/storage_service.dart';
import 'package:terabooth_ipad/templates/builtin_templates.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  BoothController controllerFor(Directory temp) => BoothController(
    camera: TestCamera(bytes: jpeg),
    storage: StorageService(rootOverride: temp),
    bridge: BridgeClient(baseUrl: 'http://x'),
    countdownDelay: Duration.zero,
    pollInterval: Duration.zero,
  );

  EventProfile event({
    String id = 'evt_1',
    String title = 'Kate & Jack',
    EventStatus status = EventStatus.scheduled,
    String start = '18:00',
    String end = '22:00',
  }) => EventProfile(
    id: id,
    title: title,
    date: '14 November 2026',
    dateIso: '2026-11-14',
    startTime: start,
    endTime: end,
    status: status,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('event validation requires a name and ordered times', () {
    expect(
      () => event(title: '  ').validate(),
      throwsA(
        isA<EventValidationException>().having(
          (e) => e.code,
          'code',
          'EVENT_NAME_REQUIRED',
        ),
      ),
    );
    expect(
      () => event(start: '22:00', end: '18:00').validate(),
      throwsA(
        isA<EventValidationException>().having(
          (e) => e.code,
          'code',
          'EVENT_TIME_ORDER',
        ),
      ),
    );
    expect(event(start: '18:00', end: '22:00').validate, returnsNormally);
  });

  test('event status transitions are explicit and archived is terminal', () {
    expect(EventStatus.draft.canTransitionTo(EventStatus.scheduled), isTrue);
    expect(EventStatus.draft.canTransitionTo(EventStatus.active), isFalse);
    expect(EventStatus.scheduled.canTransitionTo(EventStatus.active), isTrue);
    expect(EventStatus.active.canTransitionTo(EventStatus.completed), isTrue);
    expect(EventStatus.completed.canTransitionTo(EventStatus.archived), isTrue);
    expect(
      EventStatus.archived.canTransitionTo(EventStatus.scheduled),
      isFalse,
    );
  });

  test(
    'event creation, editing and persistence keep sessions intact',
    () async {
      final temp = await Directory.systemTemp.createTemp('tb_4a_event_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);

      final created = await controller.createEventProfile(event());
      expect(controller.eventId, created.id);
      expect(controller.currentEvent.status, EventStatus.scheduled);

      await controller.storage.writeSessionMetadata(
        eventId: created.id,
        sessionId: 'ses_existing',
        data: {'event_id': created.id, 'status': 'completed', 'captures': []},
      );

      final edited = await controller.updateEvent(
        created.copyWith(title: 'Renamed', client: 'Acme'),
      );
      expect(edited.title, 'Renamed');
      expect(controller.eventTitle, 'Renamed');
      expect(await controller.storage.hasSessions(created.id), isTrue);

      final restored = controllerFor(temp);
      addTearDown(restored.dispose);
      await restored.loadEvents();
      expect(restored.eventTitle, 'Renamed');
      expect(restored.events.single.client, 'Acme');
    },
  );

  test('selected event survives restart independently of sort order', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_select_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);

    final first = await controller.createEventProfile(event(id: 'evt_first'));
    await controller.createEventProfile(
      event(id: 'evt_second', title: 'Later Event'),
    );
    await controller.selectEvent(first);

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    expect(restarted.eventId, first.id);
    expect(restarted.events, hasLength(2));
  });

  test(
    'welcome configuration persists per event and remains isolated',
    () async {
      final temp = await Directory.systemTemp.createTemp('tb_8a_welcome_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);

      final one = event(id: 'evt_w1', title: 'One');
      final two = event(id: 'evt_w2', title: 'Two');
      final createdOne = await controller.createEventProfile(one);
      final createdTwo = await controller.createEventProfile(two);
      await controller.updateEvent(
        createdOne.copyWith(
          configuration: createdOne.configuration.copyWith(
            welcome: const EventWelcomeConfig(
              title: 'Wedding of One',
              subtitle: 'Welcome one',
              buttonLabel: 'Start One',
              backgroundHex: '#112233',
            ),
          ),
        ),
      );
      await controller.updateEvent(
        createdTwo.copyWith(
          configuration: createdTwo.configuration.copyWith(
            welcome: const EventWelcomeConfig(
              title: 'Wedding of Two',
              subtitle: 'Welcome two',
              buttonLabel: 'Start Two',
              backgroundHex: '#445566',
            ),
          ),
        ),
      );

      final restarted = controllerFor(temp);
      addTearDown(restarted.dispose);
      await restarted.loadEvents();
      final byId = {
        for (final e in restarted.events) e.id: e.configuration.welcome,
      };
      expect(byId['evt_w1']?.buttonLabel, 'Start One');
      expect(byId['evt_w2']?.buttonLabel, 'Start Two');
      expect(byId['evt_w1']?.backgroundHex, '#112233');
      expect(byId['evt_w2']?.backgroundHex, '#445566');
    },
  );

  test('custom Canva layout persists per event', () async {
    final temp = await Directory.systemTemp.createTemp('tb_8a_layout_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    final created = await controller.createEventProfile(event());
    final updated = created.copyWith(
      configuration: created.configuration.copyWith(
        customTemplate: const EventCustomTemplate(
          artworkPath: '/tmp/canva.png',
          artworkWidth: 1200,
          artworkHeight: 1800,
          layerMode: TemplateLayerMode.background,
          slots: [
            CustomPhotoSlot(
              id: 'a',
              captureOrder: 0,
              x: .1,
              y: .1,
              width: .8,
              height: .3,
            ),
            CustomPhotoSlot(
              id: 'b',
              captureOrder: 1,
              x: .1,
              y: .5,
              width: .8,
              height: .3,
              contain: true,
              zoom: 1.4,
            ),
          ],
        ),
      ),
    );
    await controller.updateEvent(updated);
    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    final design = restarted.currentEvent.configuration.customTemplate!;
    expect(design.artworkPath, '/tmp/canva.png');
    expect(design.layerMode, TemplateLayerMode.background);
    expect(design.slots, hasLength(2));
    expect(design.slots[1].contain, isTrue);
    expect(design.slots[1].zoom, 1.4);
  });

  test('booth layout choice persists as event configuration', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_config_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);

    await controller.createEventProfile(event());
    await controller.selectTemplate(BuiltinTemplates.collage);
    expect(controller.currentEvent.configuration.templateId, 'collage_4x6_v1');

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    expect(restarted.currentEvent.configuration.templateId, 'collage_4x6_v1');
    expect(restarted.template.id, 'collage_4x6_v1');
  });

  test('draft can be deleted only when it has no sessions', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_delete_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);

    final draft = await controller.createEventProfile(
      event(id: 'evt_draft', status: EventStatus.draft),
    );
    await controller.deleteDraftEvent(draft.id);
    expect(controller.events, isEmpty);
    expect(controller.hasSelectedEvent, isFalse);

    final scheduled = await controller.createEventProfile(event(id: 'evt_s'));
    expect(
      () => controller.deleteDraftEvent(scheduled.id),
      throwsA(isA<EventValidationException>()),
    );
  });

  test('archiving preserves sessions and blocks new booth sessions', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_archive_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);

    final created = await controller.createEventProfile(event());
    await controller.storage.writeSessionMetadata(
      eventId: created.id,
      sessionId: 'ses_keep',
      data: {'event_id': created.id, 'status': 'completed', 'captures': []},
    );
    await controller.archiveEvent(created.id);
    expect(controller.currentEvent.status, EventStatus.archived);
    expect(await controller.storage.hasSessions(created.id), isTrue);

    await controller.startSession();
    expect(controller.phase, BoothPhase.idle);
    expect(controller.error, contains('archived'));
  });

  test('duplicate event identifiers are rejected', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_dupe_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp);
    addTearDown(controller.dispose);
    await controller.createEventProfile(event());
    expect(
      () => controller.createEventProfile(event(title: 'Duplicate')),
      throwsA(
        isA<EventValidationException>().having(
          (e) => e.code,
          'code',
          'EVENT_DUPLICATE',
        ),
      ),
    );
  });

  test(
    'starting a scheduled event activates it and persists an active session',
    () async {
      final temp = await Directory.systemTemp.createTemp('tb_4a_start_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);

      final created = await controller.createEventProfile(event());
      await controller.startSession();
      expect(controller.phase, BoothPhase.review);
      expect(controller.currentEvent.status, EventStatus.active);
      expect(controller.sessionStartedAt, isNotNull);
      expect(controller.sessionId, isNotNull);

      final records = await controller.storage.readSessionsForEvent(created.id);
      expect(records, hasLength(1));
      expect(records.single.status, BoothSessionStatus.active);
      expect(records.single.photoCount, 3);
    },
  );

  test(
    'ending a review session marks it interrupted and preserves history',
    () async {
      final temp = await Directory.systemTemp.createTemp('tb_4a_end_');
      addTearDown(() => temp.delete(recursive: true));
      final controller = controllerFor(temp);
      addTearDown(controller.dispose);

      final created = await controller.createEventProfile(event());
      await controller.startSession();
      final sessionId = controller.sessionId;
      await controller.endSession();

      expect(controller.phase, BoothPhase.idle);
      expect(controller.sessionId, isNull);
      final records = await controller.storage.readSessionsForEvent(created.id);
      expect(records.single.sessionId, sessionId);
      expect(records.single.status, BoothSessionStatus.interrupted);
      expect(records.single.photoCount, 3);
    },
  );

  test('incomplete active session is marked interrupted on reload', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_recover_');
    addTearDown(() => temp.delete(recursive: true));
    final first = controllerFor(temp);
    addTearDown(first.dispose);

    final created = await first.createEventProfile(event());
    await first.storage.writeSessionMetadata(
      eventId: created.id,
      sessionId: 'ses_partial',
      data: {
        'event_id': created.id,
        'session_id': 'ses_partial',
        'status': BoothSessionStatus.active,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'captures': [],
      },
    );

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    expect(restarted.interruptedSession, isNotNull);
    expect(restarted.interruptedSession!.sessionId, 'ses_partial');
    final records = await restarted.storage.readSessionsForEvent(created.id);
    expect(records.single.status, BoothSessionStatus.interrupted);
  });

  test('complete unapproved session is restorable after restart', () async {
    final temp = await Directory.systemTemp.createTemp('tb_4a_restore_');
    addTearDown(() => temp.delete(recursive: true));
    final first = controllerFor(temp);
    addTearDown(first.dispose);

    final created = await first.createEventProfile(event());
    await first.startSession();
    expect(first.phase, BoothPhase.review);
    await first.storage.writeSessionMetadata(
      eventId: created.id,
      sessionId: first.sessionId!,
      data: {
        'event_id': created.id,
        'session_id': first.sessionId!,
        'status': BoothSessionStatus.active,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'captures': [
          for (final photo in first.photos)
            {
              'id': photo.id,
              'path': photo.path,
              'width': photo.width,
              'height': photo.height,
              'captured_at': photo.capturedAt.toIso8601String(),
            },
        ],
      },
    );

    final restarted = controllerFor(temp);
    addTearDown(restarted.dispose);
    await restarted.loadEvents();
    expect(restarted.restorableSession, isNotNull);
    await restarted.restorePreviousSession();
    expect(restarted.phase, BoothPhase.review);
    expect(restarted.photos, hasLength(3));
  });

  testWidgets('active session shows elapsed clock and end confirmation', (
    tester,
  ) async {
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: Directory('/tmp')),
      bridge: BridgeClient(baseUrl: 'http://x'),
      countdownDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.sessionStartedAt = DateTime.now().subtract(
      const Duration(seconds: 5),
    );
    controller.sessionStatus = 'active';

    await tester.pumpWidget(
      MaterialApp(home: CaptureScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('End session'), findsOneWidget);

    await tester.ensureVisible(find.text('End session'));
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(find.text('End this session?'), findsOneWidget);
  });

  testWidgets('event list supports search, filtering and status labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: Directory('/tmp')),
      bridge: BridgeClient(baseUrl: 'http://x'),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.events = [
      event(id: 'evt_a', title: 'Autumn Gala', status: EventStatus.active),
      event(id: 'evt_b', title: 'Spring Fair', status: EventStatus.draft),
    ];
    controller.hasSelectedEvent = true;

    await tester.pumpWidget(
      MaterialApp(home: EventsScreen(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Autumn Gala'), findsOneWidget);
    expect(find.text('Spring Fair'), findsOneWidget);
    expect(find.text('Active'), findsWidgets);
    expect(find.text('Draft'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Autumn');
    await tester.pump();
    expect(find.text('Autumn Gala'), findsOneWidget);
    expect(find.text('Spring Fair'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Draft'));
    await tester.pump();
    expect(find.text('Spring Fair'), findsOneWidget);
    expect(find.text('Autumn Gala'), findsNothing);
  });
}
