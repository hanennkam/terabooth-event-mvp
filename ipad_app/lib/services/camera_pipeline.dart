import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import 'camera_contract.dart';
import 'camera_service.dart';
import 'exif_orientation.dart';
import 'storage_service.dart';

/// Connection state is intentionally separate from capture state.
enum CameraConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  recovering,
  failed,
}

/// Capture state is intentionally separate from connection state.
enum CameraCaptureState { idle, capturing, transferring, ready, failed }

@immutable
class CameraPipelineState {
  final CameraConnectionState connection;
  final CameraCaptureState capture;
  final String? captureId;
  final String? errorCode;
  final String? errorMessage;

  const CameraPipelineState({
    this.connection = CameraConnectionState.disconnected,
    this.capture = CameraCaptureState.idle,
    this.captureId,
    this.errorCode,
    this.errorMessage,
  });

  bool get isCaptureInFlight =>
      capture == CameraCaptureState.capturing ||
      capture == CameraCaptureState.transferring;

  bool get canCapture =>
      connection == CameraConnectionState.connected && !isCaptureInFlight;

  CameraPipelineState copyWith({
    CameraConnectionState? connection,
    CameraCaptureState? capture,
    String? captureId,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CameraPipelineState(
      connection: connection ?? this.connection,
      capture: capture ?? this.capture,
      captureId: captureId ?? this.captureId,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class InvalidCameraStateTransition implements Exception {
  final CameraConnectionState? fromConnection;
  final CameraConnectionState? toConnection;
  final CameraCaptureState? fromCapture;
  final CameraCaptureState? toCapture;

  const InvalidCameraStateTransition.connection(
    this.fromConnection,
    this.toConnection,
  ) : fromCapture = null,
      toCapture = null;

  const InvalidCameraStateTransition.capture(this.fromCapture, this.toCapture)
    : fromConnection = null,
      toConnection = null;

  @override
  String toString() {
    if (fromConnection != null || toConnection != null) {
      return 'Invalid camera connection transition: $fromConnection -> $toConnection';
    }
    return 'Invalid capture state transition: $fromCapture -> $toCapture';
  }
}

class CameraStateMachine {
  const CameraStateMachine._();

  static const Map<CameraConnectionState, Set<CameraConnectionState>>
  connectionTransitions = {
    CameraConnectionState.disconnected: {
      CameraConnectionState.discovering,
      CameraConnectionState.connecting,
      CameraConnectionState.failed,
    },
    CameraConnectionState.discovering: {
      CameraConnectionState.connecting,
      CameraConnectionState.disconnected,
      CameraConnectionState.failed,
    },
    CameraConnectionState.connecting: {
      CameraConnectionState.connected,
      CameraConnectionState.disconnected,
      CameraConnectionState.failed,
    },
    CameraConnectionState.connected: {
      CameraConnectionState.recovering,
      CameraConnectionState.disconnected,
      CameraConnectionState.failed,
    },
    CameraConnectionState.recovering: {
      CameraConnectionState.connecting,
      CameraConnectionState.connected,
      CameraConnectionState.disconnected,
      CameraConnectionState.failed,
    },
    CameraConnectionState.failed: {
      CameraConnectionState.disconnected,
      CameraConnectionState.discovering,
      CameraConnectionState.connecting,
    },
  };

  static const Map<CameraCaptureState, Set<CameraCaptureState>>
  captureTransitions = {
    CameraCaptureState.idle: {
      CameraCaptureState.capturing,
      CameraCaptureState.failed,
    },
    CameraCaptureState.capturing: {
      CameraCaptureState.transferring,
      CameraCaptureState.failed,
    },
    CameraCaptureState.transferring: {
      CameraCaptureState.ready,
      CameraCaptureState.failed,
    },
    CameraCaptureState.ready: {
      CameraCaptureState.capturing,
      CameraCaptureState.idle,
    },
    CameraCaptureState.failed: {
      CameraCaptureState.idle,
      CameraCaptureState.capturing,
    },
  };

  static bool canTransitionConnection(
    CameraConnectionState from,
    CameraConnectionState to,
  ) {
    if (from == to) return true;
    return connectionTransitions[from]?.contains(to) ?? false;
  }

  static bool canTransitionCapture(
    CameraCaptureState from,
    CameraCaptureState to,
  ) {
    if (from == to) return true;
    return captureTransitions[from]?.contains(to) ?? false;
  }

  static void requireConnection(
    CameraConnectionState from,
    CameraConnectionState to,
  ) {
    if (!canTransitionConnection(from, to)) {
      throw InvalidCameraStateTransition.connection(from, to);
    }
  }

  static void requireCapture(CameraCaptureState from, CameraCaptureState to) {
    if (!canTransitionCapture(from, to)) {
      throw InvalidCameraStateTransition.capture(from, to);
    }
  }
}

class CameraPipelineException implements Exception {
  final String code;
  final String message;
  final bool recoverable;
  final String? captureId;

  const CameraPipelineException(
    this.code,
    this.message, {
    this.recoverable = true,
    this.captureId,
  });

  @override
  String toString() => '$code: $message';
}

class ImageValidationPolicy {
  final int minBytes;
  final int maxBytes;
  final int minLongEdge;
  final int minShortEdge;
  final int maxPixels;

  const ImageValidationPolicy({
    this.minBytes = 1024,
    this.maxBytes = 40 * 1024 * 1024,
    this.minLongEdge = 1800,
    this.minShortEdge = 600,
    this.maxPixels = 100000000,
  });
}

class ImageValidationResult {
  /// Effective dimensions after EXIF orientation.
  final int width;
  final int height;
  final String extension;
  final int orientation;
  final int rawWidth;
  final int rawHeight;

  const ImageValidationResult(
    this.width,
    this.height,
    this.extension, {
    this.orientation = 1,
    this.rawWidth = 0,
    this.rawHeight = 0,
  });
}

class ImageValidator {
  final ImageValidationPolicy policy;

  const ImageValidator({this.policy = const ImageValidationPolicy()});

  Future<ImageValidationResult> validate(
    Uint8List bytes, {
    required bool allowPng,
  }) async {
    if (bytes.length < policy.minBytes) {
      throw CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'image is too small (${bytes.length} bytes)',
      );
    }
    if (bytes.length > policy.maxBytes) {
      throw CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'image is too large (${bytes.length} bytes)',
      );
    }

    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    final isPng =
        bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;

    if (!isJpeg && !isPng) {
      throw const CameraPipelineException(
        CameraErrorCodes.unsupportedImage,
        'only JPEG or PNG image data is accepted',
      );
    }
    if (isJpeg &&
        (bytes.length < 2 ||
            bytes[bytes.length - 2] != 0xFF ||
            bytes[bytes.length - 1] != 0xD9)) {
      throw const CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'JPEG is truncated or missing its end-of-image marker',
      );
    }
    if (isPng && !allowPng) {
      throw const CameraPipelineException(
        CameraErrorCodes.unsupportedImage,
        'native camera images must be JPEG, not PNG',
      );
    }

    final dimensions = isJpeg ? _jpegDimensions(bytes) : _pngDimensions(bytes);
    if (dimensions == null) {
      throw const CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'image header is invalid or truncated',
      );
    }
    final rawWidth = dimensions.$1;
    final rawHeight = dimensions.$2;
    final orientation = isJpeg ? ExifOrientation.readJpeg(bytes) : 1;
    final effective = ExifOrientation.effectiveDimensions(
      rawWidth,
      rawHeight,
      orientation,
    );
    final width = effective.$1;
    final height = effective.$2;
    final longEdge = width > height ? width : height;
    final shortEdge = width > height ? height : width;
    if (longEdge < policy.minLongEdge || shortEdge < policy.minShortEdge) {
      throw CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'image dimensions ${width}x$height are below the print minimum',
      );
    }
    if (width * height > policy.maxPixels) {
      throw CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'image dimensions ${width}x$height exceed the pixel limit',
      );
    }

    // Decode a small version to prove the payload is decodable without
    // allocating a full 30 MP bitmap in memory.
    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: width > 128 ? 128 : width,
        targetHeight: height > 128 ? 128 : height,
      );
      frame = await codec.getNextFrame();
      if (frame.image.width <= 0 || frame.image.height <= 0) {
        throw const CameraPipelineException(
          CameraErrorCodes.invalidImage,
          'decoded image has invalid dimensions',
        );
      }
      return ImageValidationResult(
        width,
        height,
        isJpeg ? 'jpg' : 'png',
        orientation: orientation,
        rawWidth: rawWidth,
        rawHeight: rawHeight,
      );
    } on CameraPipelineException {
      rethrow;
    } catch (e) {
      throw CameraPipelineException(
        CameraErrorCodes.invalidImage,
        'image could not be decoded: $e',
      );
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
  }

  /// Returns (width, height) from a JPEG SOF marker without decoding pixels.
  (int, int)? _jpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) return null;
      final marker = bytes[i++];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (marker == 0xD9) return null;
      if (i + 1 >= bytes.length) return null;
      final length = (bytes[i] << 8) | bytes[i + 1];
      if (length < 2 || i + length > bytes.length) return null;
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        if (i + 6 >= bytes.length) return null;
        final height = (bytes[i + 3] << 8) | bytes[i + 4];
        final width = (bytes[i + 5] << 8) | bytes[i + 6];
        if (width <= 0 || height <= 0) return null;
        return (width, height);
      }
      i += length;
    }
    return null;
  }

  /// Returns (width, height) from the PNG IHDR chunk.
  (int, int)? _pngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    // Signature is already checked by the caller.
    if (bytes[12] != 0x49 ||
        bytes[13] != 0x48 ||
        bytes[14] != 0x44 ||
        bytes[15] != 0x52) {
      return null;
    }
    final width =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    if (width <= 0 || height <= 0) return null;
    return (width, height);
  }
}

