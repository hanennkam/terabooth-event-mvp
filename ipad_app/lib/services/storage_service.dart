import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../crop/crop_models.dart';
import 'event_report_service.dart';

class StorageException implements Exception {
  final String code;
  final String message;

  const StorageException(this.code, this.message);

  @override
  String toString() => 'StorageException($code): $message';
}

class OrphanRecord {
  final String filename;
  final String path;
  final int byteLength;
  final String? candidateCaptureId;
  final int? candidateSlot;
  final String detectedAt;

  const OrphanRecord({
    required this.filename,
    required this.path,
    required this.byteLength,
    this.candidateCaptureId,
    this.candidateSlot,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'path': path,
    'byte_length': byteLength,
    'candidate_capture_id': candidateCaptureId,
    'candidate_slot': candidateSlot,
    'assigned_to_session': false,
    'detected_at': detectedAt,
  };

  factory OrphanRecord.fromJson(Map<String, dynamic> json) => OrphanRecord(
    filename: json['filename'] as String,
    path: json['path'] as String,
    byteLength: (json['byte_length'] as num?)?.toInt() ?? 0,
    candidateCaptureId: json['candidate_capture_id'] as String?,
    candidateSlot: (json['candidate_slot'] as num?)?.toInt(),
    detectedAt: json['detected_at'] as String? ?? '',
  );
}

/// Local original-image storage.
///
/// Guarantees:
/// - event/session directory structure is preserved;
/// - filenames are unique and never overwrite an existing original;
/// - bytes are written to a temp file in the same directory, flushed, and
///   atomically renamed into place;
/// - a partially-written temp file is never returned to the UI;
/// - temp files left by a termination are cleaned by [recoverIncompleteWrites].
class StorageService {
  final Directory? rootOverride;

  const StorageService({this.rootOverride});

  Future<Directory> _root() async {
    if (rootOverride != null) return rootOverride!;
    return getApplicationDocumentsDirectory();
  }

  Future<Directory> _sessionDir(String eventId, String sessionId) async {
    try {
      final root = await _root();
      final dir = Directory('${root.path}/events/$eventId/sessions/$sessionId');
      await dir.create(recursive: true);
      return dir;
    } on FileSystemException catch (e) {
      throw StorageException('DIRECTORY_FAILED', e.toString());
    }
  }

  String _safeToken(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isEmpty) {
      return 'capture_${DateTime.now().microsecondsSinceEpoch}';
    }
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }

  Future<File> _uniqueTarget(
    Directory dir,
    String baseName,
    String extension,
  ) async {
    var target = File('${dir.path}/$baseName.$extension');
    var n = 2;
    while (await target.exists()) {
      target = File('${dir.path}/${baseName}__$n.$extension');
      n++;
    }
    return target;
  }

