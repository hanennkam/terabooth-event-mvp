import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/booth_controller.dart';
import 'package:terabooth_ipad/crop/crop_models.dart';
import 'package:terabooth_ipad/crop/crop_planner.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/screens/crop_editor_screen.dart';
import 'package:terabooth_ipad/screens/template_gallery_screen.dart';
import 'package:terabooth_ipad/services/bridge_client.dart';
import 'package:terabooth_ipad/services/face_detection_service.dart';
import 'package:terabooth_ipad/services/storage_service.dart';
import 'package:terabooth_ipad/templates/builtin_templates.dart';
import 'package:terabooth_ipad/templates/template_models.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List jpeg;
  setUpAll(() async => jpeg = await loadJpegFixture());

  test('default template preserves the established geometry', () {
    final template = BuiltinTemplates.defaultStrip;
    expect(template.id, 'strip_2x6_3up_v1');
    expect(template.version, 1);
    expect(template.canvasWidth, 1200);
    expect(template.canvasHeight, 1800);
    expect(template.outputWidth, 1200);
    expect(template.outputHeight, 1800);
    expect(template.dpi, 300);
    expect(template.repeatX, 2);
    expect(template.panelWidth, 600);
    expect(
      [
        for (final slot in template.slots)
          [slot.x, slot.y, slot.width, slot.height],
      ],
      [
        [24.0, 100.0, 552.0, 531.0],
        [24.0, 649.0, 552.0, 531.0],
        [24.0, 1198.0, 552.0, 531.0],
      ],
    );
    template.validate();
  });

  test('all built-in templates validate and expose three photos', () {
    for (final template in BuiltinTemplates.all) {
      template.validate();
      expect(template.slots, hasLength(3));
      expect(template.outputWidth, 1200);
      expect(template.outputHeight, 1800);
      expect(template.dpi, 300);
    }
  });

  test('invalid template geometry is rejected', () {
    const bad = PhotoTemplate(
      id: 'bad',
      name: 'Bad',
      description: 'Bad',
      version: 1,
      canvasWidth: 100,
      canvasHeight: 100,
      outputWidth: 100,
      outputHeight: 100,
      slots: [
        TemplateSlot(
          id: 'x',
          imageIndex: 0,
          x: 90,
          y: 0,
          width: 50,
          height: 20,
        ),
      ],
    );
    expect(bad.validate, throwsA(isA<TemplateValidationException>()));
  });

  testWidgets('template gallery selects a visually different template', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: const StorageService(rootOverride: null),
      bridge: BridgeClient(baseUrl: 'http://x'),
      faceDetector: const FixtureFaceDetector(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: TemplateGalleryScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.text('Choose a template'), findsOneWidget);
    expect(find.text('Classic 2×6 Duo'), findsOneWidget);
    expect(find.text('Editorial Collage'), findsOneWidget);
    expect(find.text('Minimal Stack'), findsOneWidget);

    await tester.tap(find.text('Editorial Collage'));
    await tester.pump();
    await tester.tap(find.text('Use this template'));
    await tester.pumpAndSettle();
    expect(controller.template.id, 'collage_4x6_v1');
  });

  test('smart crop keeps multiple faces and uses slot aspect', () async {
    final image = CapturedImage(
      id: 'img0',
      bytes: jpeg,
      width: 1200,
      height: 1800,
      capturedAt: DateTime.now(),
    );
    final planner = SmartCropPlanner(
      faceDetector: const FixtureFaceDetector(
        faces: [
          FaceBox(
            box: NormalizedRect(x: 0.22, y: 0.25, width: 0.20, height: 0.22),
            confidence: 0.94,
          ),
          FaceBox(
            box: NormalizedRect(x: 0.58, y: 0.30, width: 0.18, height: 0.20),
            confidence: 0.88,
          ),
        ],
      ),
    );
    final slot = BuiltinTemplates.defaultStrip.slots.first;
    final crop = await planner.plan(
      image: image,
      template: BuiltinTemplates.defaultStrip,
      slot: slot,
    );
    expect(crop.mode, CropMode.smart);
    expect(crop.faceCount, 2);
    expect(crop.rect.x, greaterThanOrEqualTo(0));
    expect(crop.rect.x + crop.rect.width, lessThanOrEqualTo(1.0001));
    expect(crop.rect.y + crop.rect.height, lessThanOrEqualTo(1.0001));
    final aspect =
        (crop.rect.width * image.width) / (crop.rect.height * image.height);
    expect(aspect, closeTo(slot.aspect, 0.02));
    expect(crop.rect.x, lessThanOrEqualTo(0.22));
    expect(crop.rect.x + crop.rect.width, greaterThanOrEqualTo(0.76));
  });

  test(
    'no face, low confidence, boundary and detector failure fall back to fit',
    () async {
      final image = CapturedImage(
        id: 'img0',
        bytes: jpeg,
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
      );
      final slot = BuiltinTemplates.defaultStrip.slots.first;
      Future<CropDecision> plan(FixtureFaceDetector detector) =>
          SmartCropPlanner(faceDetector: detector).plan(
            image: image,
            template: BuiltinTemplates.defaultStrip,
            slot: slot,
          );

      expect((await plan(const FixtureFaceDetector())).mode, CropMode.fit);
      expect(
        (await plan(
          const FixtureFaceDetector(
            faces: [
              FaceBox(
                box: NormalizedRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
                confidence: 0.2,
              ),
            ],
          ),
        )).mode,
        CropMode.fit,
      );
      expect(
        (await plan(
          const FixtureFaceDetector(
            faces: [
              FaceBox(
                box: NormalizedRect(x: 0.0, y: 0.2, width: 0.2, height: 0.2),
                confidence: 0.9,
              ),
            ],
          ),
        )).mode,
        CropMode.fit,
      );
      expect(
        (await plan(
          const FixtureFaceDetector(error: 'Vision unavailable'),
        )).mode,
        CropMode.fit,
      );
      expect(
        (await plan(
          const FixtureFaceDetector(error: 'Vision failed'),
        )).fallbackReason,
        isNotNull,
      );
    },
  );

  test('manual crop is normalized and fit is never a crop', () {
    final rect = CropGeometry.manual(
      imageAspect: 2 / 3,
      slotAspect: 552 / 531,
      zoom: 2,
      offsetX: 0.4,
      offsetY: -0.3,
    );
    rect.validate();
    expect(rect.width, lessThan(1));
    expect(rect.height, lessThan(1));
    final fit = CropDecision(
      imageId: 'img0',
      slotId: 'photo_1',
      templateId: 'strip_2x6_3up_v1',
      templateVersion: 1,
      mode: CropMode.fit,
      rect: NormalizedRect.full,
      updatedAt: DateTime.now(),
    );
    fit.validate();
    expect(fit.rect.width, 1);
    expect(fit.rect.height, 1);
    expect(
      () =>
          const NormalizedRect(x: 0.9, y: 0, width: 0.3, height: 1).validate(),
      throwsA(isA<CropValidationException>()),
    );
  });

  test('crop metadata is persisted with immutable original bytes', () async {
    final temp = await Directory.systemTemp.createTemp('terabooth_crop_meta_');
    addTearDown(() => temp.delete(recursive: true));
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
      faceDetector: const FixtureFaceDetector(
        faces: [
          FaceBox(
            box: NormalizedRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
            confidence: 0.95,
          ),
        ],
      ),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.startSession();
    final original = Uint8List.fromList(controller.photos.first.bytes);
    expect(controller.crops, hasLength(3));
    final decision = controller.crops.values.first;
    expect(decision.templateId, controller.template.id);
    expect(decision.mode, CropMode.smart);

    await controller.updateCrop(
      decision.copyWith(mode: CropMode.fit, rect: NormalizedRect.full),
    );
    expect(controller.photos.first.bytes, equals(original));
    final file = await _findSessionJson(temp);
    final decoded = await file.readAsString();
    expect(decoded, contains('crops'));
    expect(decoded, contains('strip_2x6_3up_v1'));
  });

  testWidgets('crop editor exposes smart, fit and manual controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: const StorageService(rootOverride: null),
      bridge: BridgeClient(baseUrl: 'http://x'),
      faceDetector: const FixtureFaceDetector(),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.photos = [
      for (var i = 0; i < 3; i++)
        CapturedImage(
          id: 'cap_$i',
          bytes: jpeg,
          width: 1200,
          height: 1800,
          capturedAt: DateTime.now(),
          captureId: 'cap_$i',
        ),
    ];
    controller.phase = BoothPhase.review;
    await tester.pumpWidget(
      MaterialApp(
        home: CropEditorScreen(controller: controller, photoIndex: 0),
      ),
    );
    await tester.pump();
    expect(find.text('Adjust crop'), findsOneWidget);
    expect(find.text('Smart'), findsOneWidget);
    expect(find.text('Fit'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('Apply crop'), findsOneWidget);
    expect(find.textContaining('Originals never change'), findsOneWidget);
  });

  test('template cannot change after photos exist', () async {
    final temp = await Directory.systemTemp.createTemp(
      'terabooth_template_lock_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final controller = BoothController(
      camera: TestCamera(bytes: jpeg),
      storage: StorageService(rootOverride: temp),
      bridge: BridgeClient(baseUrl: 'http://x'),
      faceDetector: const FixtureFaceDetector(),
      countdownDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.startSession();
    await controller.selectTemplate(BuiltinTemplates.collage);
    expect(controller.template.id, BuiltinTemplates.defaultStrip.id);
  });
}

Future<File> _findSessionJson(Directory root) async {
  await for (final entity in root.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('session.json')) return entity;
  }
  throw StateError('session.json not found');
}
