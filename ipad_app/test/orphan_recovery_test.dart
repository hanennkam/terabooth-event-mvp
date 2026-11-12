import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

void main() {
  late Directory temp;
  late StorageService storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('terabooth_orphans_');
    storage = StorageService(rootOverride: temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> save(String captureId, {int slot = 1}) {
    return storage.saveOriginal(
      eventId: 'evt',
      sessionId: 'ses',
      index: slot,
      captureId: captureId,
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
    );
  }

  Future<void> reference(String path) {
    return storage.writeSessionMetadata(
      eventId: 'evt',
      sessionId: 'ses',
      data: {
        'captures': [
          {'path': path, 'capture_id': 'cap'},
        ],
      },
    );
  }

  Future<List<Map<String, dynamic>>> readOrphans() async {
    final file = File('${temp.path}/events/evt/sessions/ses/orphans.json');
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (decoded['orphans'] as List).cast<Map<String, dynamic>>();
  }

  test('complete orphan is recorded without assigning a slot', () async {
    final path = await save('cap_orphan');
    final records = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    expect(records, hasLength(1));
    expect(records.single.filename, path.split('/').last);
    expect(records.single.candidateCaptureId, 'cap_orphan');
    expect(records.single.candidateSlot, 1);
    expect(await File(path).exists(), isTrue);
    final json = await readOrphans();
    expect(json, hasLength(1));
    expect(json.single['assigned_to_session'], isFalse);
  });

  test('incomplete temporary file is removed and never recorded as an orphan', () async {
    await save('cap_real');
    final dir = Directory('${temp.path}/events/evt/sessions/ses');
    final partial = File('${dir.path}/.terabooth-tmp-123-cap_x.part');
    await partial.writeAsBytes([0xFF, 0xD8, 0xFF]);
    expect(await storage.recoverIncompleteWrites(eventId: 'evt', sessionId: 'ses'), 1);
    expect(await partial.exists(), isFalse);
    final records = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    expect(records.map((r) => r.filename), isNot(contains(partial.path.split('/').last)));
  });

  test('referenced original is not an orphan', () async {
    final path = await save('cap_ref');
    await reference(path);
    final records = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    expect(records, isEmpty);
    expect(await readOrphans(), isEmpty);
  });

  test('repeated recovery is idempotent and preserves the original', () async {
    final path = await save('cap_repeat');
    final first = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    final second = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(await readOrphans(), hasLength(1));
    expect(await File(path).exists(), isTrue);
  });

  test('duplicate capture ID does not create duplicate session references', () async {
    final first = await save('cap_same');
    final second = await save('cap_same');
    await reference(first);
    final records = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    expect(records.map((r) => r.filename), contains(second.split('/').last));
    expect(await File(first).exists(), isTrue);
    expect(await File(second).exists(), isTrue);
    final metadata = jsonDecode(
      await File('${temp.path}/events/evt/sessions/ses/session.json').readAsString(),
    ) as Map<String, dynamic>;
    expect((metadata['captures'] as List), hasLength(1));
    expect(await readOrphans(), hasLength(1));
  });

  test('simulated interruption leaves a complete orphan for inspection', () async {
    final path = await save('cap_interrupted');
    // Simulate termination after the image write but before metadata update.
    final records = await storage.recoverOrphans(eventId: 'evt', sessionId: 'ses');
    expect(records.single.path, path);
    expect(await File(path).exists(), isTrue);
    expect(await readOrphans(), hasLength(1));
  });
}
