import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terabooth_ipad/services/camera_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('mock camera produces a labelled 1200x1800 image', () async {
    const camera = MockCameraService();
    await camera.connect();
    final image = await camera.capture();
    expect(image.width, 1200);
    expect(image.height, 1800);
    expect(image.bytes.length, greaterThan(1000));
    expect(image.id, startsWith('mock_'));
  });

  test('consecutive mock captures are visually distinct', () async {
    const camera = MockCameraService();
    final first = await camera.capture(captureId: 'cap_a');
    final second = await camera.capture(captureId: 'cap_b');
    expect(listEquals(first.bytes, second.bytes), isFalse);
    expect(first.captureId, 'cap_a');
    expect(second.captureId, 'cap_b');
  });
}
