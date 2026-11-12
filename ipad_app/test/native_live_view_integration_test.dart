import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/camera_contract.dart';
import 'package:terabooth_ipad/services/camera_pipeline.dart';
import 'package:terabooth_ipad/services/camera_service.dart';
import 'package:terabooth_ipad/services/native_camera_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

import 'support.dart';

class EventTestCamera extends TestCamera implements CameraEventSource {
  EventTestCamera({required super.bytes});
  final StreamController<CameraAdapterEvent> _events =
      StreamController<CameraAdapterEvent>.broadcast();

  @override
  Stream<CameraAdapterEvent> get parsedEvents => _events.stream;

  void emit(CameraAdapterEvent event) => _events.add(event);

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class LiveTestCamera extends TestCamera implements CameraLiveViewSource {
  LiveTestCamera({required super.bytes});
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();
  bool liveViewStarted = false;
  bool liveViewStopped = false;
  bool disposed = false;

  @override
  Stream<Uint8List> get liveViewFrames => _frames.stream;

  @override
  Future<void> startLiveView() async {
    liveViewStarted = true;
  }

  @override
  Future<void> stopLiveView() async {
    liveViewStopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _frames.close();
  }

  void emitFrame(Uint8List bytes) => _frames.add(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel(CameraChannels.method);

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test(
    'native service starts/stops Live View, discovery and disposes',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call.method);
        if (call.method == CameraMethods.initialize) {
          return {'licensed': true, 'wiredAuthorization': true};
        }
        return null;
      });
      final service = CascableCoreCameraService();
      await service.connect();
      await service.startDiscovery();
      await service.startLiveView();
      await service.stopLiveView();
      await service.disconnect();
      await service.dispose();
      expect(
        calls,
        containsAllInOrder([
          CameraMethods.initialize,
          CameraMethods.connect,
          CameraMethods.startDiscovery,
          CameraMethods.startLiveView,
          CameraMethods.stopLiveView,
          CameraMethods.disconnect,
          CameraMethods.dispose,
        ]),
      );
    },
  );

  test(
    'controller subscribes, exposes a frame and stops on session end',
    () async {
      final temp = await Directory.systemTemp.createTemp('tb_live_view_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final camera = LiveTestCamera(bytes: await loadJpegFixture());
      final controller = BoothController(
        camera: camera,
        storage: StorageService(rootOverride: temp),
        bridge: BridgeClient(baseUrl: 'http://x'),
        countdownDelay: Duration.zero,
        pollInterval: Duration.zero,
      );
      addTearDown(controller.dispose);
      await controller.createEventProfile(
        EventProfile(
          id: 'evt_live',
          title: 'Live',
          date: '14 Nov 2026',
          dateIso: '2026-11-14',
          configuration: const EventConfiguration(
            photoCount: 1,
            countdownSeconds: 0,
          ),
        ),
      );
      await controller.startSession();
      expect(camera.liveViewStarted, isTrue);
      final frame = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
      camera.emitFrame(frame);
      await Future<void>.delayed(Duration.zero);
      expect(controller.liveViewFrame, frame);
      await controller.endSession();
      expect(camera.liveViewStopped, isTrue);
      expect(controller.liveViewFrame, isNull);
    },
  );

  test('native connection loss updates pipeline state', () async {
    final temp = await Directory.systemTemp.createTemp('tb_live_disconnect_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final camera = EventTestCamera(bytes: await loadJpegFixture());
    final controller = BoothController(
      camera: camera,
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
    );
    addTearDown(controller.dispose);
    camera.emit(
      const CameraAdapterEvent(
        type: 'connection',
        state: 'disconnected',
        message: 'USB unplugged',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.connectionState, CameraConnectionState.failed);
  });

  test('controller disposes native adapter resources', () async {
    final temp = await Directory.systemTemp.createTemp('tb_live_dispose_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final camera = LiveTestCamera(bytes: await loadJpegFixture());
    final controller = BoothController(
      camera: camera,
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
    );
    controller.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(camera.disposed, isTrue);
  });
}
