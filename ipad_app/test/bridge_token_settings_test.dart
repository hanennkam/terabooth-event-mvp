import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/bridge_token_store.dart';
import 'package:terabooth_ipad/services/camera_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

class FakeBridgeTokenStore implements BridgeTokenStore {
  FakeBridgeTokenStore([this.value]);
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FakeBridgeTokenStore tokens;
  late BoothController controller;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tb_bridge_token_');
    tokens = FakeBridgeTokenStore('token-from-keychain');
    controller = BoothController(
      camera: const MockCameraService(),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://192.168.8.50:8787'),
      bridgeTokenStore: tokens,
    );
    await controller.storage.writeSettings({
      'bridge_url': 'http://192.168.8.192:8787',
    });
  });

  tearDown(() async {
    controller.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('loads stored URL and Keychain token separately', () async {
    await controller.loadSettings();
    expect(controller.bridge.baseUrl, 'http://192.168.8.192:8787');
    expect(controller.bridge.token, 'token-from-keychain');
  });

  test('saves and clears token without changing URL', () async {
    await controller.loadSettings();
    await controller.saveBridgeToken('new-token');
    expect(tokens.value, 'new-token');
    expect(controller.bridge.token, 'new-token');
    expect(controller.bridge.baseUrl, 'http://192.168.8.192:8787');

    await controller.clearBridgeToken();
    expect(tokens.value, isNull);
    expect(controller.bridge.token, isNull);
    expect(controller.bridge.baseUrl, 'http://192.168.8.192:8787');
  });

  test('saving URL preserves the existing token', () async {
    await controller.loadSettings();
    await controller.saveBridgeUrl('http://192.168.8.200:8787');
    expect(controller.bridge.baseUrl, 'http://192.168.8.200:8787');
    expect(controller.bridge.token, 'token-from-keychain');
  });
}
