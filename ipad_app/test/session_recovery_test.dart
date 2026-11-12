import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Uint8List jpeg;

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('terabooth_recovery_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  BoothController controller() => BoothController(
    camera: TestCamera(bytes: jpeg),
    storage: StorageService(rootOverride: temp),
    bridge: BridgeClient(baseUrl: 'http://x'),
    countdownDelay: Duration.zero,
    pollInterval: Duration.zero,
  );

  test('complete unsubmitted review can be restored explicitly', () async {
    final first = controller();
    await first.startSession();
    final originalBytes = List<int>.from(first.photos.first.bytes);
    expect(first.phase, BoothPhase.review);
    first.dispose();

    final second = controller();
    addTearDown(second.dispose);
    await second.loadRestorableSession();
    expect(second.restorableSession, isNotNull);
    expect(second.restorableSession!.photos, hasLength(3));
    await second.restorePreviousSession();
    expect(second.phase, BoothPhase.review);
    expect(second.photos, hasLength(3));
    expect(second.crops, hasLength(3));
    expect(second.photos.first.bytes, equals(originalBytes));
  });

  test('approved session is not offered as an unsubmitted review', () async {
    final first = controller();
    await first.startSession();
    first.dispose();
    final metadata = await _sessionJson(temp);
    final decoded =
        jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
    decoded['approved'] = true;
    decoded['job_id'] = 'job_completed';
    await metadata.writeAsString(jsonEncode(decoded));

    final second = controller();
    addTearDown(second.dispose);
    await second.loadRestorableSession();
    expect(second.restorableSession, isNull);
  });
}

Future<File> _sessionJson(Directory root) async {
  await for (final entity in root.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('session.json')) return entity;
  }
  throw StateError('session.json not found');
}
