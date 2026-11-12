/// SDK-independent camera channel contract.
///
/// CascableCore types stay inside the future Swift adapter; Dart only sees
/// these method/event names and payload keys.
class CameraChannels {
  const CameraChannels._();
  static const String method = 'com.terabooth/camera';
  static const String events = 'com.terabooth/camera/events';
}

class CameraMethods {
  const CameraMethods._();
  static const String initialize = 'initialize';
  static const String startDiscovery = 'startDiscovery';
  static const String stopDiscovery = 'stopDiscovery';
  static const String connect = 'connect';
  static const String disconnect = 'disconnect';
  static const String capture = 'capture';
  static const String status = 'status';
  static const String startLiveView = 'startLiveView';
  static const String stopLiveView = 'stopLiveView';
  static const String dispose = 'dispose';
}

class CameraEventTypes {
  const CameraEventTypes._();
  static const String discovery = 'discovery';
  static const String connection = 'connection';
  static const String capture = 'capture';
  static const String liveViewFrame = 'liveViewFrame';
  static const String error = 'error';
}

class CameraPayloadKeys {
  const CameraPayloadKeys._();
  static const String captureId = 'captureId';
  static const String requestId = 'requestId';
  static const String bytes = 'bytes';
  static const String path = 'path';
  static const String width = 'width';
  static const String height = 'height';
  static const String id = 'id';
  static const String state = 'state';
  static const String transport = 'transport';
}

class CameraErrorCodes {
  const CameraErrorCodes._();
  static const String sdkMissing = 'CAMERA_SDK_MISSING';
  static const String licenseMissing = 'CAMERA_LICENSE_MISSING';
  static const String permissionDenied = 'CAMERA_PERMISSION_DENIED';
  static const String notFound = 'CAMERA_NOT_FOUND';
  static const String connectFailed = 'CAMERA_CONNECT_FAILED';
  static const String connectTimeout = 'CAMERA_CONNECT_TIMEOUT';
  static const String disconnected = 'CAMERA_DISCONNECTED';
  static const String notConnected = 'CAMERA_NOT_CONNECTED';
  static const String captureInProgress = 'CAPTURE_IN_PROGRESS';
  static const String duplicateCapture = 'DUPLICATE_CAPTURE';
  static const String duplicateImage = 'DUPLICATE_IMAGE_DELIVERY';
  static const String captureTimeout = 'CAPTURE_TIMEOUT';
  static const String captureFailed = 'CAPTURE_FAILED';
  static const String captureIdMismatch = 'CAPTURE_ID_MISMATCH';
  static const String transferFailed = 'TRANSFER_FAILED';
  static const String invalidImage = 'INVALID_IMAGE';
  static const String unsupportedImage = 'UNSUPPORTED_IMAGE_FORMAT';
  static const String storageFailed = 'STORAGE_FAILED';
  static const String appBackgrounded = 'APP_BACKGROUNDED';
  static const String disposed = 'PIPELINE_DISPOSED';
  static const String unsupported = 'UNSUPPORTED';
}

/// Serializable native event shape. This intentionally has no SDK types.
class CameraAdapterEvent {
  final String type;
  final String? state;
  final String? cameraId;
  final String? model;
  final String? manufacturer;
  final String? transport;
  final String? captureId;
  final String? code;
  final String? message;
  final int? width;
  final int? height;
  final String? bytes;
  final int? byteCount;

  const CameraAdapterEvent({
    required this.type,
    this.state,
    this.cameraId,
    this.model,
    this.manufacturer,
    this.transport,
    this.captureId,
    this.code,
    this.message,
    this.width,
    this.height,
    this.bytes,
    this.byteCount,
  });

  factory CameraAdapterEvent.fromMap(Map<String, dynamic> map) {
    return CameraAdapterEvent(
      type: map['type'] as String? ?? 'unknown',
      state: map['state'] as String?,
      cameraId: map['id'] as String?,
      model: map['model'] as String?,
      manufacturer: map['manufacturer'] as String?,
      transport: map['transport'] as String?,
      captureId: map['captureId'] as String?,
      code: map['code'] as String?,
      message: map['message'] as String?,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      bytes: map['bytes'] as String?,
      byteCount: (map['byteCount'] as num?)?.toInt(),
    );
  }

  bool get isDiscovery => type == CameraEventTypes.discovery;
  bool get isConnection => type == CameraEventTypes.connection;
  bool get isCapture => type == CameraEventTypes.capture;
  bool get isLiveViewFrame => type == CameraEventTypes.liveViewFrame;
}
