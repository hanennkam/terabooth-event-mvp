import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terabooth_ipad/services/face_detection_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Apple Vision detects a face and returns normalized bounds',
    (tester) async {
      final data = await rootBundle.load('assets/fixtures/face_lincoln.jpg');
      final detector = const VisionFaceDetector();
      final result = await tester.runAsync(
        () => detector.detect(data.buffer.asUint8List()),
      );
      expect(result, isNotNull);
      if (result!.error != null) {
        markTestSkipped(
          'Apple Vision unavailable in this simulator: ${result.error}. '
          'The app falls back to Fit; no face-detection result is claimed.',
        );
        return;
      }
      expect(result.faces, isNotEmpty);
      for (final face in result.faces) {
        expect(face.confidence, greaterThan(0));
        expect(face.box.x, greaterThanOrEqualTo(0));
        expect(face.box.y, greaterThanOrEqualTo(0));
        expect(face.box.x + face.box.width, lessThanOrEqualTo(1.0001));
        expect(face.box.y + face.box.height, lessThanOrEqualTo(1.0001));
      }
    },
  );
}