/// Validates, de-duplicates, atomically saves and reopens original images.
class ImageIngestor {
  final StorageService storage;
  final ImageValidator validator;
  final Set<String> _accepted = {};

  ImageIngestor({required this.storage, ImageValidator? validator})
    : validator = validator ?? const ImageValidator();

  Set<String> get acceptedCaptureIds => Set.unmodifiable(_accepted);

  Future<CapturedImage> ingest({
    required CapturedImage image,
    required String eventId,
    required String sessionId,
    required int slot,
    required String captureId,
    required bool allowPng,
  }) async {
    if (_accepted.contains(captureId)) {
      throw CameraPipelineException(
        CameraErrorCodes.duplicateImage,
        'image for capture $captureId has already been accepted',
        captureId: captureId,
      );
    }
    if (image.captureId != null && image.captureId != captureId) {
      throw CameraPipelineException(
        CameraErrorCodes.captureIdMismatch,
        'delivered image belongs to ${image.captureId}, expected $captureId',
        captureId: captureId,
      );
    }

    String? existing;
    try {
      existing = await storage.findOriginalForCapture(
        eventId: eventId,
        sessionId: sessionId,
        captureId: captureId,
      );
    } catch (e) {
      throw CameraPipelineException(
        CameraErrorCodes.storageFailed,
        'could not check for duplicate capture: $e',
        captureId: captureId,
      );
    }
    if (existing != null) {
      throw CameraPipelineException(
        CameraErrorCodes.duplicateImage,
        'capture $captureId already has an original at $existing',
        captureId: captureId,
      );
    }

    final validation = await validator.validate(
      image.bytes,
      allowPng: allowPng,
    );
    final sourceHash = sha256.convert(image.bytes).toString();
    String? path;
    try {
      path = await storage.saveOriginal(
        eventId: eventId,
        sessionId: sessionId,
        index: slot,
        bytes: image.bytes,
        captureId: captureId,
        extension: validation.extension,
      );
      await storage.verifyOriginal(path);
      // Reopen and decode the final file: never expose an incomplete original.
      final savedBytes = await File(path).readAsBytes();
      final savedValidation = await validator.validate(
        savedBytes,
        allowPng: allowPng,
      );
      final savedHash = sha256.convert(savedBytes).toString();
      if (savedHash != sourceHash) {
        throw CameraPipelineException(
          CameraErrorCodes.captureFailed,
          'stored original hash does not match received bytes',
          captureId: captureId,
        );
      }
      if (savedValidation.width != validation.width ||
          savedValidation.height != validation.height) {
        throw CameraPipelineException(
          CameraErrorCodes.captureFailed,
          'saved image dimensions changed after write',
          captureId: captureId,
        );
      }
    } on CameraPipelineException {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          // Best effort: do not expose an invalid saved file to the UI.
        }
      }
      rethrow;
    } catch (e) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          // Best effort cleanup.
        }
      }
      throw CameraPipelineException(
        CameraErrorCodes.storageFailed,
        'image could not be saved: $e',
        captureId: captureId,
      );
    }

    _accepted.add(captureId);
    return CapturedImage(
      id: captureId,
      bytes: image.bytes,
      width: validation.width,
      height: validation.height,
      capturedAt: image.capturedAt,
      path: path,
      captureId: captureId,
      sha256: sourceHash,
      orientation: validation.orientation,
    );
  }
}

