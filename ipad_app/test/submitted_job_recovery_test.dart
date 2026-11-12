import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  Future<Directory> tempDir() =>
      Directory.systemTemp.createTemp('terabooth_submitted_');

  SubmittedJob record({
    String jobId = 'job_1',
    String eventId = 'evt_demo',
    DateTime? at,
    bool dismissed = false,
  }) => SubmittedJob(
    eventId: eventId,
    sessionId: 'ses_1',
    jobId: jobId,
    submittedAt: at ?? DateTime.utc(2026, 11, 10, 10),
    deliveryUrl: 'http://192.168.8.50:8787/d/token',
    dismissed: dismissed,
  );

  BoothController controller(Directory temp, http.Client client) =>
      BoothController(
        camera: TestCamera(bytes: jpeg),
        storage: StorageService(rootOverride: temp),
        bridge: BridgeClient(baseUrl: 'http://x', client: client),
        countdownDelay: Duration.zero,
        pollInterval: Duration.zero,
      );

  test(
    'submitted job metadata persists and latest non-dismissed wins',
    () async {
      final temp = await tempDir();
      addTearDown(() => temp.delete(recursive: true));
      final storage = StorageService(rootOverride: temp);
      await storage.writeSubmittedJob(
        record(jobId: 'old', at: DateTime.utc(2026, 11, 10, 9)),
      );
      await storage.writeSubmittedJob(
        record(jobId: 'new', at: DateTime.utc(2026, 11, 10, 11)),
      );
      await storage.writeSubmittedJob(
        record(
          jobId: 'dismissed',
          at: DateTime.utc(2026, 11, 10, 12),
          dismissed: true,
        ),
      );

      final latest = await storage.readLatestSubmittedJob(eventId: 'evt_demo');
      expect(latest?.jobId, 'new');
    },
  );

  test('restart reconciles submitted job with GET only', () async {
    final temp = await tempDir();
    addTearDown(() => temp.delete(recursive: true));
    final storage = StorageService(rootOverride: temp);
    await storage.writeSubmittedJob(record());
    var getCount = 0;
    var postCount = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        postCount++;
        return http.Response('unexpected', 500);
      }
      getCount++;
      if (request.url.path.endsWith('/artefact')) {
        return http.Response('not ready', 404);
      }
      return http.Response(
        jsonEncode({
          'job_id': 'job_1',
          'state': 'completed',
          'completion': 'confirmed',
          'attempts': 1,
          'printer_mode': 'mock',
          'gif_state': 'failed',
          'delivery_url': 'http://x/d/token',
        }),
        200,
      );
    });
    final c = controller(temp, client);
    addTearDown(c.dispose);

    await c.loadSubmittedJob();
    expect(c.phase, BoothPhase.done);
    expect(c.job?.id, 'job_1');
    expect(c.job?.printerMode, 'mock');
    expect(c.submittedJob?.printState, 'completed');
    expect(c.submittedJobError, isNull);
    expect(getCount, greaterThan(0));
    expect(postCount, 0);
  });

  test(
    'offline reconciliation preserves local reference and blocks new session',
    () async {
      final temp = await tempDir();
      addTearDown(() => temp.delete(recursive: true));
      final storage = StorageService(rootOverride: temp);
      await storage.writeSubmittedJob(record());
      final client = MockClient((request) async {
        throw http.ClientException('bridge offline');
      });
      final c = controller(temp, client);
      addTearDown(c.dispose);

      await c.loadSubmittedJob();
      expect(c.phase, BoothPhase.idle);
      expect(c.submittedJob?.jobId, 'job_1');
      expect(c.submittedJobError, contains('offline'));
      await c.startSession();
      expect(c.phase, BoothPhase.idle);
      expect(c.error, contains('Resolve or dismiss'));
    },
  );

  test(
    'unknown restored status stays Needs attention and is not resubmitted',
    () async {
      final temp = await tempDir();
      addTearDown(() => temp.delete(recursive: true));
      await StorageService(rootOverride: temp).writeSubmittedJob(record());
      var postCount = 0;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          postCount++;
          return http.Response('unexpected', 500);
        }
        if (request.url.path.endsWith('/artefact')) {
          return http.Response('not ready', 404);
        }
        return http.Response(
          jsonEncode({
            'job_id': 'job_1',
            'state': 'unknown',
            'completion': 'unknown',
            'attempts': 1,
            'printer_mode': 'mock',
            'gif_state': 'failed',
            'delivery_url': 'http://x/d/token',
          }),
          200,
        );
      });
      final c = controller(temp, client);
      addTearDown(c.dispose);
      await c.loadSubmittedJob();
      expect(c.phase, BoothPhase.done);
      expect(c.job?.state, 'unknown');
      expect(postCount, 0);
    },
  );

  test('event isolation and dismissal', () async {
    final temp = await tempDir();
    addTearDown(() => temp.delete(recursive: true));
    final storage = StorageService(rootOverride: temp);
    await storage.writeSubmittedJob(
      record(eventId: 'evt_other', jobId: 'job_other'),
    );
    expect(await storage.readLatestSubmittedJob(eventId: 'evt_demo'), isNull);

    final c = controller(
      temp,
      MockClient((request) async => http.Response('not found', 404)),
    );
    addTearDown(c.dispose);
    c.submittedJob = record();
    await c.dismissSubmittedJob();
    expect(c.submittedJob, isNull);
  });
}
