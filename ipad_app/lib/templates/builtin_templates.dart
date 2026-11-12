import 'template_models.dart';

abstract final class BuiltinTemplates {
  /// Must match the Windows Bridge `strip_2x6_3up_v1` geometry exactly.
  static const defaultStrip = PhotoTemplate(
    id: 'strip_2x6_3up_v1',
    name: 'Classic 2×6 Duo',
    description:
        'Two identical 2×6 strips on one 4×6 sheet. Event-safe default.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFFFFFFF,
    repeatX: 2,
    panelWidth: 600,
    dividerY: 82,
    dividerColor: 0xFF111111,
    slots: [
      TemplateSlot(
        id: 'photo_1',
        imageIndex: 0,
        x: 24,
        y: 100,
        width: 552,
        height: 531,
        borderWidth: 2,
      ),
      TemplateSlot(
        id: 'photo_2',
        imageIndex: 1,
        x: 24,
        y: 649,
        width: 552,
        height: 531,
        borderWidth: 2,
      ),
      TemplateSlot(
        id: 'photo_3',
        imageIndex: 2,
        x: 24,
        y: 1198,
        width: 552,
        height: 531,
        borderWidth: 2,
      ),
    ],
    texts: [
      TemplateText(
        id: 'title',
        kind: TemplateTextKind.eventTitle,
        x: 300,
        y: 28,
        fontSize: 30,
      ),
      TemplateText(
        id: 'date',
        kind: TemplateTextKind.eventDate,
        x: 300,
        y: 66,
        fontSize: 20,
      ),
      TemplateText(
        id: 'footer',
        kind: TemplateTextKind.literal,
        text: 'TERABOOTH',
        x: 300,
        y: 1770,
        fontSize: 18,
      ),
    ],
  );

  static const collage = PhotoTemplate(
    id: 'collage_4x6_v1',
    name: 'Editorial Collage',
    description: 'One large hero portrait with two supporting frames on cream.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFF2E8D8,
    slots: [
      TemplateSlot(
        id: 'hero',
        imageIndex: 0,
        x: 78,
        y: 150,
        width: 1044,
        height: 640,
        borderWidth: 6,
        borderColor: 0xFFF2E8D8,
      ),
      TemplateSlot(
        id: 'left',
        imageIndex: 1,
        x: 78,
        y: 830,
        width: 500,
        height: 660,
        borderWidth: 6,
        borderColor: 0xFFF2E8D8,
      ),
      TemplateSlot(
        id: 'right',
        imageIndex: 2,
        x: 622,
        y: 830,
        width: 500,
        height: 660,
        borderWidth: 6,
        borderColor: 0xFFF2E8D8,
      ),
    ],
    texts: [
      TemplateText(
        id: 'title',
        kind: TemplateTextKind.eventTitle,
        x: 600,
        y: 58,
        fontSize: 38,
        color: 0xFF1A1A1A,
      ),
      TemplateText(
        id: 'date',
        kind: TemplateTextKind.eventDate,
        x: 600,
        y: 106,
        fontSize: 20,
        color: 0xFF5C5246,
      ),
      TemplateText(
        id: 'footer',
        kind: TemplateTextKind.literal,
        text: 'TERABOOTH',
        x: 600,
        y: 1760,
        fontSize: 18,
        color: 0xFF5C5246,
      ),
    ],
  );

  static const minimal = PhotoTemplate(
    id: 'minimal_4x6_v1',
    name: 'Minimal Stack',
    description: 'Three full-width frames with generous white space.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFFFFFFF,
    slots: [
      TemplateSlot(
        id: 'photo_1',
        imageIndex: 0,
        x: 100,
        y: 100,
        width: 1000,
        height: 500,
        borderWidth: 1,
        borderColor: 0xFFE6E1D8,
      ),
      TemplateSlot(
        id: 'photo_2',
        imageIndex: 1,
        x: 100,
        y: 650,
        width: 1000,
        height: 500,
        borderWidth: 1,
        borderColor: 0xFFE6E1D8,
      ),
      TemplateSlot(
        id: 'photo_3',
        imageIndex: 2,
        x: 100,
        y: 1200,
        width: 1000,
        height: 500,
        borderWidth: 1,
        borderColor: 0xFFE6E1D8,
      ),
    ],
    texts: [
      TemplateText(
        id: 'title',
        kind: TemplateTextKind.eventTitle,
        x: 600,
        y: 38,
        fontSize: 26,
        color: 0xFF1A1A1A,
      ),
      TemplateText(
        id: 'date',
        kind: TemplateTextKind.eventDate,
        x: 600,
        y: 72,
        fontSize: 16,
        color: 0xFF7A746C,
      ),
      TemplateText(
        id: 'footer',
        kind: TemplateTextKind.literal,
        text: 'TERABOOTH',
        x: 600,
        y: 1760,
        fontSize: 14,
        color: 0xFFA09A90,
      ),
    ],
  );

