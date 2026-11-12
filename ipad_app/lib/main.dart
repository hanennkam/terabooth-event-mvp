import 'dart:async';

import 'package:flutter/material.dart';

import 'booth_controller.dart';
import 'screens/capture_screen.dart';
import 'screens/print_screen.dart';
import 'screens/review_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/bridge_client.dart';
import 'services/bridge_token_store.dart';
import 'services/camera_service.dart';
import 'services/native_camera_service.dart';
import 'services/storage_service.dart';
import 'theme/tb_theme.dart';

void main() {
  runApp(const TeraboothApp());
}

class TeraboothApp extends StatefulWidget {
  const TeraboothApp({super.key});

  @override
  State<TeraboothApp> createState() => _TeraboothAppState();
}

class _TeraboothAppState extends State<TeraboothApp>
    with WidgetsBindingObserver {
  late final BoothController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const useNativeCamera = bool.fromEnvironment(
      'USE_NATIVE_CAMERA',
      defaultValue: false,
    );
    const bridgeUrl = String.fromEnvironment(
      'TERABOOTH_BRIDGE_URL',
      defaultValue: 'http://192.168.8.192:8787',
    );
    const apiToken = String.fromEnvironment(
      'TERABOOTH_API_TOKEN',
      defaultValue: '',
    );
    controller = BoothController(
      camera: useNativeCamera
          ? NativeCameraService()
          : const MockCameraService(),
      storage: const StorageService(),
      bridge: BridgeClient(
        baseUrl: bridgeUrl,
        token: apiToken.isEmpty ? null : apiToken,
      ),
      bridgeTokenStore: KeychainBridgeTokenStore(),
    );
    unawaited(
      controller.loadEvents().then((_) async {
        await controller.loadRestorableSession();
        await controller.loadSubmittedJob();
      }),
    );
    unawaited(controller.loadSettings());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.handleAppBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      controller.handleAppForegrounded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  Widget _screen() {
    switch (controller.phase) {
      case BoothPhase.idle:
        return WelcomeScreen(controller: controller);
      case BoothPhase.capturing:
        return CaptureScreen(controller: controller);
      case BoothPhase.review:
        return ReviewScreen(controller: controller);
      case BoothPhase.uploading:
      case BoothPhase.printing:
      case BoothPhase.done:
      case BoothPhase.error:
        return PrintScreen(controller: controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Terabooth',
      debugShowCheckedModeBanner: false,
      theme: tbTheme(),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(body: _screen()),
      ),
    );
  }
}
