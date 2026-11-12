import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/screens/print_screen.dart';
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

  test('GIF is fetched independently after print completion', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_gif_');
    addTearDown(() => temp.delete(recursive: true));
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

  testWidgets(
    'print screen shows delivery URL, copy action and composition action',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1366);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BoothController(
        camera: TestCamera(bytes: jpeg),
        storage: StorageService(rootOverride: Directory('/tmp')),
        bridge: BridgeClient(
          baseUrl: 'http://x',
          client: bridgeMock(posts: []),
        ),
        countdownDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.phase = BoothPhase.done;
      controller.job = const PrintJob(
        id: 'job_1',
        state: 'completed',
        completion: 'confirmed',
        attempts: 1,
        gifState: 'ready',
        deliveryUrl: 'http://192.168.8.50:8787/d/token',
      );
      controller.compositionBytes = jpeg;
      controller.gifBytes = gifFixture;

      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PrintScreen(controller: controller)),
        ),
      );
      await tester.pump();
      expect(find.text('http://192.168.8.50:8787/d/token'), findsOneWidget);
      expect(find.byTooltip('Copy delivery link'), findsOneWidget);
      expect(find.text('View final composition'), findsOneWidget);
      expect(find.text('View animated GIF'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Copy delivery link'));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy delivery link'));
      await tester.pump();
      expect(copied, 'http://192.168.8.50:8787/d/token');
    },
  );
}