  static const all = [defaultStrip, collage, minimal];

  static PhotoTemplate byId(String id) => all.firstWhere(
    (template) => template.id == id,
    orElse: () => defaultStrip,
  );

  /// Count-specific layouts. Kept separate from [all] so the existing
  /// three-photo template gallery and contract remain unchanged.
  static const solo = PhotoTemplate(
    id: 'solo_4x6_v1',
    name: 'Single Portrait',
    description: 'One full-frame portrait on a 4×6 sheet.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFFFFFFF,
    slots: [
      TemplateSlot(
        id: 'photo_1',
        imageIndex: 0,
        x: 70,
        y: 210,
        width: 1060,
        height: 1230,
        borderWidth: 2,
      ),
    ],
    texts: [
      TemplateText(
        id: 'title',
        kind: TemplateTextKind.eventTitle,
        x: 600,
        y: 70,
        fontSize: 38,
      ),
      TemplateText(
        id: 'date',
        kind: TemplateTextKind.eventDate,
        x: 600,
        y: 120,
        fontSize: 22,
      ),
      TemplateText(
        id: 'footer',
        kind: TemplateTextKind.literal,
        text: 'TERABOOTH',
        x: 600,
        y: 1740,
        fontSize: 18,
      ),
    ],
  );

  static const duo = PhotoTemplate(
    id: 'duo_4x6_v1',
    name: 'Duo Stack',
    description: 'Two large portraits stacked on a 4×6 sheet.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFFFFFFF,
    slots: [
      TemplateSlot(
        id: 'photo_1',
        imageIndex: 0,
        x: 70,
        y: 190,
        width: 1060,
        height: 650,
        borderWidth: 2,
      ),
      TemplateSlot(
        id: 'photo_2',
        imageIndex: 1,
        x: 70,
        y: 900,
        width: 1060,
        height: 650,
        borderWidth: 2,
      ),
    ],
    texts: [
      TemplateText(
        id: 'title',
        kind: TemplateTextKind.eventTitle,
        x: 600,
        y: 66,
        fontSize: 34,
      ),
      TemplateText(
        id: 'date',
        kind: TemplateTextKind.eventDate,
        x: 600,
        y: 112,
        fontSize: 20,
      ),
      TemplateText(
        id: 'footer',
        kind: TemplateTextKind.literal,
        text: 'TERABOOTH',
        x: 600,
        y: 1740,
        fontSize: 18,
      ),
    ],
  );

  static const grid = PhotoTemplate(
    id: 'grid_4x6_v1',
    name: 'Four Grid',
    description: 'Four square portraits in a clean 2×2 grid.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFFFFFFF,
    slots: [
      TemplateSlot(
        id: 'photo_1',
        imageIndex: 0,
        x: 70,
        y: 190,
        width: 510,
        height: 610,
        borderWidth: 2,
      ),
      TemplateSlot(
        id: 'photo_2',
        imageIndex: 1,
        x: 620,
        y: 190,
        width: 510,
        height: 610,
        borderWidth: 2,
      ),
      TemplateSlot(
        id: 'photo_3',
        imageIndex: 2,
        x: 70,
        y: 880,
        width: 510,
        height: 610,
        borderWidth: 2,
      ),
      TemplateSlot(
        id: 'photo_4',
        imageIndex: 3,
        x: 620,
        y: 880,
        width: 510,
        height: 610,
        borderWidth: 2,
      ),
    ],
    texts: [
      TemplateText(
        id: 'title',
        kind: TemplateTextKind.eventTitle,
        x: 600,
        y: 66,
        fontSize: 34,
      ),
      TemplateText(
        id: 'date',
        kind: TemplateTextKind.eventDate,
        x: 600,
        y: 112,
        fontSize: 20,
      ),
      TemplateText(
        id: 'footer',
        kind: TemplateTextKind.literal,
        text: 'TERABOOTH',
        x: 600,
        y: 1740,
        fontSize: 18,
      ),
    ],
  );

  static const precomposed = PhotoTemplate(
    id: 'precomposed_4x6_v1',
    name: 'Canva Photo Strip',
    description: 'Full-bleed composition generated on the iPad.',
    version: 1,
    canvasWidth: 1200,
    canvasHeight: 1800,
    outputWidth: 1200,
    outputHeight: 1800,
    dpi: 300,
    backgroundColor: 0xFFFFFFFF,
    slots: [
      TemplateSlot(
        id: 'photo_1',
        imageIndex: 0,
        x: 0,
        y: 0,
        width: 1200,
        height: 1800,
      ),
    ],
  );

  static const variants = [solo, duo, grid];

  static PhotoTemplate forPhotoCount(int count, {PhotoTemplate? preferred}) {
    return switch (count.clamp(1, 4)) {
      1 => solo,
      2 => duo,
      4 => grid,
      _ => preferred ?? defaultStrip,
    };
  }
}
