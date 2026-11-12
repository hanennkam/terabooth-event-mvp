from __future__ import annotations

from dataclasses import dataclass

DEFAULT_TEMPLATE_ID = "strip_2x6_3up_v1"


@dataclass(frozen=True)
class SlotSpec:
    id: str
    image_index: int
    x: float
    y: float
    width: float
    height: float
    border_width: float = 0
    border_color: int = 0xFF111111

    @property
    def aspect(self) -> float:
        return self.width / self.height


@dataclass(frozen=True)
class TextSpec:
    id: str
    kind: str  # event_title | event_date | literal
    x: float
    y: float
    font_size: float = 28
    color: int = 0xFF111111
    text: str = ""
    align: str = "center"


@dataclass(frozen=True)
class TemplateSpec:
    id: str
    name: str
    description: str
    version: int
    canvas_width: int
    canvas_height: int
    output_width: int
    output_height: int
    dpi: int
    background_color: int
    repeat_x: int
    panel_width: float
    slots: tuple[SlotSpec, ...]
    texts: tuple[TextSpec, ...]
    divider_y: float = 0
    divider_color: int = 0xFF111111

    @property
    def slots_by_id(self) -> dict[str, SlotSpec]:
        return {slot.id: slot for slot in self.slots}


DEFAULT = TemplateSpec(
    id=DEFAULT_TEMPLATE_ID,
    name="Classic 2×6 Duo",
    description="Two identical 2×6 strips on one 4×6 sheet. Event-safe default.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFFFFFFF,
    repeat_x=2,
    panel_width=600,
    divider_y=82,
    slots=(
        SlotSpec("photo_1", 0, 24, 100, 552, 531, 2),
        SlotSpec("photo_2", 1, 24, 649, 552, 531, 2),
        SlotSpec("photo_3", 2, 24, 1198, 552, 531, 2),
    ),
    texts=(
        TextSpec("title", "event_title", 300, 28, 30),
        TextSpec("date", "event_date", 300, 66, 20),
        TextSpec("footer", "literal", 300, 1770, 18, text="TERABOOTH"),
    ),
)

COLLAGE = TemplateSpec(
    id="collage_4x6_v1",
    name="Editorial Collage",
    description="One large hero portrait with two supporting frames on cream.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFF2E8D8,
    repeat_x=1,
    panel_width=0,
    slots=(
        SlotSpec("hero", 0, 78, 150, 1044, 640, 6, 0xFFF2E8D8),
        SlotSpec("left", 1, 78, 830, 500, 660, 6, 0xFFF2E8D8),
        SlotSpec("right", 2, 622, 830, 500, 660, 6, 0xFFF2E8D8),
    ),
    texts=(
        TextSpec("title", "event_title", 600, 58, 38, 0xFF1A1A1A),
        TextSpec("date", "event_date", 600, 106, 20, 0xFF5C5246),
        TextSpec("footer", "literal", 600, 1760, 18, 0xFF5C5246, "TERABOOTH"),
    ),
)

MINIMAL = TemplateSpec(
    id="minimal_4x6_v1",
    name="Minimal Stack",
    description="Three full-width frames with generous white space.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFFFFFFF,
    repeat_x=1,
    panel_width=0,
    slots=(
        SlotSpec("photo_1", 0, 100, 100, 1000, 500, 1, 0xFFE6E1D8),
        SlotSpec("photo_2", 1, 100, 650, 1000, 500, 1, 0xFFE6E1D8),
        SlotSpec("photo_3", 2, 100, 1200, 1000, 500, 1, 0xFFE6E1D8),
    ),
    texts=(
        TextSpec("title", "event_title", 600, 38, 26, 0xFF1A1A1A),
        TextSpec("date", "event_date", 600, 72, 16, 0xFF7A746C),
        TextSpec("footer", "literal", 600, 1760, 14, 0xFFA09A90, "TERABOOTH"),
    ),
)



SOLO = TemplateSpec(
    id="solo_4x6_v1",
    name="Single Portrait",
    description="One full-frame portrait on a 4x6 sheet.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFFFFFFF,
    repeat_x=1,
    panel_width=0,
    slots=(SlotSpec("photo_1", 0, 70, 210, 1060, 1230, 2),),
    texts=(
        TextSpec("title", "event_title", 600, 70, 38),
        TextSpec("date", "event_date", 600, 120, 22),
        TextSpec("footer", "literal", 600, 1740, 18, text="TERABOOTH"),
    ),
)

DUO = TemplateSpec(
    id="duo_4x6_v1",
    name="Duo Stack",
    description="Two large portraits stacked on a 4x6 sheet.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFFFFFFF,
    repeat_x=1,
    panel_width=0,
    slots=(
        SlotSpec("photo_1", 0, 70, 190, 1060, 650, 2),
        SlotSpec("photo_2", 1, 70, 900, 1060, 650, 2),
    ),
    texts=(
        TextSpec("title", "event_title", 600, 66, 34),
        TextSpec("date", "event_date", 600, 112, 20),
        TextSpec("footer", "literal", 600, 1740, 18, text="TERABOOTH"),
    ),
)

GRID = TemplateSpec(
    id="grid_4x6_v1",
    name="Four Grid",
    description="Four portraits in a clean 2x2 grid.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFFFFFFF,
    repeat_x=1,
    panel_width=0,
    slots=(
        SlotSpec("photo_1", 0, 70, 190, 510, 610, 2),
        SlotSpec("photo_2", 1, 620, 190, 510, 610, 2),
        SlotSpec("photo_3", 2, 70, 880, 510, 610, 2),
        SlotSpec("photo_4", 3, 620, 880, 510, 610, 2),
    ),
    texts=(
        TextSpec("title", "event_title", 600, 66, 34),
        TextSpec("date", "event_date", 600, 112, 20),
        TextSpec("footer", "literal", 600, 1740, 18, text="TERABOOTH"),
    ),
)


PRECOMPOSED = TemplateSpec(
    id="precomposed_4x6_v1",
    name="Precomposed 4x6",
    description="Full-bleed precomposed photo strip from the iPad.",
    version=1,
    canvas_width=1200,
    canvas_height=1800,
    output_width=1200,
    output_height=1800,
    dpi=300,
    background_color=0xFFFFFFFF,
    repeat_x=1,
    panel_width=0,
    slots=(SlotSpec("photo_1", 0, 0, 0, 1200, 1800, 0),),
    texts=(),
)

TEMPLATES = {template.id: template for template in (DEFAULT, COLLAGE, MINIMAL, SOLO, DUO, GRID, PRECOMPOSED)}


def get_template(template_id: str) -> TemplateSpec | None:
    return TEMPLATES.get(template_id)
