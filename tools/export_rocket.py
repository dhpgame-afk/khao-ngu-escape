#!/usr/bin/env python3
"""ส่งออกโมเดลบั้งไฟ (หนีตายเขางู) ให้แก้ใน Blockbench / นำเข้า Roblox Studio

ใช้ได้ด้วย Python 3 ล้วน ๆ (ไลบรารีมาตรฐานเท่านั้น):
    python -I tools/export_rocket.py

สร้างไฟล์ใน map-assets/models/
    rocket.bbmodel  โปรเจกต์ Blockbench (Generic Model / free) 1 stud = 16 หน่วย Blockbench
    rocket.obj      เหมือนกันแต่เป็นสามเหลี่ยม 1 หน่วย = 1 stud (ใช้กับ Studio: File -> Import 3D)
    rocket.mtl      สีของแต่ละวัสดุสำหรับ rocket.obj

ตัวเลขทั้งหมดคัดลอกมาจาก src/shared/Config.luau
    (Config.Rocket.Build -- ประมาณบรรทัด 607) และรูปทรงจาก buildRocket ใน src/server/Rocket.luau
    ถ้าแก้ Config ให้แก้ค่าในส่วน "ค่าจาก Config" ด้านล่างให้ตรงกัน
ไม่แก้โค้ดเกมใด ๆ

สิ่งที่ประมาณ (ไม่เหมือนในเกม 100%)
    - ทรงกระบอก (ตัวบั้งไฟ ข้อไผ่ ขั้นปลายแหลม วงเชือก) = ปริซึมหกเหลี่ยม สร้างจากกล่อง 3 ใบหมุนรอบแกน Y 0/60/120 องศา
    - ลูกบอล (ปลายสุด ปมเชือก) = กล่องลูกบาศก์
    - ขาแท่นฝังดินลึก 4 stud ในเกม -- ที่นี่ตัดให้เริ่มที่พื้น (y=0)
    - ข้อมูลที่ไม่ใช่รูปทรง (ป้ายลอย ควัน ประกาย) ไม่ถูกส่งออก
"""

from __future__ import annotations

import base64
import json
import math
import struct
import uuid
import zlib
from pathlib import Path

# ===================== ค่าจาก Config (Config.Rocket.Build) =====================
RGB = tuple[int, int, int]

BODY_DIAMETER = 3  # BodyDiameter
BODY_HEIGHT = 22  # BodyHeight
BODY_COLOR: RGB = (226, 200, 150)  # BodyColor
NODE_COLOR: RGB = (176, 140, 86)  # NodeColor
NODE_COUNT = 4  # NodeCount
NODE_DIAMETER_EXTRA = 0.4  # NodeDiameterExtra
NODE_HEIGHT = 0.5  # NodeHeight
NOSE_TIER_COUNT = 4  # NoseTierCount
NOSE_TIER_HEIGHT = 1.4  # NoseTierHeight
NOSE_BASE_DIAMETER = 3.2  # NoseBaseDiameter
NOSE_COLORS: list[RGB] = [(205, 45, 40), (235, 190, 60)]  # NoseColors (แดง/ทอง)
TIP_DIAMETER = 0.8  # TipDiameter
FIN_SIZE = (0.3, 4, 7)  # FinSize (หนา x สูง x กว้างรวม)
FIN_COLOR: RGB = (150, 100, 55)  # FinColor
FUSE_SIZE = (0.3, 1.4, 0.3)  # FuseSize
FUSE_COLOR: RGB = (60, 45, 35)  # FuseColor
DECK_SIZE = (18, 1, 18)  # DeckSize
DECK_HEIGHT = 5  # DeckHeight (ผิวบนแท่นสูงจากพื้น)
DECK_COLOR: RGB = (125, 85, 48)  # DeckColor
LEG_SIZE = (1.4, 8, 1.4)  # LegSize
LEG_INSET = 1.2  # LegInset
FRAME_POST_SIZE = (1, 18, 1)  # FramePostSize
FRAME_POST_SPACING = 12  # FramePostSpacing
FRAME_BAR_SIZE = (14, 0.8, 0.8)  # FrameBarSize
FRAME_COLOR: RGB = (150, 100, 55)  # FrameColor
TIE_SPOT_COUNT = 4  # TieSpotCount
TIE_SPOT_RADIUS = 3.2  # TieSpotRadius
TIE_RING_DIAMETER = 2.6  # TieRingDiameter
TIE_RING_THICKNESS = 0.2  # TieRingThickness
TIE_RING_COLOR: RGB = (205, 45, 40)  # TieRingColor
TIE_KNOT_HEIGHT = 3.2  # TieKnotHeight
TIE_KNOT_SIZE = 0.8  # TieKnotSize
TIE_KNOT_COLOR: RGB = (235, 190, 60)  # TieKnotColor
# ค่าคงที่ที่ฝังอยู่ใน Rocket.luau (ไม่ได้อยู่ใน Config)
FRAME_BAR_FRACTIONS = (0.45, 0.85)  # สัดส่วนความสูงเสาของคาน 2 ชั้น
FUSE_ANGLE_DEG = 22.5  # math.pi / 8
FUSE_OFFSET = 0.2  # ห่างผิวตัวบั้งไฟ
FUSE_LIFT = 0.3  # ยกจากก้นบั้งไฟ
TIE_RING_LIFT = 0.05  # วงเชือกลอยเหนือแท่น
TIP_LIFT_RATIO = 0.3  # ปลายสุดสูงเหนือขั้นสุดท้าย = 0.3 x เส้นผ่านศูนย์กลาง