class CameraPipeline extends ChangeNotifier {
  final CameraService camera;
  final ImageIngestor ingestor;
  final Duration captureTimeout;
  final Duration connectTimeout;

  final Queue<_CaptureJob> _queue = Queue<_CaptureJob>();
  _CaptureJob? _active;
  bool _disposed = false;
  int _counter = 0;
  StreamSubscription<CameraAdapterEvent>? _cameraEvents;

  CameraPipelineState _state = const CameraPipelineState();

  CameraPipeline({
    required this.camera,
    required StorageService storage,
    this.captureTimeout = const Duration(seconds: 15),
    this.connectTimeout = const Duration(seconds: 20),
    ImageValidator? validator,
  }) : ingestor = ImageIngestor(storage: storage, validator: validator) {
    if (camera is CameraEventSource) {
      _cameraEvents = (camera as CameraEventSource).parsedEvents.listen((
        event,
      ) {
        if (!event.isConnection) return;
        if (event.state == 'disconnected' ||
            event.state == 'failed' ||
            event.state == 'disconnectFailed') {
          notifyDisconnected(
            message: event.message?.isNotEmpty == true
                ? event.message!
                : 'camera disconnected',
          );
        }
      });
    }
  }

  CameraPipelineState get state => _state;
  CameraConnectionState get connectionState => _state.connection;
  CameraCaptureState get captureState => _state.capture;
  bool get isCaptureInFlight => _state.isCaptureInFlight;
  String? get lastError => _state.errorMessage;

