import 'dart:typed_data';

/// Reads the EXIF orientation tag from a JPEG without modifying the bytes.
///
/// Returns 1 when the tag is absent/invalid. Values 5-8 swap the effective
/// width and height; 2-4 preserve dimensions but imply mirroring/180-degree
/// display, which Flutter's image codec/print compositor apply.
class ExifOrientation {
  const ExifOrientation._();

  static bool swapsDimensions(int orientation) =>
      orientation >= 5 && orientation <= 8;

  static int readJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;
    var i = 2;
    while (i + 3 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) return 1;
      final marker = bytes[i++];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (marker == 0xD9) return 1;
      if (i + 1 >= bytes.length) return 1;
      final length = (bytes[i] << 8) | bytes[i + 1];
      if (length < 2 || i + length > bytes.length) return 1;
      if (marker == 0xE1) {
        final segment = i + 2;
        final segmentEnd = i + length;
        if (segment + 6 <= segmentEnd &&
            bytes[segment] == 0x45 && // E
            bytes[segment + 1] == 0x78 && // x
            bytes[segment + 2] == 0x69 && // i
            bytes[segment + 3] == 0x66 && // f
            bytes[segment + 4] == 0x00 &&
            bytes[segment + 5] == 0x00) {
          final result = _readTiffOrientation(bytes, segment + 6, segmentEnd);
          if (result != null) return result;
        }
      }
      // The SOF marker appears after APP1/APP0 in normal camera JPEGs, but
      // continue scanning harmless segments until SOF/EOI.
      i += length;
    }
    return 1;
  }

  static int? _readTiffOrientation(Uint8List bytes, int tiff, int end) {
    if (tiff + 8 > end) return null;
    final isLittle = bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49;
    final isBig = bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D;
    if (!isLittle && !isBig) return null;

    int u16(int offset) {
      if (offset + 2 > end) throw RangeError('u16');
      return isLittle
          ? (bytes[offset] | (bytes[offset + 1] << 8))
          : ((bytes[offset] << 8) | bytes[offset + 1]);
    }

    int u32(int offset) {
      if (offset + 4 > end) throw RangeError('u32');
      return isLittle
          ? (bytes[offset] |
                (bytes[offset + 1] << 8) |
                (bytes[offset + 2] << 16) |
                (bytes[offset + 3] << 24))
          : ((bytes[offset] << 24) |
                (bytes[offset + 1] << 16) |
                (bytes[offset + 2] << 8) |
                bytes[offset + 3]);
    }

    try {
      if (u16(tiff + 2) != 42) return null;
      final ifdOffset = u32(tiff + 4);
      final ifd = tiff + ifdOffset;
      if (ifd + 2 > end) return null;
      final count = u16(ifd);
      for (var n = 0; n < count; n++) {
        final entry = ifd + 2 + n * 12;
        if (entry + 12 > end) return null;
        final tag = u16(entry);
        if (tag != 0x0112) continue;
        final type = u16(entry + 2);
        final valueCount = u32(entry + 4);
        if (type == 3 && valueCount >= 1) {
          final value = u16(entry + 8);
          if (value >= 1 && value <= 8) return value;
        }
        return null;
      }
    } on RangeError {
      return null;
    }
    return null;
  }

  static (int, int) effectiveDimensions(
    int width,
    int height,
    int orientation,
  ) {
    return swapsDimensions(orientation) ? (height, width) : (width, height);
  }
}