# ===================== ค่าของตัวส่งออก =====================
UNITS_PER_STUD = 16  # 1 stud = 16 หน่วย Blockbench
HEX_RADIUS_RATIO = 0.55  # รัศมีมุมหกเหลี่ยม = 0.55 x เส้นผ่านศูนย์กลาง (ใกล้เคียงวงกลมที่สุด)
TEXTURE_SIZE = 16
PROJECT_NAME = "บั้งไฟ_Rocket (1 stud = 16 หน่วย Blockbench)"

# ชื่อวัสดุ -> สี (หนึ่งสีหนึ่ง texture)
MATERIALS: dict[str, RGB] = {
    "deck_wood": DECK_COLOR,
    "frame_wood": FRAME_COLOR,
    "body_bamboo": BODY_COLOR,
    "node_bamboo": NODE_COLOR,
    "red": NOSE_COLORS[0],
    "gold": NOSE_COLORS[1],
    "fuse_dark": FUSE_COLOR,
}


def _material_for(color: RGB) -> str:
    for name, value in MATERIALS.items():
        if value == color:
            return name
    raise ValueError(f"ไม่มีวัสดุสำหรับสี {color}")


# ===================== กล่อง =====================
class Box:
    """กล่อง 1 ใบ: จุดกึ่งกลาง (stud) ขนาด (stud) หมุนรอบแกน Y ที่กึ่งกลางตัวเอง"""

    def __init__(
        self,
        name: str,
        group: str,
        material: str,
        center: tuple[float, float, float],
        size: tuple[float, float, float],
        rot_y: float = 0.0,
    ) -> None:
        self.name = name
        self.group = group
        self.material = material
        self.center = center
        self.size = size
        self.rot_y = rot_y
        self.uuid = str(uuid.uuid4())

    def corners(self) -> list[tuple[float, float, float]]:
        """8 มุมหลังหมุนแล้ว เรียงตามบิต: x=bit0 y=bit1 z=bit2 (0=ต่ำ 1=สูง)"""
        cx, cy, cz = self.center
        sx, sy, sz = self.size
        angle = math.radians(self.rot_y)
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        result = []
        for index in range(8):
            lx = (sx / 2) * (1 if index & 1 else -1)
            ly = (sy / 2) * (1 if index & 2 else -1)
            lz = (sz / 2) * (1 if index & 4 else -1)
            # หมุนรอบ +Y แบบเดียวกับ CFrame.Angles(0, a, 0) ของ Roblox
            rx = lx * cos_a + lz * sin_a
            rz = -lx * sin_a + lz * cos_a
            result.append((cx + rx, cy + ly, cz + rz))
        return result


