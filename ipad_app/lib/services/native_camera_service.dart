import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models.dart';
import 'camera_contract.dart';
import 'camera_service.dart';

/// Bridges to the native iOS camera plugin.
///
/// The native side is a compile-safe stub until CascableCore is integrated.
/// It returns `CAMERA_SDK_MISSING` rather than faking a capture.
class NativeCameraService
    implements CameraService, CameraLiveViewSource, CameraEventSource {
  static const MethodChannel _channel = MethodChannel(CameraChannels.method);
  static const EventChannel _eventChannel = EventChannel(CameraChannels.events);
  late final Stream<Map<String, dynamic>> _events = _eventChannel
      .receiveBroadcastStream()
      .map((event) => (event as Map).cast<String, dynamic>())
      .asBroadcastStream();

  @override
  String get name => 'Canon EOS 60D (CascableCore)';

  @override
  bool get isSimulated => false;

  @override
  Future<void> connect() async {
    final init = await initialize();
    if (init == null || init['licensed'] != true) {
      throw StateError('CascableCore licence is not available');
    }
    await _channel.invokeMethod<void>(CameraMethods.connect);
  }

  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod<void>(CameraMethods.disconnect);
  }

  @override
  Future<CapturedImage> capture({String? captureId}) async {
    final map = await _channel.invokeMapMethod<String, dynamic>(
      CameraMethods.capture,
      {CameraPayloadKeys.captureId: captureId},
    );
    if (map == null) throw StateError('camera returned no image');
    final b64 = map[CameraPayloadKeys.bytes] as String?;
    final path = map[CameraPayloadKeys.path] as String?;
    final Uint8List bytes;
    if (b64 != null) {
      bytes = Uint8List.fromList(base64Decode(b64));
    } else if (path != null) {
      bytes = await File(path).readAsBytes();
    } else {
      throw StateError('camera returned no bytes or path');
    }
    final width = (map[CameraPayloadKeys.width] as num?)?.toInt() ?? 0;
    final height = (map[CameraPayloadKeys.height] as num?)?.toInt() ?? 0;
    final returnedCaptureId =
        map[CameraPayloadKeys.captureId] as String? ?? captureId;
    return CapturedImage(
      id:
          returnedCaptureId ??
          'native_${DateTime.now().microsecondsSinceEpoch}',
      bytes: bytes,
      width: width,
      height: height,
      capturedAt: DateTime.now(),
      captureId: returnedCaptureId,
    );
  }

  Future<Map<String, dynamic>?> initialize() async {
    return _channel.invokeMapMethod<String, dynamic>(CameraMethods.initialize);
  }

  Future<Map<String, dynamic>?> status() async {
    return _channel.invokeMapMethod<String, dynamic>(CameraMethods.status);
  }

  /// Native state/capture events. A single broadcast subscription is shared by
  /// the event and Live View consumers.
  Stream<Map<String, dynamic>> get events => _events;

  @override
  Stream<CameraAdapterEvent> get parsedEvents =>
      events.map(CameraAdapterEvent.fromMap);

  Future<void> startDiscovery() async {
    await _channel.invokeMethod<void>(CameraMethods.startDiscovery);
  }

  Future<void> stopDiscovery() async {
    await _channel.invokeMethod<void>(CameraMethods.stopDiscovery);
  }

  @override
  Future<void> startLiveView() async {
    await _channel.invokeMethod<void>(CameraMethods.startLiveView);
  }

  @override
  Future<void> stopLiveView() async {
    await _channel.invokeMethod<void>(CameraMethods.stopLiveView);
  }

  @override
  Stream<Uint8List> get liveViewFrames => parsedEvents
      .where((event) => event.isLiveViewFrame)
      .map((event) => Uint8List.fromList(base64Decode(event.bytes ?? '')));

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod<void>(CameraMethods.dispose);
  }
}

/// Dart-side selection for the native CascableCore adapter.
/// Delegates to the existing channel and does not create a second camera
/// state machine. It is not the default service.
class CascableCameraService
    implements CameraService, CameraLiveViewSource, CameraEventSource {
  final NativeCameraService native;
  CascableCameraService({NativeCameraService? native})
    : native = native ?? NativeCameraService();

  @override
  String get name => native.name;

  @override
  bool get isSimulated => false;

  @override
  Future<void> connect() => native.connect();

  @override
  Future<void> disconnect() => native.disconnect();

  @override
  Future<CapturedImage> capture({String? captureId}) =>
      native.capture(captureId: captureId);

  Stream<Map<String, dynamic>> get events => native.events;
  @override
  Stream<CameraAdapterEvent> get parsedEvents => native.parsedEvents;

  Future<Map<String, dynamic>?> initialize() => native.initialize();
  Future<void> startDiscovery() => native.startDiscovery();
  Future<void> stopDiscovery() => native.stopDiscovery();
  @override
  Future<void> startLiveView() => native.startLiveView();
  @override
  Future<void> stopLiveView() => native.stopLiveView();
  @override
  Stream<Uint8List> get liveViewFrames => native.liveViewFrames;
  @override
  Future<void> dispose() => native.dispose();
}

/// Exact-name selection class for the iOS CascableCore adapter.
/// It is a thin alias, not a second state machine.
class CascableCoreCameraService extends CascableCameraService {
  CascableCoreCameraService({super.native});
}
