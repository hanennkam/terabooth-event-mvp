import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../crop/crop_models.dart';
import '../templates/template_models.dart';

class BridgeException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const BridgeException(this.code, this.message, {this.statusCode});

  @override
  String toString() => message;
}

class BridgeClient {
  final String baseUrl;
  final String? token;
  final http.Client client;
  final Duration healthTimeout;
  final Duration submitTimeout;
  final Duration statusTimeout;
  final Duration reprintTimeout;
  final Duration artefactTimeout;
  final Duration gifTimeout;

  BridgeClient({
    required this.baseUrl,
    this.token,
    http.Client? client,
    this.healthTimeout = const Duration(seconds: 5),
    this.submitTimeout = const Duration(seconds: 30),
    this.statusTimeout = const Duration(seconds: 5),
    this.reprintTimeout = const Duration(seconds: 10),
    this.artefactTimeout = const Duration(seconds: 10),
    this.gifTimeout = const Duration(seconds: 15),
  }) : client = client ?? http.Client();

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$path');

  Map<String, String> get _headers => {
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<T> _request<T>(
    String operation,
    Duration timeout,
    Future<T> Function() run,
  ) async {
    try {
      return await run().timeout(timeout);
    } on BridgeException {
      rethrow;
    } on TimeoutException {
      throw BridgeException(
        '${operation}_TIMEOUT',
        '$operation timed out after ${timeout.inSeconds}s.',
      );
    } on http.ClientException catch (e) {
      throw BridgeException(
        '${operation}_FAILED',
        '$operation failed: ${e.message}',
      );
    }
  }

  Future<HealthStatus> health() {
    return _request('HEALTH', healthTimeout, () async {
      final r = await client.get(_uri('/v1/health'), headers: _headers);
      if (r.statusCode != 200) {
        throw BridgeException(
          'HEALTH_FAILED',
          'Health check failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return HealthStatus.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    });
  }

  Future<PrintJob> submit({
    required String eventId,
    required String sessionId,
    required String title,
    required String date,
    required List<CapturedImage> images,
    PhotoTemplate? template,
    List<CropDecision> crops = const [],
    EventBranding? branding,
    Uint8List? brandingLogo,
  }) {
    final expected = template?.slots.length ?? 3;
    if (images.length != expected) {
      return Future.error(
        ArgumentError(
          'template requires $expected images, got ${images.length}',
        ),
      );
    }
    return _request('SUBMIT', submitTimeout, () async {
      final meta = {
        'schema': 'terabooth.print/1',
        'event_id': eventId,
        'session_id': sessionId,
        'template': template?.id ?? 'strip_2x6_3up_v1',
        if (template != null) 'template_version': template.version,
        if (crops.isNotEmpty)
          'crops': [for (final crop in crops) crop.toJson()],
        'copies': 1,
        'paper': '4x6',
        'cut': '2x6',
        'event_text': {'title': title, 'date': date},
        if (branding != null && branding.enabled)
          'branding': {
            'enabled': true,
            'title': branding.title,
            'tagline': branding.tagline,
            'color_hex': branding.colorHex,
            'placement': branding.placement.name,
          },
        'images': [
          for (var i = 0; i < images.length; i++)
            {
              'id': images[i].id,
              'filename': '${images[i].id}.jpg',
              'sha256': sha256.convert(images[i].bytes).toString(),
              'width': images[i].width,
              'height': images[i].height,
            },
        ],
        'delivery': {'required': true, 'ttl_hours': 24},
      };
      final request = http.MultipartRequest('POST', _uri('/v1/print-jobs'))
        ..headers.addAll(_headers)
        ..headers['Idempotency-Key'] = _idempotencyKey(
          sessionId,
          images,
          template: template,
          crops: crops,
          branding: branding,
          brandingLogo: brandingLogo,
        )
        ..fields['metadata'] = jsonEncode(meta);
      for (var i = 0; i < images.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'image_$i',
            images[i].bytes,
            filename: '${images[i].id}.jpg',
            contentType: null,
          ),
        );
      }
      if (branding != null && branding.enabled && brandingLogo != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'branding_logo',
            brandingLogo,
            filename: 'branding_logo',
            contentType: null,
          ),
        );
      }
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 202 && response.statusCode != 200) {
        throw BridgeException(
          'SUBMIT_FAILED',
          'Print submit failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      return PrintJob.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    });
  }

  Future<PrintJob> getJob(String jobId) {
    return _request('STATUS', statusTimeout, () async {
      final r = await client.get(
        _uri('/v1/print-jobs/$jobId'),
        headers: _headers,
      );
      if (r.statusCode != 200) {
        throw BridgeException(
          'STATUS_FAILED',
          'Job status failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return PrintJob.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    });
  }

  /// Fetches the bridge-generated 1200×1800 composition.
  Future<Uint8List> artefact(String jobId) {
    return _request('ARTEFACT', artefactTimeout, () async {
      final r = await client.get(
        _uri('/v1/print-jobs/$jobId/artefact'),
        headers: _headers,
      );
      if (r.statusCode == 404) {
        throw const BridgeException(
          'ARTEFACT_NOT_READY',
          'The final composition is not ready yet.',
          statusCode: 404,
        );
      }
      if (r.statusCode != 200) {
        throw BridgeException(
          'ARTEFACT_FAILED',
          'Composition request failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return r.bodyBytes;
    });
  }

  /// Fetches the independent animated GIF artefact.
  Future<Uint8List> gif(String jobId) {
    return _request('GIF', gifTimeout, () async {
      final r = await client.get(
        _uri('/v1/print-jobs/$jobId/gif'),
        headers: _headers,
      );
      if (r.statusCode == 409) {
        throw const BridgeException(
          'GIF_NOT_READY',
          'The animated GIF is still being prepared.',
          statusCode: 409,
        );
      }
      if (r.statusCode == 404) {
        throw const BridgeException(
          'GIF_UNAVAILABLE',
          'The animated GIF is unavailable.',
          statusCode: 404,
        );
      }
      if (r.statusCode != 200) {
        throw BridgeException(
          'GIF_FAILED',
          'Animated GIF request failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return r.bodyBytes;
    });
  }

  Future<PrintJob> revokeDelivery(String jobId) {
    return _request('REVOKE', reprintTimeout, () async {
      final r = await client.post(
        _uri('/v1/print-jobs/$jobId/delivery/revoke'),
        headers: _headers,
      );
      if (r.statusCode != 200) {
        throw BridgeException(
          'REVOKE_FAILED',
          'Guest access revocation failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return PrintJob.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    });
  }

  Future<PrintJob> regenerateDelivery(String jobId) {
    return _request('REGENERATE_LINK', reprintTimeout, () async {
      final r = await client.post(
        _uri('/v1/print-jobs/$jobId/delivery/regenerate'),
        headers: _headers,
      );
      if (r.statusCode != 200) {
        throw BridgeException(
          'REGENERATE_LINK_FAILED',
          'Guest link regeneration failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return PrintJob.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    });
  }

  Future<PrintJob> reprint(String jobId) {
    return _request('REPRINT', reprintTimeout, () async {
      final r = await client.post(
        _uri('/v1/print-jobs/$jobId/reprint'),
        headers: {
          ..._headers,
          'Idempotency-Key':
              'reprint-$jobId-${DateTime.now().microsecondsSinceEpoch}',
        },
      );
      if (r.statusCode != 202 && r.statusCode != 200) {
        throw BridgeException(
          'REPRINT_FAILED',
          'Reprint failed (${r.statusCode}).',
          statusCode: r.statusCode,
        );
      }
      return PrintJob.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
    });
  }

  String _idempotencyKey(
    String sessionId,
    List<CapturedImage> images, {
    PhotoTemplate? template,
    List<CropDecision> crops = const [],
    EventBranding? branding,
    Uint8List? brandingLogo,
  }) {
    final templatePart = template == null
        ? 'strip_2x6_3up_v1|1'
        : '${template.id}|${template.version}';
    final cropPart = [
      for (final crop in crops)
        '${crop.slotId}:${crop.mode.wireName}:${crop.rect.toJson()}',
    ].join(',');
    final h = sha256.convert(
      utf8.encode(
        '$sessionId|${images.map((e) => sha256.convert(e.bytes)).join("|")}|$templatePart|$cropPart|1',
      ),
    );
    return h.toString();
  }
}