def hex_prism(
    boxes: list[Box],
    name: str,
    group: str,
    material: str,
    diameter: float,
    height: float,
    center: tuple[float, float, float],
) -> None:
    """ทรงกระบอกตั้งตรง ~ ปริซึมหกเหลี่ยม = กล่อง 3 ใบ (กว้างข้ามหน้าเรียบ x หนาเท่าความยาวขอบ) หมุน 0/60/120 องศา"""
    radius = diameter * HEX_RADIUS_RATIO
    across_flats = radius * math.sqrt(3)
    for index, angle in enumerate((0, 60, 120)):
        boxes.append(Box(f"{name}_{index + 1}", group, material, center, (across_flats, height, radius), angle))


def build_boxes() -> list[Box]:
    boxes: list[Box] = []
    base_group = "ฐาน_Base"
    frame_group = "กรอบ_Frame"
    body_group = "ตัวบั้งไฟ_Body"
    nose_group = "หัว_Nose"
    fins_group = "ครีบ_Fins"
    fuse_group = "ชนวน_Fuse"
    ties_group = "จุดมัด_TieSpots"

    deck_x, deck_y, deck_z = DECK_SIZE
    deck_top = DECK_HEIGHT
    deck_material = _material_for(DECK_COLOR)
    frame_material = _material_for(FRAME_COLOR)

    # ----- ฐาน: แท่นไม้ + ขา 4 ต้น -----
    boxes.append(Box("Deck", base_group, deck_material, (0, deck_top - deck_y / 2, 0), DECK_SIZE))
    leg_top = deck_top - deck_y
    leg_bottom = max(0.0, leg_top - LEG_SIZE[1])  # ตัดส่วนที่ฝังดินออก
    leg_height = leg_top - leg_bottom
    leg_index = 0
    for sx in (-1, 1):
        for sz in (-1, 1):
            leg_index += 1
            boxes.append(
                Box(
                    f"Leg{leg_index}",
                    base_group,
                    frame_material,
                    (
                        sx * (deck_x / 2 - LEG_INSET),
                        leg_bottom + leg_height / 2,
                        sz * (deck_z / 2 - LEG_INSET),
                    ),
                    (LEG_SIZE[0], leg_height, LEG_SIZE[2]),
                )
            )

    # ----- กรอบด้านหลัง (-Z): เสา 2 ต้น + คาน 2 ชั้น -----
    back_z = -(deck_z / 2 - 1)
    for index, sx in enumerate((-1, 1), start=1):
        boxes.append(
            Box(
                f"FramePost{index}",
                frame_group,
                frame_material,
                (sx * FRAME_POST_SPACING / 2, deck_top + FRAME_POST_SIZE[1] / 2, back_z),
                FRAME_POST_SIZE,
            )
        )
    for index, fraction in enumerate(FRAME_BAR_FRACTIONS, start=1):
        boxes.append(
            Box(
                f"FrameBar{index}",
                frame_group,
                frame_material,
                (0, deck_top + FRAME_POST_SIZE[1] * fraction, back_z),
                FRAME_BAR_SIZE,
            )
        )

    # ----- ตัวบั้งไฟ + ข้อไผ่ -----
    body_material = _material_for(BODY_COLOR)
    node_material = _material_for(NODE_COLOR)
    hex_prism(
        boxes, "Shaft", body_group, body_material, BODY_DIAMETER, BODY_HEIGHT, (0, deck_top + BODY_HEIGHT / 2, 0)
    )
    for i in range(1, NODE_COUNT + 1):
        hex_prism(
            boxes,
            f"BambooNode{i}",
            body_group,
            node_material,
            BODY_DIAMETER + NODE_DIAMETER_EXTRA,
            NODE_HEIGHT,
            (0, deck_top + BODY_HEIGHT * i / (NODE_COUNT + 1), 0),
        )

    # ----- หัว: ปลายแหลมเป็นขั้น แดง/ทองสลับ + ปลายสุด -----
    for tier in range(1, NOSE_TIER_COUNT + 1):
        diameter = NOSE_BASE_DIAMETER * (1 - (tier - 1) / NOSE_TIER_COUNT)
        color = NOSE_COLORS[(tier - 1) % len(NOSE_COLORS)]
        hex_prism(
            boxes,
            f"Nose{tier}",
            nose_group,
            _material_for(color),
            diameter,
            NOSE_TIER_HEIGHT,
            (0, deck_top + BODY_HEIGHT + (tier - 0.5) * NOSE_TIER_HEIGHT, 0),
        )
    tip_y = BODY_HEIGHT + NOSE_TIER_COUNT * NOSE_TIER_HEIGHT
    boxes.append(
        Box(
            "Tip",
            nose_group,
            _material_for(NOSE_COLORS[-1]),
            (0, deck_top + tip_y + TIP_DIAMETER * TIP_LIFT_RATIO, 0),
            (TIP_DIAMETER, TIP_DIAMETER, TIP_DIAMETER),
            45,
        )
    )

    # ----- ครีบ 2 แผ่นไขว้ (ยื่นตามแกน X และ Z) -----
    fin_thick, fin_height, fin_width = FIN_SIZE
    fin_material = _material_for(FIN_COLOR)
    boxes.append(Box("Fin1", fins_group, fin_material, (0, deck_top + fin_height / 2, 0), (fin_thick, fin_height, fin_width)))
    boxes.append(Box("Fin2", fins_group, fin_material, (0, deck_top + fin_height / 2, 0), (fin_width, fin_height, fin_thick)))

    # ----- ชนวนที่ก้นบั้งไฟ (เยื้อง 22.5 องศา) -----
    fuse_angle = math.radians(FUSE_ANGLE_DEG)
    fuse_radius = BODY_DIAMETER / 2 + FUSE_OFFSET
    boxes.append(
        Box(
            "Fuse",
            fuse_group,
            _material_for(FUSE_COLOR),
            (
                fuse_radius * math.cos(fuse_angle),
                deck_top + FUSE_SIZE[1] / 2 + FUSE_LIFT,
                -fuse_radius * math.sin(fuse_angle),  # CFrame.Angles(0,a,0) หมุนแล้ว z = -r sin a
            ),
            FUSE_SIZE,
            FUSE_ANGLE_DEG,
        )
    )

    # ----- จุดมัด: วงเชือกบนแท่น + ปมเชือกที่ตัวบั้งไฟ เริ่มมุม 45 องศา -----
    ring_material = _material_for(TIE_RING_COLOR)
    knot_material = _material_for(TIE_KNOT_COLOR)
    for i in range(1, TIE_SPOT_COUNT + 1):
        angle = (i - 0.5) * 2 * math.pi / TIE_SPOT_COUNT
        dir_x, dir_z = math.cos(angle), math.sin(angle)
        hex_prism(
            boxes,
            f"TieRing{i}",
            ties_group,
            ring_material,
            TIE_RING_DIAMETER,
            TIE_RING_THICKNESS,
            (
                dir_x * TIE_SPOT_RADIUS,
                deck_top + TIE_RING_THICKNESS / 2 + TIE_RING_LIFT,
                dir_z * TIE_SPOT_RADIUS,
            ),
        )
        boxes.append(
            Box(
                f"TieKnot{i}",
                ties_group,
                knot_material,
                (dir_x * BODY_DIAMETER / 2, deck_top + TIE_KNOT_HEIGHT, dir_z * BODY_DIAMETER / 2),
                (TIE_KNOT_SIZE, TIE_KNOT_SIZE, TIE_KNOT_SIZE),
                45,
            )
        )
    return boxes


