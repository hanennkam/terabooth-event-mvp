import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

void main() {
  test('originals use unique names, never overwrite, and are listed', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_storage_');
    addTearDown(() => temp.delete(recursive: true));
    final storage = StorageService(rootOverride: temp);
    final first = await storage.saveOriginal(
      eventId: 'evt',
      sessionId: 'ses',
      index: 1,
      captureId: 'cap_1',
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
    );
    final second = await storage.saveOriginal(
      eventId: 'evt',
      sessionId: 'ses',
      index: 1,
      captureId: 'cap_1',
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0xFF, 0xD9]),
    );
    expect(first, isNot(second));
    expect(first, contains('/events/evt/sessions/ses/original_1_cap_1.jpg'));
    expect(second, contains('__2.jpg'));
    expect(File(first).existsSync(), isTrue);
    expect(File(second).existsSync(), isTrue);
    expect(await storage.listOriginals('evt', 'ses'), hasLength(2));
    final sessionDir = Directory('${temp.path}/events/evt/sessions/ses');
    final leftovers = await sessionDir
        .list()
        .where((e) => e.path.split('/').last.startsWith('.terabooth-tmp-'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test(
    'recovery removes partial temp files but preserves completed originals',
    () async {
      final temp = await Directory.systemTemp.createTemp('terabooth_recovery_');
      addTearDown(() => temp.delete(recursive: true));
      final storage = StorageService(rootOverride: temp);
      final kept = await storage.saveOriginal(
        eventId: 'evt',
        sessionId: 'ses',
        index: 1,
        captureId: 'cap_kept',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      final dir = Directory('${temp.path}/events/evt/sessions/ses');
      final partial = File('${dir.path}/.terabooth-tmp-123-cap_x.part');
      await partial.writeAsBytes([1, 2]);
      final removed = await storage.recoverIncompleteWrites(
        eventId: 'evt',
        sessionId: 'ses',
      );
      expect(removed, 1);
      expect(await partial.exists(), isFalse);
      expect(await File(kept).exists(), isTrue);
    },
  );

  test('write failure is explicit', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_failure_');
    addTearDown(() => temp.delete(recursive: true));
    final blocker = File('${temp.path}/not-a-directory');
    await blocker.writeAsString('x');
    final storage = StorageService(rootOverride: Directory(blocker.path));
    await expectLater(
      storage.saveOriginal(
        eventId: 'evt',
        sessionId: 'ses',
        index: 1,
        captureId: 'cap',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<StorageException>()),
    );
  });
}
