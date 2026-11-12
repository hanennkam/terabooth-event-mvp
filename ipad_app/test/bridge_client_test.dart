import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/templates/template_models.dart';

void main() {
  test('submit sends idempotency and parses job', () async {
    late http.BaseRequest seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({
          'job_id': 'job_1',
          'state': 'queued',
          'completion': 'unknown',
          'attempts': 0,
          'delivery_url': 'http://192.168.8.50:8787/d/token',
        }),
        202,
      );
    });
    final bridge = BridgeClient(
      baseUrl: 'http://192.168.8.50:8787',
      client: client,
    );
    final images = List.generate(
      3,
      (i) => CapturedImage(
        id: 'img_$i',
        bytes: Uint8List.fromList([i, i + 1]),
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
      ),
    );
    final job = await bridge.submit(
      eventId: 'evt',
      sessionId: 'ses',
      title: 'Kate',
      date: '14 Nov',
      images: images,
    );
    expect(job.id, 'job_1');
    expect(job.deliveryUrl, contains('/d/token'));
    expect(seen.headers.containsKey('Idempotency-Key'), isTrue);
    expect(seen.headers['Idempotency-Key'], isNotEmpty);
  });

  test('parses terminal states', () {
    final job = PrintJob.fromJson({
      'job_id': 'j',
      'state': 'unknown',
      'completion': 'unknown',
      'attempts': 2,
    });
    expect(job.isTerminal, isTrue);
  });

  test('artefact returns composition bytes', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/print-jobs/job_1/artefact');
      return http.Response.bytes([0xFF, 0xD8, 0xFF, 0xD9], 200);
    });
    final bridge = BridgeClient(baseUrl: 'http://x', client: client);
    final bytes = await bridge.artefact('job_1');
    expect(bytes, [0xFF, 0xD8, 0xFF, 0xD9]);
  });

  test('artefact not ready is a typed error', () async {
    final bridge = BridgeClient(
      baseUrl: 'http://x',
      client: MockClient((request) async => http.Response('not ready', 404)),
    );
    await expectLater(
      bridge.artefact('job_1'),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          'ARTEFACT_NOT_READY',
        ),
      ),
    );
  });

  test('submit timeout is reported without retry', () async {
    final bridge = BridgeClient(
      baseUrl: 'http://x',
      submitTimeout: const Duration(milliseconds: 30),
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('late', 202);
      }),
    );
    final images = List.generate(
      3,
      (i) => CapturedImage(
        id: 'img_$i',
        bytes: Uint8List.fromList([i, i + 1]),
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
      ),
    );
    await expectLater(
      bridge.submit(
        eventId: 'evt',
        sessionId: 'ses',
        title: 'T',
        date: 'D',
        images: images,
      ),
      throwsA(
        isA<BridgeException>().having((e) => e.code, 'code', 'SUBMIT_TIMEOUT'),
      ),
    );
  });

  test('connection failure is reported', () async {
    final bridge = BridgeClient(
      baseUrl: 'http://x',
      client: MockClient((request) async {
        throw http.ClientException('bridge offline');
      }),
    );
    final images = List.generate(
      3,
      (i) => CapturedImage(
        id: 'img_$i',
        bytes: Uint8List.fromList([i, i + 1]),
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
      ),
    );
    await expectLater(
      bridge.submit(
        eventId: 'evt',
        sessionId: 'ses',
        title: 'T',
        date: 'D',
        images: images,
      ),
      throwsA(
        isA<BridgeException>().having((e) => e.code, 'code', 'SUBMIT_FAILED'),
      ),
    );
  });

  test('gif fetch returns bytes', () async {
    final bridge = BridgeClient(
      baseUrl: 'http://x',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/print-jobs/job_1/gif');
        return http.Response.bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61], 200);
      }),
    );
    final bytes = await bridge.gif('job_1');
    expect(bytes.take(6), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
  });

  test('gif pending and unavailable are controlled errors', () async {
    final pending = BridgeClient(
      baseUrl: 'http://x',
      client: MockClient((request) async => http.Response('pending', 409)),
    );
    await expectLater(
      pending.gif('job_1'),
      throwsA(
        isA<BridgeException>().having((e) => e.code, 'code', 'GIF_NOT_READY'),
      ),
    );
    final unavailable = BridgeClient(
      baseUrl: 'http://x',
      client: MockClient((request) async => http.Response('unavailable', 404)),
    );
    await expectLater(
      unavailable.gif('job_1'),
      throwsA(
        isA<BridgeException>().having((e) => e.code, 'code', 'GIF_UNAVAILABLE'),
      ),
    );
  });

  test('precomposed template accepts composed plus originals', () async {
    final client = MockClient((request) async {
      final body = request.body;
      expect(body, contains('precomposed_4x6_v1'));
      return http.Response(
        jsonEncode({
          'job_id': 'pre',
          'state': 'completed',
          'completion': 'confirmed',
          'attempts': 1,
          'printer_mode': 'mock',
        }),
        202,
      );
    });
    final images = List.generate(
      4,
      (i) => CapturedImage(
        id: 'img_$i',
        bytes: Uint8List.fromList([i]),
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
      ),
    );
    final job = await BridgeClient(baseUrl: 'http://x', client: client).submit(
      eventId: 'evt',
      sessionId: 'ses',
      title: 'T',
      date: 'D',
      images: images,
      template: const PhotoTemplate(
        id: 'precomposed_4x6_v1',
        name: 'Precomposed',
        description: '',
        version: 1,
        canvasWidth: 1200,
        canvasHeight: 1800,
        outputWidth: 1200,
        outputHeight: 1800,
        dpi: 300,
        slots: [
          TemplateSlot(
            id: 'photo_1',
            imageIndex: 0,
            x: 0,
            y: 0,
            width: 1200,
            height: 1800,
          ),
        ],
      ),
    );
    expect(job.id, 'pre');
  });
}