# ===================== PNG =====================
def solid_png(color: RGB, size: int = TEXTURE_SIZE) -> bytes:
    """PNG สีเดียวเต็มรูป (RGB 8 บิต)"""

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    row = b"\x00" + bytes(color) * size  # filter 0 + พิกเซลซ้ำ
    raw = row * size
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


# ===================== Blockbench =====================
def build_bbmodel(boxes: list[Box]) -> dict:
    texture_ids = {name: index for index, name in enumerate(MATERIALS)}
    textures = []
    for name, color in MATERIALS.items():
        data = base64.b64encode(solid_png(color)).decode("ascii")
        textures.append(
            {
                "path": "",
                "name": f"{name}.png",
                "folder": "",
                "namespace": "",
                "id": str(texture_ids[name]),
                "width": TEXTURE_SIZE,
                "height": TEXTURE_SIZE,
                "uv_width": TEXTURE_SIZE,
                "uv_height": TEXTURE_SIZE,
                "particle": False,
                "use_as_default": False,
                "layers_enabled": False,
                "sync_to_project": "",
                "render_mode": "default",
                "render_sides": "auto",
                "frame_time": 1,
                "frame_order_type": "loop",
                "frame_order": "",
                "frame_interpolate": False,
                "visible": True,
                "internal": True,
                "saved": True,
                "uuid": str(uuid.uuid4()),
                "source": f"data:image/png;base64,{data}",
            }
        )

    elements = []
    group_children: dict[str, list[str]] = {}
    for box in boxes:
        cx, cy, cz = (value * UNITS_PER_STUD for value in box.center)
        hx, hy, hz = (value * UNITS_PER_STUD / 2 for value in box.size)
        texture = texture_ids[box.material]
        face = {"uv": [0, 0, TEXTURE_SIZE, TEXTURE_SIZE], "texture": texture}
        elements.append(
            {
                "name": box.name,
                "box_uv": False,
                "rescale": False,
                "locked": False,
                "light_emission": 0,
                "render_order": "default",
                "allow_mirror_modeling": True,
                "from": [round(cx - hx, 4), round(cy - hy, 4), round(cz - hz, 4)],
                "to": [round(cx + hx, 4), round(cy + hy, 4), round(cz + hz, 4)],
                "autouv": 0,
                "color": texture % 8,
                "origin": [round(cx, 4), round(cy, 4), round(cz, 4)],
                "rotation": [0, round(box.rot_y, 4), 0],
                "uuid": box.uuid,
                "faces": {side: dict(face) for side in ("north", "east", "south", "west", "up", "down")},
                "type": "cube",
            }
        )
        group_children.setdefault(box.group, []).append(box.uuid)

    outliner = [
        {
            "name": group,
            "origin": [0, 0, 0],
            "color": index % 8,
            "uuid": str(uuid.uuid4()),
            "export": True,
            "mirror_uv": False,
            "isOpen": True,
            "locked": False,
            "visibility": True,
            "autouv": 0,
            "children": children,
        }
        for index, (group, children) in enumerate(group_children.items())
    ]

    return {
        "meta": {"format_version": "4.10", "model_format": "free", "box_uv": False},
        "name": PROJECT_NAME,
        "model_identifier": "",
        "visible_box": [1, 1, 0],
        "variable_placeholders": "",
        "variable_placeholder_buttons": [],
        "unhandled_marker_colors": [],
        "timeline_setups": [],
        "resolution": {"width": TEXTURE_SIZE, "height": TEXTURE_SIZE},
        "elements": elements,
        "outliner": outliner,
        "textures": textures,
    }