  /// Saves original bytes atomically and returns the final path.
  ///
  /// [captureId] makes the filename unique and ties the file to the capture
  /// request. If omitted, a timestamp is used instead of overwriting.
  Future<String> saveOriginal({
    required String eventId,
    required String sessionId,
    required int index,
    required Uint8List bytes,
    String? captureId,
    String extension = 'jpg',
  }) async {
    if (bytes.isEmpty) {
      throw const StorageException(
        'EMPTY_IMAGE',
        'refusing to save an empty image',
      );
    }
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (ext != 'jpg' && ext != 'jpeg' && ext != 'png') {
      throw StorageException(
        'UNSUPPORTED_EXTENSION',
        'unsupported image extension: $extension',
      );
    }
    final dir = await _sessionDir(eventId, sessionId);
    final token = _safeToken(
      captureId ?? 'cap_${DateTime.now().microsecondsSinceEpoch}',
    );
    final target = await _uniqueTarget(dir, 'original_${index}_$token', ext);
    final temp = File(
      '${dir.path}/.terabooth-tmp-${DateTime.now().microsecondsSinceEpoch}-$token.part',
    );

    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await temp.length() != bytes.length) {
        throw const StorageException(
          'SHORT_WRITE',
          'temp file length does not match input',
        );
      }
      await temp.rename(target.path);
      if (await target.length() != bytes.length) {
        throw const StorageException(
          'VERIFY_FAILED',
          'saved file length does not match input',
        );
      }
      return target.path;
    } on StorageException {
      await _deleteQuietly(temp);
      await _deleteQuietly(target);
      rethrow;
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      await _deleteQuietly(target);
      throw StorageException('WRITE_FAILED', e.toString());
    } catch (e) {
      await _deleteQuietly(temp);
      await _deleteQuietly(target);
      throw StorageException('WRITE_FAILED', e.toString());
    }
  }

  /// Atomically writes session metadata. Metadata may be replaced intentionally;
  /// originals never are.
  Future<void> writeSessionMetadata({
    required String eventId,
    required String sessionId,
    required Map<String, dynamic> data,
  }) async {
    final dir = await _sessionDir(eventId, sessionId);
    final file = File('${dir.path}/session.json');
    final temp = File(
      '${dir.path}/.terabooth-tmp-${DateTime.now().microsecondsSinceEpoch}-session.part',
    );
    try {
      await temp.writeAsString(jsonEncode(data), flush: true);
      await temp.rename(file.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('METADATA_WRITE_FAILED', e.toString());
    } catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('METADATA_WRITE_FAILED', e.toString());
    }
  }

  /// Finds an existing original for [captureId], including files saved before
  /// an app restart. Used to reject duplicate image delivery.
  Future<String?> findOriginalForCapture({
    required String eventId,
    required String sessionId,
    required String captureId,
  }) async {
    final dir = await _sessionDir(eventId, sessionId);
    final token = _safeToken(captureId);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (!name.startsWith('original_')) continue;
      if (name.contains('_$token.') || name.contains('_${token}__')) {
        return entity.path;
      }
    }
    return null;
  }

  /// Finds complete originals that are not referenced by session.json and
  /// records them in orphans.json. It never deletes an original and never
  /// assigns an orphan to a capture slot.
  Future<List<OrphanRecord>> recoverOrphans({
    String? eventId,
    String? sessionId,
  }) async {
    final dirs = await _sessionDirs(eventId: eventId, sessionId: sessionId);
    final all = <OrphanRecord>[];
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      final referenced = await _referencedFilenames(dir);
      final existing = await _readOrphanRecords(dir);
      final complete = await _completeOriginals(dir);
      final next = <String, OrphanRecord>{};

      // Keep existing records only while the file exists and is still orphaned.
      for (final record in existing) {
        if (referenced.contains(record.filename)) continue;
        if (!complete.any((f) => _basename(f.path) == record.filename)) {
          continue;
        }
        next[record.filename] = record;
      }
      for (final file in complete) {
        final name = _basename(file.path);
        if (referenced.contains(name)) continue;
        next.putIfAbsent(name, () => _orphanFromFile(file));
      }

      final records = next.values.toList()
        ..sort((a, b) => a.filename.compareTo(b.filename));
      await _writeOrphanRecords(dir, eventId, sessionId, records);
      all.addAll(records);
    }
    return all;
  }

  Future<List<Directory>> _sessionDirs({
    String? eventId,
    String? sessionId,
  }) async {
    final root = await _root();
    final base = Directory('${root.path}/events');
    if (!await base.exists()) return [];
    final result = <Directory>[];
    if (eventId != null && sessionId != null) {
      final dir = Directory('${base.path}/$eventId/sessions/$sessionId');
      if (await dir.exists()) result.add(dir);
      return result;
    }
    final events = <Directory>[];
    if (eventId != null) {
      events.add(Directory('${base.path}/$eventId'));
    } else {
      await for (final entity in base.list()) {
        if (entity is Directory) events.add(entity);
      }
    }
    for (final event in events) {
      final sessions = Directory('${event.path}/sessions');
      if (!await sessions.exists()) continue;
      await for (final entity in sessions.list()) {
        if (entity is Directory) result.add(entity);
      }
    }
    return result;
  }

  String _basename(String path) => path.split('/').last;

  Future<Set<String>> _referencedFilenames(Directory dir) async {
    final file = File('${dir.path}/session.json');
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      final captures = decoded['captures'];
      if (captures is! List) return {};
      final result = <String>{};
      for (final capture in captures) {
        if (capture is! Map) continue;
        final path = capture['path'];
        if (path is String && path.isNotEmpty) {
          result.add(_basename(path));
        }
        final filename = capture['filename'];
        if (filename is String && filename.isNotEmpty) {
          result.add(_basename(filename));
        }
      }
      return result;
    } catch (_) {
      // A malformed metadata file must not cause deletion or assignment.
      return {};
    }
  }

  Future<List<OrphanRecord>> _readOrphanRecords(Directory dir) async {
    final file = File('${dir.path}/orphans.json');
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final orphans = decoded['orphans'];
      if (orphans is! List) return [];
      return [
        for (final item in orphans)
          if (item is Map) OrphanRecord.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeOrphanRecords(
    Directory dir,
    String? eventId,
    String? sessionId,
    List<OrphanRecord> records,
  ) async {
    final file = File('${dir.path}/orphans.json');
    final temp = File(
      '${dir.path}/.terabooth-tmp-${DateTime.now().microsecondsSinceEpoch}-orphans.part',
    );
    final payload = {
      'version': 1,
      'event_id': eventId ?? dir.parent.parent.path.split('/').last,
      'session_id': sessionId ?? dir.path.split('/').last,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'orphans': [for (final record in records) record.toJson()],
    };
    try {
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(file.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('ORPHAN_WRITE_FAILED', e.toString());
    }
  }

  Future<List<File>> _completeOriginals(Directory dir) async {
    final result = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = _basename(entity.path);
      if (!name.startsWith('original_')) continue;
      if (!name.endsWith('.jpg') &&
          !name.endsWith('.jpeg') &&
          !name.endsWith('.png')) {
        continue;
      }
      if (await _hasImageSignature(entity)) result.add(entity);
    }
    return result;
  }

  Future<bool> _hasImageSignature(File file) async {
    try {
      if (await file.length() == 0) return false;
      final handle = await file.open();
      try {
        final header = await handle.read(8);
        if (header.length >= 3 &&
            header[0] == 0xFF &&
            header[1] == 0xD8 &&
            header[2] == 0xFF) {
          return true;
        }
        return header.length >= 8 &&
            header[0] == 0x89 &&
            header[1] == 0x50 &&
            header[2] == 0x4E &&
            header[3] == 0x47 &&
            header[4] == 0x0D &&
            header[5] == 0x0A &&
            header[6] == 0x1A &&
            header[7] == 0x0A;
      } finally {
        await handle.close();
      }
    } catch (_) {
      return false;
    }
  }

  OrphanRecord _orphanFromFile(File file) {
    final name = _basename(file.path);
    final stem = name.substring(0, name.lastIndexOf('.'));
    final match = RegExp(r'^original_(\d+)_(.+)$').firstMatch(stem);
    return OrphanRecord(
      filename: name,
      path: file.path,
      byteLength: file.lengthSync(),
      candidateCaptureId: match?.group(2),
      candidateSlot: match == null ? null : int.tryParse(match.group(1)!),
      detectedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Persists the ordered event catalog (first entry is the active event).
  Future<List<EventProfile>> readEventCatalog() async {
    final root = await _root();
    final file = File('${root.path}/event_catalog.json');
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map) EventProfile.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> writeEventCatalog(List<EventProfile> events) async {
    final root = await _root();
    final file = File('${root.path}/event_catalog.json');
    final temp = File(
      '${root.path}/.terabooth-tmp-${DateTime.now().microsecondsSinceEpoch}-events.part',
    );
    try {
      await temp.writeAsString(
        jsonEncode([for (final event in events) event.toJson()]),
        flush: true,
      );
      await temp.rename(file.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('EVENT_CATALOG_WRITE_FAILED', e.toString());
    }
  }

  /// Persists operator settings (currently the bridge URL only).
  Future<Map<String, dynamic>> readSettings() async {
    final root = await _root();
    final file = File('${root.path}/settings.json');
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> writeSettings(Map<String, dynamic> settings) async {
    final root = await _root();
    final file = File('${root.path}/settings.json');
    final temp = File(
      '${root.path}/.terabooth-tmp-${DateTime.now().microsecondsSinceEpoch}-settings.part',
    );
    try {
      await temp.writeAsString(jsonEncode(settings), flush: true);
      await temp.rename(file.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('SETTINGS_WRITE_FAILED', e.toString());
    }
  }

  /// Finds the newest complete, unsubmitted session for an event. Returns
  /// null if files are missing/incomplete or the session was already approved.
  Future<RestorableSession?> latestUnsubmittedSession({
    required String eventId,
  }) async {
    final dirs = await _sessionDirs(eventId: eventId);
    dirs.sort((a, b) => b.path.compareTo(a.path));
    for (final dir in dirs) {
      final metadataFile = File('${dir.path}/session.json');
      if (!await metadataFile.exists()) continue;
      try {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is! Map) continue;
        final map = decoded.cast<String, dynamic>();
        if (map['approved'] == true) continue;
        final captures = map['captures'];
        final expectedCount =
            (map['photo_count_expected'] as num?)?.toInt() ?? 3;
        if (captures is! List || captures.length != expectedCount) continue;
        final photos = <CapturedImage>[];
        var complete = true;
        for (final item in captures) {
          if (item is! Map) {
            complete = false;
            break;
          }
          final capture = item.cast<String, dynamic>();
          final path = capture['path'] as String?;
          if (path == null || !await File(path).exists()) {
            complete = false;
            break;
          }
          final bytes = await File(path).readAsBytes();
          if (bytes.isEmpty) {
            complete = false;
            break;
          }
          photos.add(
            CapturedImage(
              id: (capture['id'] as String?) ?? '',
              bytes: bytes,
              path: path,
              width: (capture['width'] as num?)?.toInt() ?? 0,
              height: (capture['height'] as num?)?.toInt() ?? 0,
              capturedAt:
                  DateTime.tryParse(capture['captured_at'] as String? ?? '') ??
                  DateTime.now(),
              captureId: capture['capture_id'] as String?,
              orientation: (capture['orientation'] as num?)?.toInt() ?? 1,
            ),
          );
        }
        if (!complete || photos.any((p) => p.width <= 0 || p.height <= 0)) {
          continue;
        }
        final crops = <String, CropDecision>{};
        final rawCrops = map['crops'];
        if (rawCrops is List) {
          for (final raw in rawCrops) {
            if (raw is! Map) continue;
            try {
              final decision = CropDecision.fromJson(
                raw.cast<String, dynamic>(),
              );
              crops[decision.slotId] = decision;
            } catch (_) {
              // A malformed crop is ignored; originals remain untouched.
            }
          }
        }
        return RestorableSession(
          eventId: eventId,
          sessionId: (map['session_id'] as String?) ?? dir.path.split('/').last,
          templateId: (map['template'] as String?) ?? 'strip_2x6_3up_v1',
          templateVersion: (map['template_version'] as num?)?.toInt() ?? 1,
          photos: photos,
          crops: crops,
          photoCount: expectedCount,
          countdownSeconds: (map['countdown_seconds'] as num?)?.toInt() ?? 3,
          configuration: EventConfiguration.fromJson(
            (map['configuration'] as Map?)?.cast<String, dynamic>(),
          ),
          branding: EventBranding.fromJson(
            (map['branding'] as Map?)?.cast<String, dynamic>(),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<String> exportEventReportCsv(EventReport report) async {
    final root = await _root();
    final dir = Directory('${root.path}/exports');
    await dir.create(recursive: true);
    final safe = report.event.title
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final file = File('${dir.path}/${report.event.id}_$safe.csv');
    final temp = File(
      '${dir.path}/.report-${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temp.writeAsString(report.toCsv(), flush: true);
      await temp.rename(file.path);
      return file.path;
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('REPORT_WRITE_FAILED', e.toString());
    }
  }

  Future<Directory> _eventDir(String eventId) async {
    try {
      final root = await _root();
      final dir = Directory('${root.path}/events/$eventId');
      await dir.create(recursive: true);
      return dir;
    } on FileSystemException catch (e) {
      throw StorageException('DIRECTORY_FAILED', e.toString());
    }
  }

  /// Stores a validated event logo outside JSON, atomically.
  Future<String> saveBrandingLogo(
    String eventId,
    List<int> bytes,
    String extension,
  ) async {
    final dir = Directory('${(await _eventDir(eventId)).path}/branding');
    await dir.create(recursive: true);
    final target = File('${dir.path}/logo.$extension');
    final temp = File(
      '${dir.path}/.logo-${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
      return target.path;
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('BRANDING_LOGO_WRITE_FAILED', e.toString());
    }
  }

  Future<Uint8List?> readBrandingLogo(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteBrandingLogo(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A stale logo reference is handled by the branding validator.
    }
  }

  /// Returns all locally persisted session records for an event.
  Future<List<BoothSessionRecord>> readSessionsForEvent(String eventId) async {
    final root = await _root();
    final dir = Directory('${root.path}/events/$eventId/sessions');
    if (!await dir.exists()) return [];
    final records = <BoothSessionRecord>[];
    await for (final entry in dir.list()) {
      if (entry is! Directory) continue;
      final file = File('${entry.path}/session.json');
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        final record = BoothSessionRecord.fromJson(
          decoded.cast<String, dynamic>(),
          fallbackEventId: eventId,
          fallbackSessionId: entry.path.split('/').last,
        );
        records.add(record);
      } catch (_) {
        // Corrupt session metadata is skipped; image files are untouched.
      }
    }
    records.sort((a, b) {
      final aTime = a.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return records;
  }

  Future<bool> hasSessions(String eventId) async {
    final records = await readSessionsForEvent(eventId);
    return records.isNotEmpty;
  }

  /// Newest session that is still marked active and was not approved.
  Future<BoothSessionRecord?> latestActiveSession(String eventId) async {
    final records = await readSessionsForEvent(eventId);
    for (final record in records) {
      if (record.isActive) return record;
    }
    return null;
  }

  Future<SessionRecovery> readSessionRecovery(
    String eventId,
    String sessionId,
  ) async {
    final dir = await _sessionDir(eventId, sessionId);
    final file = File('${dir.path}/session.json');
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const StorageException(
        'SESSION_INVALID',
        'Session metadata is invalid.',
      );
    }
    final map = decoded.cast<String, dynamic>();
    final record = BoothSessionRecord.fromJson(
      map,
      fallbackEventId: eventId,
      fallbackSessionId: sessionId,
    );
    final expected = record.expectedPhotoCount.clamp(1, 4);
    final missing = <int>[];
    final photos = <CapturedImage>[];
    final captures = map['captures'];
    final bySlot = <int, Map<String, dynamic>>{};
    if (captures is List) {
      for (final raw in captures) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final slot = (item['slot'] as num?)?.toInt();
        if (slot != null) bySlot[slot] = item;
      }
    }
    for (var slot = 1; slot <= expected; slot++) {
      final item = bySlot[slot];
      final path = item?['path'] as String?;
      if (item == null || path == null) {
        missing.add(slot);
        continue;
      }
      try {
        final imageFile = File(path);
        if (!await imageFile.exists()) {
          missing.add(slot);
          continue;
        }
        final bytes = await imageFile.readAsBytes();
        if (bytes.isEmpty) {
          missing.add(slot);
          continue;
        }
        photos.add(
          CapturedImage(
            id: item['id'] as String? ?? '',
            bytes: bytes,
            path: path,
            width: (item['width'] as num?)?.toInt() ?? 0,
            height: (item['height'] as num?)?.toInt() ?? 0,
            capturedAt:
                DateTime.tryParse(item['captured_at'] as String? ?? '') ??
                DateTime.now(),
            captureId: item['capture_id'] as String?,
            orientation: (item['orientation'] as num?)?.toInt() ?? 1,
          ),
        );
      } catch (_) {
        missing.add(slot);
      }
    }
    final crops = <String, CropDecision>{};
    final rawCrops = map['crops'];
    if (rawCrops is List) {
      for (final raw in rawCrops) {
        if (raw is! Map) continue;
        try {
          final decision = CropDecision.fromJson(raw.cast<String, dynamic>());
          crops[decision.slotId] = decision;
        } catch (_) {
          // A malformed crop is ignored; originals remain untouched.
        }
      }
    }
    return SessionRecovery(
      record: record,
      photos: photos,
      missingSlots: missing,
      crops: crops,
      configuration: EventConfiguration.fromJson(
        (map['configuration'] as Map?)?.cast<String, dynamic>(),
      ),
      branding: EventBranding.fromJson(
        (map['branding'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }

  Future<void> updateSessionStatus({
    required String eventId,
    required String sessionId,
    required String status,
    bool ended = true,
  }) async {
    final dir = await _sessionDir(eventId, sessionId);
    final file = File('${dir.path}/session.json');
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return;
    final data = decoded.cast<String, dynamic>();
    data['status'] = status;
    if (ended) data['ended_at'] = DateTime.now().toUtc().toIso8601String();
    await writeSessionMetadata(
      eventId: eventId,
      sessionId: sessionId,
      data: data,
    );
  }

  /// Marks an interrupted session without touching captures or originals.
  Future<void> markSessionInterrupted({
    required String eventId,
    required String sessionId,
  }) async {
    final dir = await _sessionDir(eventId, sessionId);
    final file = File('${dir.path}/session.json');
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return;
    final data = decoded.cast<String, dynamic>();
    data['status'] = BoothSessionStatus.interrupted;
    data['ended_at'] = DateTime.now().toUtc().toIso8601String();
    await writeSessionMetadata(
      eventId: eventId,
      sessionId: sessionId,
      data: data,
    );
  }

  Future<Directory> _submittedJobsDir(String eventId) async {
    final root = await _root();
    final dir = Directory('${root.path}/events/$eventId/submitted_jobs');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> writeSubmittedJob(SubmittedJob job) async {
    final dir = await _submittedJobsDir(job.eventId);
    final file = File('${dir.path}/${job.jobId}.json');
    final temp = File(
      '${dir.path}/.terabooth-tmp-${DateTime.now().microsecondsSinceEpoch}-job.part',
    );
    try {
      await temp.writeAsString(jsonEncode(job.toJson()), flush: true);
      await temp.rename(file.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(temp);
      throw StorageException('SUBMITTED_JOB_WRITE_FAILED', e.toString());
    }
  }

  Future<SubmittedJob?> readLatestSubmittedJob({
    required String eventId,
  }) async {
    final dir = await _submittedJobsDir(eventId);
    final candidates = <SubmittedJob>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final job = SubmittedJob.fromJson(decoded.cast<String, dynamic>());
        if (job.dismissed || job.jobId.isEmpty || job.eventId != eventId) {
          continue;
        }
        candidates.add(job);
      } catch (_) {
        // Corrupt job metadata is skipped; originals are untouched.
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return candidates.first;
  }

  Future<List<String>> listOriginals(String eventId, String sessionId) async {
    final dir = await _sessionDir(eventId, sessionId);
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('.terabooth-tmp-')) continue;
      if (name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files.map((e) => e.path).toList();
  }

  /// Removes temp/partial files left by an app termination. Never deletes a
  /// completed original or a valid session.json.
  Future<int> recoverIncompleteWrites({
    String? eventId,
    String? sessionId,
  }) async {
    final root = await _root();
    final base = Directory('${root.path}/events');
    if (!await base.exists()) return 0;
    final candidates = <Directory>[];
    if (eventId != null && sessionId != null) {
      candidates.add(Directory('${base.path}/$eventId/sessions/$sessionId'));
    } else if (eventId != null) {
      final sessions = Directory('${base.path}/$eventId/sessions');
      if (await sessions.exists()) {
        await for (final entity in sessions.list()) {
          if (entity is Directory) candidates.add(entity);
        }
      }
    } else {
      await for (final event in base.list()) {
        if (event is! Directory) continue;
        final sessions = Directory('${event.path}/sessions');
        if (!await sessions.exists()) continue;
        await for (final entity in sessions.list()) {
          if (entity is Directory) candidates.add(entity);
        }
      }
    }

    var removed = 0;
    for (final dir in candidates) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split('/').last;
        if (name.startsWith('.terabooth-tmp-') || name.endsWith('.tmp')) {
          if (await _deleteQuietly(entity)) removed++;
        }
      }
    }
    return removed;
  }

  Future<void> verifyOriginal(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const StorageException(
        'VERIFY_FAILED',
        'saved original does not exist',
      );
    }
    if (await file.length() == 0) {
      throw const StorageException('VERIFY_FAILED', 'saved original is empty');
    }
  }

  Future<bool> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {
      // Best effort cleanup; never mask the original failure.
    }
    return false;
  }
}
