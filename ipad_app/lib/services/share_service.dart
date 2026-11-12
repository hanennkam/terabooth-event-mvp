import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Thin wrapper around the native iPadOS share sheet. No custom AirDrop
/// protocol or recipient discovery is implemented.
class ShareService {
  const ShareService();

  Future<void> shareBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: filename)],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
