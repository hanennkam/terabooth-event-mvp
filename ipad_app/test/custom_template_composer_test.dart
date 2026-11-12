import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/models.dart';
import 'package:terabooth_ipad/services/custom_template_composer.dart';

import 'support.dart';

Future<Uint8List> _artwork() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 600, 900),
    ui.Paint()..color = const ui.Color(0x00000000),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 600, 60),
    ui.Paint()..color = const ui.Color(0xFFC8A464),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 900);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom composition preserves originals and returns 4x6 PNG', () async {
    final jpeg = await loadJpegFixture();
    final originalHash = sha256.convert(jpeg).toString();
    final photos = [
      CapturedImage(
        id: 'p1',
        bytes: jpeg,
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
        captureId: 'p1',
      ),
      CapturedImage(
        id: 'p2',
        bytes: jpeg,
        width: 1200,
        height: 1800,
        capturedAt: DateTime.now(),
        captureId: 'p2',
      ),
    ];
    final design = EventCustomTemplate(
      artworkPath: 'unused.png',
      artworkWidth: 600,
      artworkHeight: 900,
      layerMode: TemplateLayerMode.overlay,
      slots: const [
        CustomPhotoSlot(
          id: 's1',
          captureOrder: 0,
          x: .08,
          y: .08,
          width: .84,
          height: .35,
        ),
        CustomPhotoSlot(
          id: 's2',
          captureOrder: 1,
          x: .08,
          y: .48,
          width: .84,
          height: .35,
          contain: true,
          zoom: 1.2,
          offsetX: .1,
        ),
      ],
    );
    final composed = await CustomTemplateComposer().compose(
      design: design,
      artworkBytes: await _artwork(),
      photos: photos,
    );
    final codec = await ui.instantiateImageCodec(composed);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 1200);
    expect(frame.image.height, 1800);
    frame.image.dispose();
    codec.dispose();
    expect(sha256.convert(jpeg).toString(), originalHash);
  });

  test('background artwork mode composes without mutating slot data', () async {
    final jpeg = await loadJpegFixture();
    final design = EventCustomTemplate(
      artworkPath: 'unused.png',
      layerMode: TemplateLayerMode.background,
      slots: const [
        CustomPhotoSlot(
          id: 's1',
          captureOrder: 0,
          x: .1,
          y: .1,
          width: .8,
          height: .8,
        ),
      ],
    );
    final before = design.slots.first.toJson();
    final composed = await CustomTemplateComposer().compose(
      design: design,
      artworkBytes: await _artwork(),
      photos: [
        CapturedImage(
          id: 'p1',
          bytes: jpeg,
          width: 1200,
          height: 1800,
          capturedAt: DateTime.now(),
          captureId: 'p1',
        ),
      ],
    );
    expect(composed, isNotEmpty);
    expect(design.slots.first.toJson(), before);
  });
}
