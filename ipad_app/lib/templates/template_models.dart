import 'dart:ui';

class TemplateValidationException implements Exception {
  final String message;
  const TemplateValidationException(this.message);
  @override
  String toString() => message;
}

enum TemplateTextKind { eventTitle, eventDate, literal }

class TemplateText {
  final String id;
  final TemplateTextKind kind;
  final String text;
  final double x;
  final double y;
  final double fontSize;
  final int color;
  final String align; // left | center | right
  final bool uppercase;

  const TemplateText({
    required this.id,
    required this.kind,
    this.text = '',
    required this.x,
    required this.y,
    this.fontSize = 28,
    this.color = 0xFF111111,
    this.align = 'center',
    this.uppercase = false,
  });
}

class TemplateSlot {
  final String id;
  final int imageIndex;
  final double x;
  final double y;
  final double width;
  final double height;
  final double borderWidth;
  final int borderColor;

  const TemplateSlot({
    required this.id,
    required this.imageIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.borderWidth = 0,
    this.borderColor = 0xFF111111,
  });

  double get aspect => width / height;

  Map<String, dynamic> toJson() => {
    'id': id,
    'image_index': imageIndex,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'border_width': borderWidth,
    'border_color': borderColor,
  };
}

class PhotoTemplate {
  final String id;
  final String name;
  final String description;
  final int version;
  final int canvasWidth;
  final int canvasHeight;
  final int outputWidth;
  final int outputHeight;
  final int dpi;
  final int backgroundColor;
  final int repeatX;
  final double panelWidth;
  final int dividerY;
  final int dividerColor;
  final List<TemplateSlot> slots;
  final List<TemplateText> texts;

  const PhotoTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.outputWidth,
    required this.outputHeight,
    this.dpi = 300,
    this.backgroundColor = 0xFFFFFFFF,
    this.repeatX = 1,
    this.panelWidth = 0,
    this.dividerY = 0,
    this.dividerColor = 0xFF111111,
    required this.slots,
    this.texts = const [],
  });

  double get aspect => canvasWidth / canvasHeight;
  Color get background => Color(backgroundColor);

  /// Default templates repeat the same panel horizontally. The slot list is
  /// the base panel; the renderer repeats it `repeatX` times.
  List<TemplateSlot> get allSlots => slots;

  List<TemplateSlot> slotsForImage(int imageIndex) =>
      slots.where((slot) => slot.imageIndex == imageIndex).toList();

  void validate() {
    if (id.trim().isEmpty) {
      throw const TemplateValidationException('template id is required');
    }
    if (version < 1) {
      throw const TemplateValidationException('template version must be >= 1');
    }
    if (canvasWidth <= 0 ||
        canvasHeight <= 0 ||
        outputWidth <= 0 ||
        outputHeight <= 0) {
      throw const TemplateValidationException(
        'template dimensions must be positive',
      );
    }
    if (repeatX < 1 || repeatX > 2) {
      throw const TemplateValidationException('repeatX must be 1 or 2');
    }
    if (repeatX > 1 && panelWidth <= 0) {
      throw const TemplateValidationException('repeatX requires a panel width');
    }
    if (slots.isEmpty) {
      throw const TemplateValidationException(
        'template needs at least one slot',
      );
    }
    final ids = <String>{};
    for (final slot in slots) {
      if (!ids.add(slot.id)) {
        throw TemplateValidationException('duplicate slot id ${slot.id}');
      }
      if (slot.imageIndex < 0 || slot.imageIndex > 3) {
        throw TemplateValidationException(
          'slot ${slot.id} has invalid image index',
        );
      }
      if (slot.width <= 0 || slot.height <= 0) {
        throw TemplateValidationException(
          'slot ${slot.id} has invalid dimensions',
        );
      }
      final boundaryWidth = repeatX > 1 ? panelWidth : canvasWidth.toDouble();
      if (slot.x < 0 ||
          slot.y < 0 ||
          slot.x + slot.width > boundaryWidth + 0.01 ||
          slot.y + slot.height > canvasHeight + 0.01) {
        throw TemplateValidationException(
          'slot ${slot.id} is outside the canvas',
        );
      }
    }
    for (final text in texts) {
      if (text.x < 0 ||
          text.y < 0 ||
          text.x > (repeatX > 1 ? panelWidth : canvasWidth) ||
          text.y > canvasHeight) {
        throw TemplateValidationException(
          'text ${text.id} is outside the canvas',
        );
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'canvas_width': canvasWidth,
    'canvas_height': canvasHeight,
    'output_width': outputWidth,
    'output_height': outputHeight,
    'dpi': dpi,
    'background_color': backgroundColor,
    'repeat_x': repeatX,
    'panel_width': panelWidth,
    'divider_y': dividerY,
    'divider_color': dividerColor,
    'slots': [for (final slot in slots) slot.toJson()],
  };
}