# ===================== OBJ / MTL =====================
# (ชื่อด้านนอก, 4 มุมเรียงทวนเข็มเมื่อมองจากด้านนอก (ตามบิตของ Box.corners), เวกเตอร์ตั้งฉากก่อนหมุน)
_FACES = [
    ((0, 4, 6, 2), (-1, 0, 0)),  # -X
    ((1, 3, 7, 5), (1, 0, 0)),  # +X
    ((0, 1, 5, 4), (0, -1, 0)),  # -Y
    ((2, 6, 7, 3), (0, 1, 0)),  # +Y
    ((0, 2, 3, 1), (0, 0, -1)),  # -Z
    ((4, 5, 7, 6), (0, 0, 1)),  # +Z
]

_OBJ_GROUP_NAMES = {
    "ฐาน_Base": "Base",
    "กรอบ_Frame": "Frame",
    "ตัวบั้งไฟ_Body": "Body",
    "หัว_Nose": "Nose",
    "ครีบ_Fins": "Fins",
    "ชนวน_Fuse": "Fuse",
    "จุดมัด_TieSpots": "TieSpots",
}


def build_obj(boxes: list[Box]) -> str:
    lines = ["# บั้งไฟ (Rocket) -- 1 หน่วย = 1 stud, Y ขึ้น, พื้น y=0", "mtllib rocket.mtl"]
    vertex_count = 0
    normal_count = 0
    current_group = ""
    for box in boxes:
        group = _OBJ_GROUP_NAMES[box.group]
        if group != current_group:
            lines.append(f"g {group}")
            current_group = group
        lines.append(f"o {box.name}")
        lines.append(f"usemtl {box.material}")
        corners = box.corners()
        for x, y, z in corners:
            lines.append(f"v {x:.5f} {y:.5f} {z:.5f}")
        angle = math.radians(box.rot_y)
        cos_a, sin_a = math.cos(angle), math.sin(angle)
        for corner_ids, (nx, ny, nz) in _FACES:
            rx = nx * cos_a + nz * sin_a
            rz = -nx * sin_a + nz * cos_a
            lines.append(f"vn {rx:.5f} {ny:.5f} {rz:.5f}")
            normal_count += 1
            a, b, c, d = (vertex_count + i + 1 for i in corner_ids)
            lines.append(f"f {a}//{normal_count} {b}//{normal_count} {c}//{normal_count}")
            lines.append(f"f {a}//{normal_count} {c}//{normal_count} {d}//{normal_count}")
        vertex_count += 8
    return "\n".join(lines) + "\n"


