import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final probeFile = File('ios/Runner/CascableCoreDemoProbe.swift');
  final appDelegate = File('ios/Runner/AppDelegate.swift');

  test('demo probe contains no shutter, capture or transfer APIs', () {
    final source = probeFile.readAsStringSync();
    expect(source, isNot(contains('invokeOneShot')));
    expect(source, isNot(contains('addCameraInitiatedTransferHandler')));
    expect(source, isNot(contains('executeTransfer')));
    expect(source, isNot(contains('CascableCoreSimulatedCamera')));
    expect(source, isNot(contains('SimulatedCameraConfiguration')));
    expect(source, isNot(contains('setEnabled(true')));
  });

  test(
    'demo probe is USB-only and simulated plugin is explicitly disabled',
    () {
      final source = probeFile.readAsStringSync();
      expect(source, contains('discoveryMode = .usbOnly'));
      expect(source, contains('setEnabled(false'));
      expect(source, contains('USB Preflight'));
    },
  );

  test('launch only prepares the probe and does not discover or connect', () {
    final app = appDelegate.readAsStringSync();
    final source = probeFile.readAsStringSync();
    expect(
      app,
      contains('CascableCoreDemoProbe.shared.prepare(licenseApplied:'),
    );
    expect(app, isNot(contains('CascableCoreDemoProbe.shared.start(')));
    expect(app, isNot(contains('beginSearching')));
    expect(app, isNot(contains('camera.connect')));

    final prepareStart = source.indexOf('func prepare(');
    expect(prepareStart, greaterThanOrEqualTo(0));
    final prepareEnd = source.indexOf(
      '// MARK: - Explicit user actions',
      prepareStart,
    );
    expect(prepareEnd, greaterThan(prepareStart));
    final prepareBody = source.substring(prepareStart, prepareEnd);
    expect(prepareBody, isNot(contains('beginSearching')));
    expect(prepareBody, isNot(contains('camera.connect')));
    expect(prepareBody, isNot(contains('startLiveView')));
  });

  test('preflight actions are explicitly operator initiated', () {
    final source = probeFile.readAsStringSync();
    expect(source, contains('func startDiscovery()'));
    expect(source, contains('func connect()'));
    expect(source, contains('func readPropertiesAndStorage()'));
    expect(source, contains('func startLiveView()'));
    expect(source, contains('func stopLiveView()'));
    expect(source, contains('func disconnect()'));
    expect(source, contains('1. USB discovery'));
    expect(source, contains('Optional: start Live View'));
  });
}
