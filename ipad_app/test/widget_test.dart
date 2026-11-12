import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/screens/welcome_screen.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/camera_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';

void main() {
  testWidgets('welcome screen clearly labels simulated camera', (tester) async {
    final controller = BoothController(
      camera: const MockCameraService(),
      storage: const StorageService(rootOverride: null),
      bridge: BridgeClient(baseUrl: 'http://127.0.0.1:8787'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WelcomeScreen(controller: controller)),
      ),
    );
    expect(find.textContaining('SIMULATED CAMERA'), findsOneWidget);
    expect(find.text('Start Session'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('welcome screen opens the event selector', (tester) async {
    final controller = BoothController(
      camera: const MockCameraService(),
      storage: const StorageService(rootOverride: null),
      bridge: BridgeClient(baseUrl: 'http://127.0.0.1:8787'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WelcomeScreen(controller: controller)),
      ),
    );
    await tester.tap(find.text('Change event'));
    await tester.pumpAndSettle();
    expect(find.text('Select event'), findsOneWidget);
    expect(find.text('Create new event'), findsOneWidget);
    controller.dispose();
  });
}
