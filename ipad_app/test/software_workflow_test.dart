import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  late Uint8List gifFixture;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
    gifFixture = await File('test/fixtures/animated.gif').readAsBytes();
  });

  MockClient bridgeMock({
    required List<String> posts,
    List<Map<String, dynamic>>? jobs,
    Uint8List? artefact,
    Uint8List? gif,
  }) {
    var getCount = 0;
    return MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/v1/print-jobs') {
        posts.add(path);
        return http.Response(
          jsonEncode({
            'job_id': 'job_1',
            'state': 'queued',
            'completion': 'unknown',
            'attempts': 0,
            'delivery_url': 'http://x/d/token',
          }),
          202,
        );
      }
      if (path.endsWith('/artefact')) {
        if (artefact == null) return http.Response('not ready', 404);
        return http.Response.bytes(artefact, 200);
      }
      if (path.endsWith('/gif')) {
        if (gif == null) return http.Response('not available', 404);
        return http.Response.bytes(gif, 200);
      }
      if (path.startsWith('/v1/print-jobs/')) {
        final sequence =
            jobs ??
            [
              {
                'job_id': 'job_1',
                'state': 'completed',
                'completion': 'confirmed',
                'attempts': 1,
                'delivery_url': 'http://x/d/token',
              },
            ];
        final index = getCount < sequence.length
            ? getCount
            : sequence.length - 1;
        getCount++;
        return http.Response(jsonEncode(sequence[index]), 200);
      }
      return http.Response('not found', 404);
    });
  }

  BoothController controllerFor(
    Directory temp,
    MockClient client, {
    Uint8List? bytes,
  }) {
    return BoothController(
      camera: TestCamera(bytes: bytes ?? jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x', client: client),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
  }

  test(
    'three-photo workflow retrieves bridge composition and QR URL',
    () async {
      final temp = await Directory.systemTemp.createTemp('terabooth_e2e_');
      addTearDown(() => temp.delete(recursive: true));
      final posts = <String>[];
      final controller = controllerFor(
        temp,
        bridgeMock(posts: posts, artefact: jpeg),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await controller.approve();

      expect(controller.phase, BoothPhase.done);
      expect(posts, hasLength(1));
      expect(controller.job?.state, 'completed');
      expect(controller.job?.deliveryUrl, 'http://x/d/token');
      expect(controller.compositionBytes, equals(jpeg));
      expect(controller.photos, hasLength(3));
    },
  );

  test('custom Canva layout composes locally and uploads originals', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_canva_');
    addTearDown(() => temp.delete(recursive: true));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 600, 900),
      ui.Paint()..color = const ui.Color(0x22C8A464),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(600, 900);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final artwork = File('${temp.path}/canva.png');
    await artwork.writeAsBytes(data!.buffer.asUint8List());
    final posts = <String>[];
    String? submittedBody;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/v1/print-jobs') {
        posts.add(request.url.path);
        submittedBody = latin1.decode(request.bodyBytes);
        return http.Response(
          jsonEncode({
            'job_id': 'job_custom',
            'state': 'queued',
            'completion': 'unknown',
            'attempts': 0,
            'delivery_url': 'http://x/d/custom',
          }),
          202,
        );
      }
      if (request.url.path.endsWith('/artefact')) {
        return http.Response.bytes(jpeg, 200);
      }
      if (request.url.path.startsWith('/v1/print-jobs/')) {
        return http.Response(
          jsonEncode({
            'job_id': 'job_custom',
            'state': 'completed',
            'completion': 'confirmed',
            'attempts': 1,
            'delivery_url': 'http://x/d/custom',
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final controller = controllerFor(temp, client);
    addTearDown(controller.dispose);
    final created = await controller.createEventProfile(
      EventProfile(
        id: 'evt_canva',
        title: 'Canva Event',
        date: '14 Nov',
        dateIso: '2026-11-14',
        startTime: '18:00',
        endTime: '22:00',
        status: EventStatus.scheduled,
      ),
    );
    await controller.updateEvent(
      created.copyWith(
        configuration: created.configuration.copyWith(
          customTemplate: EventCustomTemplate(
            artworkPath: artwork.path,
            artworkWidth: 600,
            artworkHeight: 900,
            slots: const [
              CustomPhotoSlot(
                id: 'a',
                captureOrder: 0,
                x: .1,
                y: .1,
                width: .8,
                height: .35,
              ),
              CustomPhotoSlot(
                id: 'b',
                captureOrder: 1,
                x: .1,
                y: .55,
                width: .8,
                height: .35,
                contain: true,
                zoom: 1.2,
              ),
            ],
          ),
        ),
      ),
    );
    await controller.startSession();
    await controller.approve();
    expect(controller.phase, BoothPhase.done, reason: controller.error);
    expect(posts, hasLength(1));
    expect(submittedBody, contains('precomposed_4x6_v1'));
    expect(controller.photos, hasLength(2));
    expect(controller.job?.deliveryUrl, 'http://x/d/custom');
  });

  test('GIF is fetched independently after print completion', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_gif_');
    addTearDown(() async {
      // A background GIF callback may finish after the test body; cleanup must
      // be idempotent rather than failing on an already-removed temp dir.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await temp.delete(recursive: true);
          break;
        } on PathNotFoundException {
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });
    final gif = gifFixture;
    final posts = <String>[];
    final controller = controllerFor(
      temp,
      bridgeMock(
        posts: posts,
        artefact: jpeg,
        gif: gif,
        jobs: [
          {
            'job_id': 'job_1',
            'state': 'completed',
            'completion': 'confirmed',
            'attempts': 1,
            'gif_state': 'ready',
            'delivery_url': 'http://x/d/token',
          },
        ],
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await controller.approve();
    for (var i = 0; i < 50 && controller.gifBytes == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(controller.phase, BoothPhase.done);
    expect(controller.gifError, isNull);
    expect(controller.gifBytes, isNotNull);
    expect(controller.gifBytes!.take(6), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
  });

  test('duplicate approval cannot submit twice', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_dupe_');
    addTearDown(() => temp.delete(recursive: true));
    final posts = <String>[];
    final controller = controllerFor(
      temp,
      bridgeMock(posts: posts, artefact: jpeg),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await controller.approve();
    await controller.approve();

    expect(posts, hasLength(1));
    expect(controller.phase, BoothPhase.done);
  });

  test('job status transitions are polled until terminal', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_status_');
    addTearDown(() => temp.delete(recursive: true));
    final posts = <String>[];
    final controller = controllerFor(
      temp,
      bridgeMock(
        posts: posts,
        artefact: jpeg,
        jobs: [
          {
            'job_id': 'job_1',
            'state': 'printing',
            'completion': 'unknown',
            'attempts': 1,
            'delivery_url': 'http://x/d/token',
          },
          {
            'job_id': 'job_1',
            'state': 'completed',
            'completion': 'confirmed',
            'attempts': 1,
            'delivery_url': 'http://x/d/token',
          },
        ],
      ),
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await controller.approve();
    expect(controller.phase, BoothPhase.done);
    expect(controller.job?.state, 'completed');
  });

  test(
    'unknown print state remains terminal without automatic resubmission',
    () async {
      final temp = await Directory.systemTemp.createTemp('terabooth_unknown_');
      addTearDown(() => temp.delete(recursive: true));
      final posts = <String>[];
      final controller = controllerFor(
        temp,
        bridgeMock(
          posts: posts,
          jobs: [
            {
              'job_id': 'job_1',
              'state': 'unknown',
              'completion': 'unknown',
              'attempts': 1,
              'delivery_url': 'http://x/d/token',
            },
          ],
        ),
      );
      addTearDown(controller.dispose);

      await controller.startSession();
      await controller.approve();
      expect(controller.phase, BoothPhase.done);
      expect(controller.job?.state, 'unknown');
      expect(posts, hasLength(1));
    },
  );

  test('submit connection failure produces an error, not success', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_down_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(
        baseUrl: 'http://x',
        client: MockClient((request) async {
          throw http.ClientException('bridge offline');
        }),
      ),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.startSession();
    await controller.approve();
    expect(controller.phase, BoothPhase.error);
    expect(controller.error, contains('offline'));
    expect(controller.compositionBytes, isNull);
  });

  test('event catalog persists and reloads the selected event', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_event_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = controllerFor(temp, bridgeMock(posts: []));
    addTearDown(controller.dispose);

    final created = await controller.createEvent('New Event', '15 Nov 2026');
    expect(controller.eventId, created.id);
    expect(controller.eventTitle, 'New Event');

    final restored = controllerFor(temp, bridgeMock(posts: []));
    addTearDown(restored.dispose);
    await restored.loadEvents();
    expect(restored.eventId, created.id);
    expect(restored.eventTitle, 'New Event');
    expect(restored.eventDate, '15 Nov 2026');
  });
}