def build_mtl() -> str:
    lines = ["# สีของบั้งไฟ"]
    for name, (red, green, blue) in MATERIALS.items():
        lines += [
            f"newmtl {name}",
            f"Kd {red / 255:.4f} {green / 255:.4f} {blue / 255:.4f}",
            "Ka 0 0 0",
            "Ks 0 0 0",
            "d 1",
            "illum 1",
            "",
        ]
    return "\n".join(lines)


# ===================== main =====================
def main() -> None:
    out_dir = Path(__file__).resolve().parent.parent / "map-assets" / "models"
    out_dir.mkdir(parents=True, exist_ok=True)

    boxes = build_boxes()
    bbmodel = build_bbmodel(boxes)
    (out_dir / "rocket.bbmodel").write_text(json.dumps(bbmodel, ensure_ascii=False, indent=1), encoding="utf-8")
    (out_dir / "rocket.obj").write_text(build_obj(boxes), encoding="utf-8", newline="\n")
    (out_dir / "rocket.mtl").write_text(build_mtl(), encoding="utf-8", newline="\n")

    # ตรวจ: อ่านกลับมาเป็น JSON ได้ + ขนาดรวม
    reloaded = json.loads((out_dir / "rocket.bbmodel").read_text(encoding="utf-8"))
    points = [corner for box in boxes for corner in box.corners()]
    mins = [min(p[axis] for p in points) for axis in range(3)]
    maxs = [max(p[axis] for p in points) for axis in range(3)]
    print(f"เขียนไฟล์ไปที่ {out_dir}")
    print(f"จำนวน element (กล่อง): {len(reloaded['elements'])} / กลุ่ม: {len(reloaded['outliner'])} / texture: {len(reloaded['textures'])}")
    print(
        "ขนาดรวม (stud) กว้าง X x สูง Y x ลึก Z = "
        f"{maxs[0] - mins[0]:.2f} x {maxs[1] - mins[1]:.2f} x {maxs[2] - mins[2]:.2f}"
    )
    print(f"ช่วง X {mins[0]:.2f}..{maxs[0]:.2f}  Y {mins[1]:.2f}..{maxs[1]:.2f}  Z {mins[2]:.2f}..{maxs[2]:.2f}")


if __name__ == "__main__":
    main()