  String _newCaptureId() {
    _counter++;
    return 'cap_${DateTime.now().toUtc().microsecondsSinceEpoch}_$_counter';
  }

  void _ensureActive() {
    if (_disposed) {
      throw const CameraPipelineException(
        CameraErrorCodes.disposed,
        'camera pipeline has been disposed',
        recoverable: false,
      );
    }
  }

  void _setConnection(
    CameraConnectionState next, {
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    if (_disposed) return;
    CameraStateMachine.requireConnection(_state.connection, next);
    _state = _state.copyWith(
      connection: next,
      errorCode: errorCode,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    notifyListeners();
  }

  void _setCapture(
    CameraCaptureState next, {
    String? captureId,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
  }) {
    if (_disposed) return;
    CameraStateMachine.requireCapture(_state.capture, next);
    _state = _state.copyWith(
      capture: next,
      captureId: captureId,
      errorCode: errorCode,
      errorMessage: errorMessage,
      clearError: clearError,
    );
    notifyListeners();
  }

  Future<void> connect() async {
    _ensureActive();
    if (_state.connection == CameraConnectionState.connected) return;
    if (_active != null) {
      throw const CameraPipelineException(
        CameraErrorCodes.captureInProgress,
        'cannot connect while a capture is in flight',
      );
    }
    if (_state.connection == CameraConnectionState.discovering ||
        _state.connection == CameraConnectionState.connecting) {
      throw const CameraPipelineException(
        CameraErrorCodes.connectFailed,
        'connection is already in progress',
      );
    }

    try {
      if (_state.connection == CameraConnectionState.recovering) {
        _setConnection(CameraConnectionState.connecting, clearError: true);
      } else {
        _setConnection(CameraConnectionState.discovering, clearError: true);
        _setConnection(CameraConnectionState.connecting);
      }
      await camera.connect().timeout(connectTimeout);
      _setConnection(CameraConnectionState.connected, clearError: true);
      if (_state.capture != CameraCaptureState.idle) {
        _setCapture(CameraCaptureState.idle, clearError: true);
      }
    } on TimeoutException {
      _setConnection(
        CameraConnectionState.failed,
        errorCode: CameraErrorCodes.connectTimeout,
        errorMessage: 'camera connection timed out',
      );
      throw const CameraPipelineException(
        CameraErrorCodes.connectTimeout,
        'camera connection timed out',
      );
    } on CameraPipelineException {
      rethrow;
    } catch (e) {
      _setConnection(
        CameraConnectionState.failed,
        errorCode: CameraErrorCodes.connectFailed,
        errorMessage: e.toString(),
      );
      throw CameraPipelineException(
        CameraErrorCodes.connectFailed,
        'camera connection failed: $e',
      );
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _failActive(
      CameraErrorCodes.disconnected,
      'camera disconnected',
      recoverable: true,
    );
    _failQueued(CameraErrorCodes.disconnected, 'camera disconnected');
    try {
      await camera.disconnect().timeout(const Duration(seconds: 10));
    } catch (_) {
      // The local state must still become disconnected.
    }
    if (_state.connection != CameraConnectionState.disconnected) {
      _setConnection(CameraConnectionState.disconnected, clearError: true);
    }
    if (_state.capture != CameraCaptureState.idle) {
      _setCapture(CameraCaptureState.idle, clearError: true);
    }
  }

  /// Call when the native adapter reports a USB/power disconnect.
  void notifyDisconnected({String message = 'camera disconnected'}) {
    if (_disposed) return;
    final hadActive = _active != null;
    _failActive(CameraErrorCodes.disconnected, message, recoverable: true);
    _failQueued(CameraErrorCodes.disconnected, message);
    if (!hadActive && _state.capture == CameraCaptureState.ready) {
      _setCapture(CameraCaptureState.idle);
    }
    if (_state.connection != CameraConnectionState.failed) {
      _setConnection(
        CameraConnectionState.failed,
        errorCode: CameraErrorCodes.disconnected,
        errorMessage: message,
      );
    }
  }

  /// Fails any in-flight capture; never reports it as successful.
  void handleAppBackgrounded() {
    if (_disposed) return;
    final hadActive = _active != null;
    _failActive(
      CameraErrorCodes.appBackgrounded,
      'app moved to background during capture',
    );
    _failQueued(CameraErrorCodes.appBackgrounded, 'app moved to background');
    if (!hadActive && _state.capture == CameraCaptureState.ready) {
      _setCapture(CameraCaptureState.idle);
    }
    if (_state.connection == CameraConnectionState.connected ||
        _state.connection == CameraConnectionState.connecting ||
        _state.connection == CameraConnectionState.discovering) {
      _setConnection(
        CameraConnectionState.recovering,
        errorCode: CameraErrorCodes.appBackgrounded,
        errorMessage: 'camera session paused while app was in background',
      );
    }
  }

  /// Attempts one reconnect. Never auto-captures.
  Future<void> handleAppForegrounded() async {
    if (_disposed) return;
    if (_state.connection != CameraConnectionState.recovering) return;
    try {
      await connect();
    } catch (_) {
      // connect() records the failure state; no fake success.
    }
  }

  Future<CapturedImage> capture({
    required String eventId,
    required String sessionId,
    required int slot,
  }) {
    _ensureActive();
    if (_state.connection != CameraConnectionState.connected) {
      return Future<CapturedImage>.error(
        const CameraPipelineException(
          CameraErrorCodes.notConnected,
          'camera is not connected',
        ),
      );
    }
    if ((_active != null && _active!.slot == slot) ||
        _queue.any((job) => job.slot == slot)) {
      return Future<CapturedImage>.error(
        CameraPipelineException(
          CameraErrorCodes.duplicateCapture,
          'capture for photo $slot is already requested',
        ),
      );
    }

    final job = _CaptureJob(
      captureId: _newCaptureId(),
      slot: slot,
      eventId: eventId,
      sessionId: sessionId,
    );
    _queue.add(job);
    _drain();
    return job.completer.future;
  }

  void _drain() {
    if (_disposed || _active != null || _queue.isEmpty) return;
    if (_state.connection != CameraConnectionState.connected) {
      _failQueued(CameraErrorCodes.notConnected, 'camera is not connected');
      return;
    }
    final job = _queue.removeFirst();
    _active = job;
    _setCapture(
      CameraCaptureState.capturing,
      captureId: job.captureId,
      clearError: true,
    );
    unawaited(_execute(job));
  }

  Future<void> _execute(_CaptureJob job) async {
    try {
      final delivered = await camera
          .capture(captureId: job.captureId)
          .timeout(captureTimeout);
      if (!identical(_active, job) || _disposed) return;
      if (delivered.captureId != null && delivered.captureId != job.captureId) {
        throw CameraPipelineException(
          CameraErrorCodes.captureIdMismatch,
          'camera returned ${delivered.captureId} for request ${job.captureId}',
          captureId: job.captureId,
        );
      }
      _setCapture(CameraCaptureState.transferring, captureId: job.captureId);
      final saved = await ingestor.ingest(
        image: delivered,
        eventId: job.eventId,
        sessionId: job.sessionId,
        slot: job.slot,
        captureId: job.captureId,
        allowPng: camera.isSimulated,
      );
      if (!identical(_active, job) || _disposed) return;
      _setCapture(
        CameraCaptureState.ready,
        captureId: job.captureId,
        clearError: true,
      );
      if (!job.completer.isCompleted) job.completer.complete(saved);
    } on TimeoutException {
      _failJob(
        job,
        CameraErrorCodes.captureTimeout,
        'capture ${job.captureId} timed out before a valid image was received',
      );
    } on CameraPipelineException catch (e) {
      _failJob(job, e.code, e.message);
    } catch (e) {
      _failJob(job, CameraErrorCodes.captureFailed, e.toString());
    } finally {
      if (identical(_active, job)) _active = null;
      _drain();
    }
  }

  void _failJob(_CaptureJob job, String code, String message) {
    if (!job.completer.isCompleted) {
      job.completer.completeError(
        CameraPipelineException(code, message, captureId: job.captureId),
      );
    }
    if (identical(_active, job)) {
      _active = null;
      if (!_disposed) {
        _setCapture(
          CameraCaptureState.failed,
          captureId: job.captureId,
          errorCode: code,
          errorMessage: message,
        );
      }
    }
  }

  void _failActive(String code, String message, {bool recoverable = true}) {
    final active = _active;
    if (active == null) return;
    if (!active.completer.isCompleted) {
      active.completer.completeError(
        CameraPipelineException(
          code,
          message,
          recoverable: recoverable,
          captureId: active.captureId,
        ),
      );
    }
    _active = null;
    if (!_disposed) {
      _setCapture(
        CameraCaptureState.failed,
        captureId: active.captureId,
        errorCode: code,
        errorMessage: message,
      );
    }
  }

  void _failQueued(String code, String message) {
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      if (!job.completer.isCompleted) {
        job.completer.completeError(
          CameraPipelineException(code, message, captureId: job.captureId),
        );
      }
    }
  }

  void resetCaptureState() {
    if (_active != null || _queue.isNotEmpty) return;
    if (_state.capture != CameraCaptureState.idle) {
      _setCapture(CameraCaptureState.idle, clearError: true);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cameraEvents?.cancel();
    _cameraEvents = null;
    _failActive(
      CameraErrorCodes.disposed,
      'camera pipeline disposed',
      recoverable: false,
    );
    _failQueued(CameraErrorCodes.disposed, 'camera pipeline disposed');
    unawaited(camera.disconnect().catchError((_) {}));
    super.dispose();
  }
}

class _CaptureJob {
  final String captureId;
  final int slot;
  final String eventId;
  final String sessionId;
  final Completer<CapturedImage> completer = Completer<CapturedImage>();

  _CaptureJob({
    required this.captureId,
    required this.slot,
    required this.eventId,
    required this.sessionId,
  });
}
