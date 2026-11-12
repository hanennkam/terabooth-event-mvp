import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/services/camera_contract.dart';
import 'package:terabooth_ipad/services/native_camera_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(CameraChannels.method);

  setUpAll(() async {
    jpeg = await loadJpegFixture();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  void installHandler(Future<dynamic> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(methodChannel, handler);
  }

  group('serializable native event mapping', () {
    test('maps discovery events', () {
      final event = CameraAdapterEvent.fromMap({
        'type': 'discovery',
        'id': 'serial-1',
        'model': 'Canon EOS 60D',
        'manufacturer': 'Canon Inc.',
        'transport': 'usb',
        'state': 'discovered',
      });
      expect(event.isDiscovery, isTrue);
      expect(event.cameraId, 'serial-1');
      expect(event.model, 'Canon EOS 60D');
      expect(event.transport, 'usb');
      expect(event.state, 'discovered');
    });

    test('maps connection states', () {
      for (final state in [
        'connecting',
        'connected',
        'disconnected',
        'failed',
      ]) {
        final event = CameraAdapterEvent.fromMap({
          'type': 'connection',
          'state': state,
          'id': 'serial-1',
        });
        expect(event.isConnection, isTrue);
        expect(event.state, state);
      }
    });

    test('maps live view lifecycle and frame payloads', () {
      final started = CameraAdapterEvent.fromMap({
        'type': 'connection',
        'state': 'liveViewStarted',
      });
      final frame = CameraAdapterEvent.fromMap({
        'type': 'liveViewFrame',
        'width': 1056,
        'height': 704,
        'bytes': 'AA==',
      });
      final stopped = CameraAdapterEvent.fromMap({
        'type': 'connection',
        'state': 'liveViewStopped',
      });
      expect(started.state, 'liveViewStarted');
      expect(frame.isLiveViewFrame, isTrue);
      expect(frame.width, 1056);
      expect(frame.height, 704);
      expect(frame.bytes, 'AA==');
      expect(stopped.state, 'liveViewStopped');
    });

    test('shutter sent is distinct from original receipt', () {
      final sent = CameraAdapterEvent.fromMap({
        'type': 'capture',
        'captureId': 'cap_1',
        'state': 'shutterSent',
      });
      final received = CameraAdapterEvent.fromMap({
        'type': 'capture',
        'captureId': 'cap_1',
        'state': 'originalReceived',
        'byteCount': 4096,
      });
      expect(sent.isCapture, isTrue);
      expect(sent.state, 'shutterSent');
      expect(received.state, 'originalReceived');
      expect(received.captureId, 'cap_1');
      expect(received.byteCount, 4096);
    });

    test('maps transfer failure and disconnect errors', () {
      final transfer = CameraAdapterEvent.fromMap({
        'type': 'capture',
        'captureId': 'cap_1',
        'state': 'failed',
        'code': CameraErrorCodes.transferFailed,
        'message': 'camera did not offer an original image',
      });
      final disconnect = CameraAdapterEvent.fromMap({
        'type': 'capture',
        'captureId': 'cap_1',
        'state': 'failed',
        'code': CameraErrorCodes.disconnected,
      });
      expect(transfer.code, CameraErrorCodes.transferFailed);
      expect(disconnect.code, CameraErrorCodes.disconnected);
    });
  });

  group('NativeCameraService boundary', () {
    test('initializes, connects and preserves capture ID plus bytes', () async {
      final calls = <String>[];
      installHandler((call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'initialize':
            return {'licensed': true, 'platformSupportsWiredCameras': true};
          case 'connect':
            return null;
          case 'capture':
            final args = (call.arguments as Map).cast<String, dynamic>();
            return {
              'captureId': args['captureId'],
              'bytes': base64Encode(jpeg),
              'width': 1800,
              'height': 1200,
            };
        }
        return null;
      });

      final service = NativeCameraService();
      await service.connect();
      final image = await service.capture(captureId: 'cap_test_1');
      expect(calls, containsAllInOrder(['initialize', 'connect', 'capture']));
      expect(image.captureId, 'cap_test_1');
      expect(image.id, 'cap_test_1');
      expect(image.bytes, jpeg);
      expect(image.width, 1800);
      expect(image.height, 1200);
    });

    test('rejects a missing licence before connect', () async {
      installHandler((call) async {
        if (call.method == 'initialize') {
          return {'licensed': false};
        }
        return null;
      });
      final service = NativeCameraService();
      await expectLater(service.connect(), throwsA(isA<StateError>()));
    });

    test('rejects a native capture with no bytes or path', () async {
      installHandler((call) async {
        switch (call.method) {
          case 'initialize':
            return {'licensed': true};
          case 'capture':
            return {'captureId': 'cap_no_image'};
        }
        return null;
      });
      final service = NativeCameraService();
      await service.connect();
      await expectLater(
        service.capture(captureId: 'cap_no_image'),
        throwsA(isA<StateError>()),
      );
    });

    test('CascableCameraService delegates to the native boundary', () async {
      installHandler((call) async {
        if (call.method == 'initialize') return {'licensed': true};
        return null;
      });
      final service = CascableCoreCameraService();
      expect(service.name, 'Canon EOS 60D (CascableCore)');
      expect(service.isSimulated, isFalse);
      await service.connect();
      await service.disconnect();
    });
  });
}
