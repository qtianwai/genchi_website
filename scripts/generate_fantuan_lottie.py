#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ANIMATION_DIR = ROOT / "ios" / "FoodMap" / "genchi" / "genchi" / "Resources" / "Animations"
PREVIEW_DIR = ROOT / "项目素材" / "饭团Lottie预览"

ARTBOARD = 200
PREVIEW_SIZE = 768
FPS = 60
COMP_OFFSET = (100, 88)


STATE_CONFIG = {
    "fantuan_idle": {"duration": 3.0, "style": "idle"},
    "fantuan_hungry": {"duration": 2.5, "style": "hungry"},
    "fantuan_sleepy": {"duration": 3.0, "style": "sleepy"},
    "fantuan_excited": {"duration": 2.0, "style": "excited"},
    "fantuan_rainy": {"duration": 3.0, "style": "rainy"},
    "fantuan_eating": {"duration": 1.5, "style": "eating"},
    "fantuan_happy": {"duration": 1.5, "style": "happy"},
    "fantuan_starving": {"duration": 3.0, "style": "starving"},
    "fantuan_tap": {"duration": 0.8, "style": "tap"},
}


COLORS = {
    "outline": "#0B0B0D",
    "rice": "#FFF9F1",
    "rice_shadow": "#F8F0DF",
    "grain": "#F4E5C5",
    "cheek": "#F8A7C4",
    "cheek_line": "#EF6E97",
    "belt": "#61B8C7",
    "belt_pattern": "#F7D58A",
    "bib": "#FFF1D5",
    "medallion": "#E0734B",
    "flower_a": "#F5986F",
    "flower_b": "#F07B63",
    "leaf": "#92C6B6",
    "rain": "#7EC8F7",
    "umbrella": "#7AB7EE",
    "accent_green": "#8FC9A2",
    "bubble_fill": "#FFFFFF",
}


BODY_POINTS = [
    (0, -92),
    (28, -90),
    (58, -76),
    (78, -46),
    (86, -6),
    (82, 42),
    (62, 82),
    (34, 104),
    (0, 112),
    (-34, 104),
    (-62, 82),
    (-82, 42),
    (-86, -6),
    (-78, -46),
    (-58, -76),
    (-28, -90),
]

POUCH_POINTS = [
    (-30, 0),
    (30, 0),
    (24, 36),
    (0, 52),
    (-24, 36),
]


def auto_tangents(points: list[tuple[float, float]], strength: float = 0.22, closed: bool = True):
    count = len(points)
    tangents_in = []
    tangents_out = []
    for idx, (x, y) in enumerate(points):
        prev = points[idx - 1] if idx > 0 else (points[-1] if closed else points[idx])
        nxt = points[(idx + 1) % count] if idx < count - 1 or closed else points[idx]
        dx = (nxt[0] - prev[0]) * strength
        dy = (nxt[1] - prev[1]) * strength
        tangents_in.append([-dx, -dy])
        tangents_out.append([dx, dy])
    if not closed:
        tangents_in[0] = [0, 0]
        tangents_out[-1] = [0, 0]
    return tangents_in, tangents_out


BODY_IN, BODY_OUT = auto_tangents(BODY_POINTS, strength=0.18)
POUCH_IN, POUCH_OUT = auto_tangents(POUCH_POINTS, strength=0.18)


def cubic_bezier(p0, p1, p2, p3, t):
    mt = 1 - t
    x = mt ** 3 * p0[0] + 3 * mt ** 2 * t * p1[0] + 3 * mt * t ** 2 * p2[0] + t ** 3 * p3[0]
    y = mt ** 3 * p0[1] + 3 * mt ** 2 * t * p1[1] + 3 * mt * t ** 2 * p2[1] + t ** 3 * p3[1]
    return x, y


def sample_path(points, in_tangents, out_tangents, steps: int = 18):
    sampled = []
    count = len(points)
    for idx, point in enumerate(points):
        next_idx = (idx + 1) % count
        p0 = point
        p1 = (point[0] + out_tangents[idx][0], point[1] + out_tangents[idx][1])
        nxt = points[next_idx]
        p2 = (nxt[0] + in_tangents[next_idx][0], nxt[1] + in_tangents[next_idx][1])
        p3 = nxt
        for step in range(steps):
            sampled.append(cubic_bezier(p0, p1, p2, p3, step / steps))
    return sampled


def rgb(hex_code: str) -> list[float]:
    hex_code = hex_code.lstrip("#")
    return [int(hex_code[i:i + 2], 16) / 255 for i in range(0, 6, 2)] + [1.0]


def comp_point(point: tuple[float, float]) -> list[float]:
    return [point[0] + COMP_OFFSET[0], point[1] + COMP_OFFSET[1]]


def k_static(value):
    return {"a": 0, "k": value}


def k_anim(frames: list[tuple[int, list[float], list[float] | None]]):
    keyed = []
    for frame, start, end in frames:
        entry = {"t": frame, "s": start}
        if end is not None:
            entry["e"] = end
        keyed.append(entry)
    return {"a": 1, "k": keyed}


def shape_path(points, in_tangents, out_tangents, closed=True):
    return {
        "ty": "sh",
        "ks": {
            "a": 0,
            "k": {
                "i": [[x, y] for x, y in in_tangents],
                "o": [[x, y] for x, y in out_tangents],
                "v": [[x, y] for x, y in points],
                "c": closed,
            },
        },
        "nm": "Path",
        "mn": "ADBE Vector Shape - Group",
        "hd": False,
    }


def fill(color: str, opacity: float = 100):
    return {
        "ty": "fl",
        "c": k_static(rgb(color)),
        "o": k_static(opacity),
        "r": 1,
        "bm": 0,
        "nm": "Fill",
        "mn": "ADBE Vector Graphic - Fill",
        "hd": False,
    }


def stroke(color: str, width: float, opacity: float = 100):
    return {
        "ty": "st",
        "c": k_static(rgb(color)),
        "o": k_static(opacity),
        "w": k_static(width),
        "lc": 2,
        "lj": 2,
        "bm": 0,
        "nm": "Stroke",
        "mn": "ADBE Vector Graphic - Stroke",
        "hd": False,
    }


def tr(position=(0, 0), scale=(100, 100), rotation=0, opacity=100, anchor=(0, 0)):
    return {
        "ty": "tr",
        "p": k_static(list(position)),
        "a": k_static(list(anchor)),
        "s": k_static(list(scale)),
        "r": k_static(rotation),
        "o": k_static(opacity),
        "sk": k_static(0),
        "sa": k_static(0),
        "nm": "Transform",
        "mn": "ADBE Vector Transform Group",
        "hd": False,
    }


def group(name: str, items: list[dict], transform: dict | None = None):
    payload = list(items)
    payload.append(transform or tr())
    return {
        "ty": "gr",
        "it": payload,
        "nm": name,
        "np": max(1, len(payload) - 1),
        "cix": 2,
        "bm": 0,
        "ix": 1,
        "mn": "ADBE Vector Group",
        "hd": False,
    }


def ellipse_group(name: str, center: tuple[float, float], size: tuple[float, float], fill_color: str | None = None,
                  stroke_color: str | None = None, stroke_width: float = 0, rotation: float = 0,
                  opacity: float = 100, scale: tuple[float, float] = (100, 100)):
    items = [
        {
            "ty": "el",
            "d": 1,
            "p": k_static(comp_point(center)),
            "s": k_static(list(size)),
            "nm": "Ellipse Path",
            "mn": "ADBE Vector Shape - Ellipse",
            "hd": False,
        }
    ]
    if fill_color:
        items.append(fill(fill_color, opacity))
    if stroke_color and stroke_width > 0:
        items.append(stroke(stroke_color, stroke_width, opacity))
    return group(name, items, tr(rotation=rotation, scale=scale))


def rect_group(name: str, center: tuple[float, float], size: tuple[float, float], radius: float,
               fill_color: str | None = None, stroke_color: str | None = None, stroke_width: float = 0,
               rotation: float = 0):
    items = [
        {
            "ty": "rc",
            "d": 1,
            "p": k_static(comp_point(center)),
            "s": k_static(list(size)),
            "r": k_static(radius),
            "nm": "Rectangle Path",
            "mn": "ADBE Vector Shape - Rect",
            "hd": False,
        }
    ]
    if fill_color:
        items.append(fill(fill_color))
    if stroke_color and stroke_width > 0:
        items.append(stroke(stroke_color, stroke_width))
    return group(name, items, tr(rotation=rotation))


def path_group(name: str, points, in_tangents, out_tangents, fill_color: str | None = None,
               stroke_color: str | None = None, stroke_width: float = 0, rotation: float = 0,
               position=(0, 0), scale=(100, 100), opacity: float = 100):
    items = [shape_path(points, in_tangents, out_tangents)]
    if fill_color:
        items.append(fill(fill_color, opacity))
    if stroke_color and stroke_width > 0:
        items.append(stroke(stroke_color, stroke_width, opacity))
    return group(name, items, tr(position=comp_point(position), rotation=rotation, scale=scale, opacity=opacity))


def line_capsule(name: str, center: tuple[float, float], size: tuple[float, float], color: str, rotation: float):
    return rect_group(name, center=center, size=size, radius=size[0] / 2, fill_color=color, rotation=rotation)


def rig_animation(style: str, end_frame: int):
    if style == "idle":
        p = k_anim([(0, [100, 88, 0], [100, 82, 0]), (90, [100, 82, 0], [100, 88, 0]), (180, [100, 88, 0], None)])
        r = k_anim([(0, [0], [1.5]), (90, [1.5], [0]), (180, [0], None)])
        s = k_static([100, 100, 100])
    elif style == "hungry":
        p = k_anim([(0, [100, 90, 0], [100, 80, 0]), (75, [100, 80, 0], [100, 90, 0]), (150, [100, 90, 0], None)])
        r = k_anim([(0, [0], [3]), (75, [3], [0]), (150, [0], None)])
        s = k_anim([(0, [100, 100, 100], [102, 102, 100]), (75, [102, 102, 100], [100, 100, 100]), (150, [100, 100, 100], None)])
    elif style == "sleepy":
        p = k_anim([(0, [100, 90, 0], [100, 94, 0]), (90, [100, 94, 0], [100, 90, 0]), (180, [100, 90, 0], None)])
        r = k_anim([(0, [0], [4]), (60, [4], [-6]), (120, [-6], [0]), (180, [0], None)])
        s = k_static([100, 100, 100])
    elif style == "excited":
        p = k_anim([(0, [100, 94, 0], [100, 68, 0]), (30, [100, 68, 0], [100, 94, 0]), (60, [100, 94, 0], [100, 72, 0]), (90, [100, 72, 0], [100, 94, 0]), (120, [100, 94, 0], None)])
        r = k_anim([(0, [-4], [4]), (60, [4], [-4]), (120, [-4], [0]), (150, [0], None)])
        s = k_anim([(0, [100, 100, 100], [102, 98, 100]), (60, [102, 98, 100], [100, 100, 100]), (120, [100, 100, 100], None)])
    elif style == "rainy":
        p = k_anim([(0, [100, 90, 0], [98, 90, 0]), (45, [98, 90, 0], [102, 90, 0]), (90, [102, 90, 0], [100, 90, 0]), (180, [100, 90, 0], None)])
        r = k_anim([(0, [-2], [2]), (45, [2], [-2]), (90, [-2], [0]), (180, [0], None)])
        s = k_static([100, 100, 100])
    elif style == "eating":
        p = k_anim([(0, [100, 88, 0], [100, 82, 0]), (30, [100, 82, 0], [100, 88, 0]), (60, [100, 88, 0], None)])
        r = k_anim([(0, [0], [2]), (30, [2], [-2]), (60, [-2], [0]), (90, [0], None)])
        s = k_anim([(0, [100, 100, 100], [104, 96, 100]), (30, [104, 96, 100], [96, 104, 100]), (60, [96, 104, 100], [100, 100, 100]), (90, [100, 100, 100], None)])
    elif style == "happy":
        p = k_anim([(0, [100, 88, 0], [100, 80, 0]), (45, [100, 80, 0], [100, 88, 0]), (90, [100, 88, 0], None)])
        r = k_anim([(0, [-6], [6]), (45, [6], [-4]), (90, [-4], [0]), (120, [0], None)])
        s = k_static([100, 100, 100])
    elif style == "starving":
        p = k_anim([(0, [100, 96, 0], [100, 98, 0]), (90, [100, 98, 0], [100, 96, 0]), (180, [100, 96, 0], None)])
        r = k_anim([(0, [-3], [3]), (90, [3], [-2]), (180, [-2], [0]), (210, [0], None)])
        s = k_static([92, 88, 100])
    else:  # tap
        p = k_anim([(0, [100, 94, 0], [100, 72, 0]), (12, [100, 72, 0], [100, 94, 0]), (24, [100, 94, 0], [100, 82, 0]), (36, [100, 82, 0], [100, 88, 0]), (48, [100, 88, 0], None)])
        r = k_anim([(0, [0], [8]), (12, [8], [-6]), (24, [-6], [2]), (36, [2], [0]), (48, [0], None)])
        s = k_anim([(0, [100, 100, 100], [104, 96, 100]), (12, [104, 96, 100], [98, 102, 100]), (24, [98, 102, 100], [100, 100, 100]), (48, [100, 100, 100], None)])
    return {
        "ddd": 0,
        "ind": 1,
        "ty": 3,
        "nm": "Rig",
        "sr": 1,
        "ks": {
            "o": k_static(100),
            "r": r,
            "p": p,
            "a": k_static([100, 88, 0]),
            "s": s,
        },
        "ao": 0,
        "ip": 0,
        "op": end_frame,
        "st": 0,
        "bm": 0,
    }


def rice_grain_groups():
    layout = [
        (-38, -52, 14, 6, -28),
        (-16, -64, 12, 5, 18),
        (8, -62, 12, 5, -20),
        (30, -52, 14, 6, 24),
        (-56, -14, 12, 5, -35),
        (-50, 18, 12, 5, 10),
        (-28, 42, 12, 5, -12),
        (54, -10, 12, 5, 26),
        (48, 18, 12, 5, -28),
        (22, 48, 12, 5, 18),
        (-8, 62, 12, 5, -16),
        (6, -30, 12, 5, 12),
    ]
    return [
        ellipse_group(f"Grain {idx}", center=(x, y), size=(w, h), fill_color=COLORS["grain"], rotation=rot, opacity=88)
        for idx, (x, y, w, h, rot) in enumerate(layout)
    ]


def belt_pattern_groups():
    motifs = [(-50, 0, 22), (0, 0, 30), (50, 0, 22)]
    groups = []
    for idx, (cx, cy, size) in enumerate(motifs):
        groups.append(ellipse_group(f"Belt Loop {idx}", center=(cx, 42 + cy), size=(size, size * 0.7),
                                    stroke_color=COLORS["belt_pattern"], stroke_width=3, scale=(100, 72)))
        groups.append(line_capsule(f"Belt Dash L {idx}", center=(cx - 22, 42 + cy), size=(18, 4),
                                   color=COLORS["belt_pattern"], rotation=0))
        groups.append(line_capsule(f"Belt Dash R {idx}", center=(cx + 22, 42 + cy), size=(18, 4),
                                   color=COLORS["belt_pattern"], rotation=0))
    return groups


def bib_flower_groups():
    flowers = [
        (-24, 80, COLORS["flower_a"]),
        (24, 80, COLORS["flower_b"]),
        (-20, 102, COLORS["cheek"]),
        (22, 102, COLORS["accent_green"]),
    ]
    groups = []
    for idx, (cx, cy, petal) in enumerate(flowers):
        for turn in (0, 72, 144, 216, 288):
            groups.append(ellipse_group(f"Flower {idx} Petal {turn}", center=(cx, cy), size=(7, 12), fill_color=petal, rotation=turn))
        groups.append(ellipse_group(f"Flower {idx} Core", center=(cx, cy + 4), size=(5, 5), fill_color=COLORS["belt_pattern"]))
    return groups


def medal_groups():
    outer = ellipse_group("Medal Ring", center=(0, 96), size=(34, 34), stroke_color=COLORS["medallion"], stroke_width=3)
    line_h = line_capsule("Medal H", center=(0, 96), size=(22, 4), color=COLORS["medallion"], rotation=0)
    line_v = line_capsule("Medal V", center=(0, 96), size=(4, 22), color=COLORS["medallion"], rotation=0)
    return [outer, line_h, line_v]


def cheek_groups():
    return [
        ellipse_group("Cheek Left", center=(-34, -2), size=(28, 24), fill_color=COLORS["cheek"], opacity=92),
        ellipse_group("Cheek Right", center=(34, -2), size=(28, 24), fill_color=COLORS["cheek"], opacity=92),
        line_capsule("Cheek L1", center=(-40, -1), size=(4, 12), color=COLORS["cheek_line"], rotation=22),
        line_capsule("Cheek L2", center=(-30, 1), size=(4, 12), color=COLORS["cheek_line"], rotation=22),
        line_capsule("Cheek R1", center=(30, 1), size=(4, 12), color=COLORS["cheek_line"], rotation=-22),
        line_capsule("Cheek R2", center=(40, -1), size=(4, 12), color=COLORS["cheek_line"], rotation=-22),
    ]


def body_shapes(style: str):
    shapes = [
        path_group("Body", BODY_POINTS, BODY_IN, BODY_OUT, fill_color=COLORS["rice"]),
    ]
    shapes.extend(rice_grain_groups())
    shapes.append(ellipse_group("Body Glow", center=(-14, -38), size=(56, 22), fill_color="#FFFFFF", opacity=58, rotation=-12))
    shapes.append(path_group("Outline", BODY_POINTS, BODY_IN, BODY_OUT, stroke_color=COLORS["outline"], stroke_width=6))
    if style == "starving":
        shapes.append(ellipse_group("Hollow", center=(0, 14), size=(36, 12), fill_color=COLORS["rice_shadow"], opacity=80))
    return shapes


def costume_shapes():
    shapes = [
        ellipse_group("Foot Left", center=(-70, 84), size=(24, 56), fill_color=COLORS["outline"], rotation=14),
        ellipse_group("Foot Right", center=(70, 84), size=(24, 56), fill_color=COLORS["outline"], rotation=-14),
        rect_group("Belt", center=(0, 42), size=(160, 24), radius=12, fill_color=COLORS["belt"], stroke_color=COLORS["outline"], stroke_width=4),
    ]
    shapes.extend(belt_pattern_groups())
    shapes.append(path_group("Pouch", POUCH_POINTS, POUCH_IN, POUCH_OUT, fill_color=COLORS["bib"], stroke_color=COLORS["outline"], stroke_width=4, position=(0, 60), scale=(108, 108)))
    shapes.extend(bib_flower_groups())
    shapes.extend(medal_groups())
    shapes.extend(cheek_groups())
    return shapes


def eye_shapes(style: str):
    if style in {"eating", "happy"}:
        return [
            ellipse_group("Left Smile Eye", center=(-30, -22), size=(20, 12), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 46)),
            ellipse_group("Right Smile Eye", center=(30, -22), size=(20, 12), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 46)),
        ]
    if style == "sleepy":
        return [
            line_capsule("Left Sleep Eye", center=(-30, -18), size=(18, 6), color=COLORS["outline"], rotation=-8),
            line_capsule("Right Sleep Eye", center=(30, -18), size=(18, 6), color=COLORS["outline"], rotation=8),
        ]
    if style == "starving":
        shapes = []
        for prefix, cx in (("Left", -28), ("Right", 28)):
            shapes.append(line_capsule(f"{prefix} X A", center=(cx, -20), size=(22, 4), color=COLORS["outline"], rotation=40))
            shapes.append(line_capsule(f"{prefix} X B", center=(cx, -20), size=(22, 4), color=COLORS["outline"], rotation=-40))
        return shapes
    if style == "tap":
        return [
            line_capsule("Wink", center=(-28, -22), size=(18, 5), color=COLORS["outline"], rotation=-6),
            ellipse_group("Right Eye", center=(30, -22), size=(28, 34), fill_color=COLORS["outline"]),
            ellipse_group("Right Shine", center=(24, -28), size=(9, 9), fill_color="#FFFFFF"),
        ]
    eye_groups = [
        ellipse_group("Left Eye", center=(-30, -22), size=(28, 34), fill_color=COLORS["outline"]),
        ellipse_group("Left Shine", center=(-36, -28), size=(9, 9), fill_color="#FFFFFF"),
        ellipse_group("Right Eye", center=(30, -22), size=(28, 34), fill_color=COLORS["outline"]),
        ellipse_group("Right Shine", center=(24, -28), size=(9, 9), fill_color="#FFFFFF"),
    ]
    if style == "hungry":
        for idx, cx in enumerate((-30, 30)):
            eye_groups.append(line_capsule(f"Spark V {idx}", center=(cx, -22), size=(4, 16), color="#FFFFFF", rotation=0))
            eye_groups.append(line_capsule(f"Spark H {idx}", center=(cx, -22), size=(16, 4), color="#FFFFFF", rotation=0))
    if style == "rainy":
        eye_groups = [
            ellipse_group("Left Eye", center=(-30, -20), size=(22, 30), fill_color=COLORS["outline"], rotation=-8),
            ellipse_group("Left Shine", center=(-34, -26), size=(7, 7), fill_color="#FFFFFF"),
            ellipse_group("Right Eye", center=(30, -20), size=(22, 30), fill_color=COLORS["outline"], rotation=8),
            ellipse_group("Right Shine", center=(26, -26), size=(7, 7), fill_color="#FFFFFF"),
        ]
    return eye_groups


def mouth_shapes(style: str):
    if style == "hungry":
        return [
            ellipse_group("Mouth", center=(0, 12), size=(20, 16), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 80)),
        ]
    if style == "sleepy":
        return [line_capsule("Mouth", center=(0, 14), size=(12, 5), color=COLORS["outline"], rotation=0)]
    if style == "excited":
        return [
            ellipse_group("Mouth", center=(0, 12), size=(22, 18), fill_color=COLORS["outline"]),
            ellipse_group("Tongue", center=(0, 16), size=(12, 8), fill_color=COLORS["cheek"]),
        ]
    if style in {"eating", "happy"}:
        return [ellipse_group("Smile", center=(0, 10), size=(24, 18), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 70))]
    if style == "starving":
        return [line_capsule("Mouth", center=(0, 14), size=(16, 4), color=COLORS["outline"], rotation=0)]
    if style == "tap":
        return [ellipse_group("Smile", center=(0, 10), size=(24, 18), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 70))]
    if style == "rainy":
        return [ellipse_group("Mouth", center=(0, 12), size=(16, 10), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 40))]
    return [ellipse_group("Smile", center=(0, 10), size=(24, 18), stroke_color=COLORS["outline"], stroke_width=4, scale=(100, 72))]


def decorative_shapes(style: str):
    shapes = costume_shapes()
    if style == "hungry":
        shapes.append(rect_group("Drool", center=(10, 24), size=(8, 18), radius=4, fill_color="#9CDDFB"))
    if style == "sleepy":
        for idx, (x, y, s) in enumerate(((48, -70, 14), (66, -92, 12), (84, -112, 10))):
            shapes.append(ellipse_group(f"Sleep Bubble {idx}", center=(x, y), size=(s, s), stroke_color=COLORS["outline"], stroke_width=3))
    if style == "excited":
        for idx, (x, y, rot) in enumerate(((-70, -58, -12), (0, -100, 0), (70, -58, 12))):
            shapes.append(line_capsule(f"Star V {idx}", center=(x, y), size=(5, 18), color=COLORS["belt_pattern"], rotation=rot))
            shapes.append(line_capsule(f"Star H {idx}", center=(x, y), size=(18, 5), color=COLORS["belt_pattern"], rotation=rot))
    if style == "rainy":
        shapes.append(rect_group("Umbrella Canopy", center=(52, -70), size=(52, 24), radius=12, fill_color=COLORS["umbrella"], stroke_color=COLORS["outline"], stroke_width=3))
        shapes.append(line_capsule("Umbrella Stem", center=(52, -42), size=(4, 34), color=COLORS["outline"], rotation=0))
        shapes.append(ellipse_group("Umbrella Hook", center=(58, -24), size=(12, 12), stroke_color=COLORS["outline"], stroke_width=3, scale=(70, 100)))
        for idx, x in enumerate((-54, -16, 22, 60)):
            shapes.append(line_capsule(f"Rain {idx}", center=(x, -92), size=(4, 16), color=COLORS["rain"], rotation=-12))
    if style == "eating":
        for idx, (x, y, rot) in enumerate(((-16, 2, -20), (8, 0, 12), (20, 8, 28))):
            shapes.append(ellipse_group(f"Crumb {idx}", center=(x, y), size=(8, 4), fill_color=COLORS["grain"], rotation=rot))
    if style == "happy":
        for idx, (x, y) in enumerate(((-58, -70), (54, -66))):
            shapes.append(ellipse_group(f"Heart A {idx}", center=(x - 4, y), size=(10, 12), fill_color=COLORS["cheek"], rotation=-18))
            shapes.append(ellipse_group(f"Heart B {idx}", center=(x + 4, y), size=(10, 12), fill_color=COLORS["cheek"], rotation=18))
            shapes.append(path_group(f"Heart Tail {idx}", [(-6, 0), (6, 0), (0, 12)], [[0, 0], [0, 0], [0, 0]], [[0, 0], [0, 0], [0, 0]], fill_color=COLORS["cheek"], position=(x, y + 8)))
    if style == "starving":
        shapes.append(ellipse_group("Sweat", center=(56, -12), size=(10, 18), fill_color=COLORS["rain"], rotation=18))
    if style == "tap":
        shapes.append(ellipse_group("Bubble", center=(48, -82), size=(34, 26), fill_color=COLORS["bubble_fill"], stroke_color=COLORS["outline"], stroke_width=3))
        shapes.append(path_group("Bubble Tail", [(-5, 0), (5, 0), (0, 8)], [[0, 0], [0, 0], [0, 0]], [[0, 0], [0, 0], [0, 0]], fill_color=COLORS["bubble_fill"], stroke_color=COLORS["outline"], stroke_width=3, position=(36, -64)))
        shapes.append(line_capsule("Question Stem", center=(48, -84), size=(4, 16), color=COLORS["outline"], rotation=0))
        shapes.append(ellipse_group("Question Dot", center=(48, -68), size=(4, 4), fill_color=COLORS["outline"]))
    return shapes


def face_layer(style: str, index: int, end_frame: int):
    return {
        "ddd": 0,
        "ind": index,
        "ty": 4,
        "nm": "Face",
        "parent": 1,
        "sr": 1,
        "ks": {
            "o": k_static(100),
            "r": k_static(0),
            "p": k_static([0, 0, 0]),
            "a": k_static([0, 0, 0]),
            "s": k_static([100, 100, 100]),
        },
        "ao": 0,
        "shapes": eye_shapes(style) + mouth_shapes(style),
        "ip": 0,
        "op": end_frame,
        "st": 0,
        "bm": 0,
    }


def body_layer(style: str, index: int, end_frame: int):
    return {
        "ddd": 0,
        "ind": index,
        "ty": 4,
        "nm": "Body",
        "parent": 1,
        "sr": 1,
        "ks": {
            "o": k_static(100),
            "r": k_static(0),
            "p": k_static([0, 0, 0]),
            "a": k_static([0, 0, 0]),
            "s": k_static([100, 100, 100]),
        },
        "ao": 0,
        "shapes": body_shapes(style),
        "ip": 0,
        "op": end_frame,
        "st": 0,
        "bm": 0,
    }


def decor_layer(style: str, index: int, end_frame: int):
    return {
        "ddd": 0,
        "ind": index,
        "ty": 4,
        "nm": "Decor",
        "parent": 1,
        "sr": 1,
        "ks": {
            "o": k_static(100),
            "r": k_static(0),
            "p": k_static([0, 0, 0]),
            "a": k_static([0, 0, 0]),
            "s": k_static([100, 100, 100]),
        },
        "ao": 0,
        "shapes": decorative_shapes(style),
        "ip": 0,
        "op": end_frame,
        "st": 0,
        "bm": 0,
    }


def animation_json(name: str, style: str, duration: float):
    end_frame = int(FPS * duration)
    return {
        "v": "5.9.6",
        "fr": FPS,
        "ip": 0,
        "op": end_frame,
        "w": ARTBOARD,
        "h": ARTBOARD,
        "nm": name,
        "ddd": 0,
        "assets": [],
        "layers": [
            rig_animation(style, end_frame),
            decor_layer(style, 2, end_frame),
            face_layer(style, 3, end_frame),
            body_layer(style, 4, end_frame),
        ],
        "markers": [],
    }


def scale_point(x: float, y: float, scale: float) -> tuple[float, float]:
    return PREVIEW_SIZE / 2 + x * scale, PREVIEW_SIZE / 2 + y * scale


def draw_rotated_capsule(draw: ImageDraw.ImageDraw, center, size, rotation, fill_color):
    temp = Image.new("RGBA", (PREVIEW_SIZE, PREVIEW_SIZE), (0, 0, 0, 0))
    temp_draw = ImageDraw.Draw(temp)
    w, h = size
    x, y = center
    temp_draw.rounded_rectangle((x - w / 2, y - h / 2, x + w / 2, y + h / 2), radius=min(w, h) / 2, fill=fill_color)
    return temp.rotate(rotation, center=center, resample=Image.Resampling.BICUBIC)


def preview_image(style: str):
    image = Image.new("RGBA", (PREVIEW_SIZE, PREVIEW_SIZE), (255, 255, 255, 0))
    scale = 3.2
    draw = ImageDraw.Draw(image)

    body_curve = sample_path(BODY_POINTS, BODY_IN, BODY_OUT)
    body = [scale_point(x, y + 16, scale) for x, y in body_curve]
    draw.polygon(body, fill=COLORS["rice"], outline=COLORS["outline"])

    grain_positions = [
        (-38, -52, 14, 6, -28),
        (-16, -64, 12, 5, 18),
        (8, -62, 12, 5, -20),
        (30, -52, 14, 6, 24),
        (-56, -14, 12, 5, -35),
        (-50, 18, 12, 5, 10),
        (-28, 42, 12, 5, -12),
        (54, -10, 12, 5, 26),
        (48, 18, 12, 5, -28),
        (22, 48, 12, 5, 18),
        (-8, 62, 12, 5, -16),
        (6, -30, 12, 5, 12),
    ]
    for x, y, w, h, rot in grain_positions:
        cx, cy = scale_point(x, y + 16, scale)
        temp = draw_rotated_capsule(draw, (cx, cy), (w * scale, h * scale), rot, COLORS["grain"])
        image.alpha_composite(temp)

    for cx, rotation in ((-70, 14), (70, -14)):
        foot_center = scale_point(cx, 100, scale)
        temp = draw_rotated_capsule(draw, foot_center, (24 * scale, 56 * scale), rotation, COLORS["outline"])
        image.alpha_composite(temp)

    draw.rounded_rectangle(
        (
            scale_point(-80, 46, scale)[0], scale_point(-80, 46, scale)[1],
            scale_point(80, 46, scale)[0], scale_point(80, 68, scale)[1],
        ),
        radius=12 * scale,
        fill=COLORS["belt"],
        outline=COLORS["outline"],
        width=4,
    )

    for cx, size in ((-50, 22), (0, 30), (50, 22)):
        x0, y0 = scale_point(cx - size / 2, 42, scale)
        x1, y1 = scale_point(cx + size / 2, 50, scale)
        draw.arc((x0, y0, x1, y1), start=0, end=360, fill=COLORS["belt_pattern"], width=6)
        lx0, ly0 = scale_point(cx - 22, 46, scale)
        lx1, ly1 = scale_point(cx - 8, 46, scale)
        draw.line((lx0, ly0, lx1, ly1), fill=COLORS["belt_pattern"], width=6)
        rx0, ry0 = scale_point(cx + 8, 46, scale)
        rx1, ry1 = scale_point(cx + 22, 46, scale)
        draw.line((rx0, ry0, rx1, ry1), fill=COLORS["belt_pattern"], width=6)

    pouch_curve = sample_path(POUCH_POINTS, POUCH_IN, POUCH_OUT)
    pouch = [scale_point(x * 1.08, y * 1.08 + 76, scale) for x, y in pouch_curve]
    draw.polygon(pouch, fill=COLORS["bib"], outline=COLORS["outline"])

    for cx, cy, petal in ((-24, 80, COLORS["flower_a"]), (24, 80, COLORS["flower_b"]), (-20, 102, COLORS["cheek"]), (22, 102, COLORS["accent_green"])):
        for turn in (0, 72, 144, 216, 288):
            center = scale_point(cx, cy, scale)
            temp = draw_rotated_capsule(draw, center, (7 * scale, 12 * scale), turn, petal)
            image.alpha_composite(temp)
        core = scale_point(cx, cy + 4, scale)
        draw.ellipse((core[0] - 2.5 * scale, core[1] - 2.5 * scale, core[0] + 2.5 * scale, core[1] + 2.5 * scale), fill=COLORS["belt_pattern"])

    medal = scale_point(0, 96, scale)
    draw.ellipse((medal[0] - 17 * scale, medal[1] - 17 * scale, medal[0] + 17 * scale, medal[1] + 17 * scale), outline=COLORS["medallion"], width=6)
    draw.line((medal[0] - 11 * scale, medal[1], medal[0] + 11 * scale, medal[1]), fill=COLORS["medallion"], width=5)
    draw.line((medal[0], medal[1] - 11 * scale, medal[0], medal[1] + 11 * scale), fill=COLORS["medallion"], width=5)

    for cx in (-34, 34):
        cheek = scale_point(cx, 14, scale)
        draw.ellipse((cheek[0] - 14 * scale, cheek[1] - 12 * scale, cheek[0] + 14 * scale, cheek[1] + 12 * scale), fill=COLORS["cheek"])
    for cx, direction in ((-40, 22), (-30, 22), (30, -22), (40, -22)):
        temp = draw_rotated_capsule(draw, scale_point(cx, 16 if abs(cx) == 30 else 14, scale), (4 * scale, 12 * scale), direction, COLORS["cheek_line"])
        image.alpha_composite(temp)

    if style in {"idle", "excited", "hungry", "rainy"}:
        eye_specs = [(-30, -6, 28, 34), (30, -6, 28, 34)]
        if style == "rainy":
            eye_specs = [(-30, -6, 22, 30), (30, -6, 22, 30)]
        for idx, (cx, cy, w, h) in enumerate(eye_specs):
            eye = scale_point(cx, cy, scale)
            draw.ellipse((eye[0] - w / 2 * scale, eye[1] - h / 2 * scale, eye[0] + w / 2 * scale, eye[1] + h / 2 * scale), fill=COLORS["outline"])
            shine = scale_point(cx - 6, cy - 6, scale)
            draw.ellipse((shine[0] - 4.5 * scale, shine[1] - 4.5 * scale, shine[0] + 4.5 * scale, shine[1] + 4.5 * scale), fill="#FFFFFF")
            if style == "hungry":
                draw.line((eye[0], eye[1] - 8 * scale, eye[0], eye[1] + 8 * scale), fill="#FFFFFF", width=4)
                draw.line((eye[0] - 8 * scale, eye[1], eye[0] + 8 * scale, eye[1]), fill="#FFFFFF", width=4)
    elif style in {"eating", "happy"}:
        for cx in (-30, 30):
            arc = (
                scale_point(cx - 10, -22 - 6, scale)[0],
                scale_point(cx - 10, -22 - 6, scale)[1],
                scale_point(cx + 10, -22 + 6, scale)[0],
                scale_point(cx + 10, -22 + 6, scale)[1],
            )
            draw.arc(arc, start=0, end=180, fill=COLORS["outline"], width=6)
    elif style == "sleepy":
        for cx, rot in ((-30, -8), (30, 8)):
            temp = draw_rotated_capsule(draw, scale_point(cx, -2, scale), (18 * scale, 6 * scale), rot, COLORS["outline"])
            image.alpha_composite(temp)
    elif style == "starving":
        for cx in (-28, 28):
            temp_a = draw_rotated_capsule(draw, scale_point(cx, -4, scale), (22 * scale, 4 * scale), 40, COLORS["outline"])
            temp_b = draw_rotated_capsule(draw, scale_point(cx, -4, scale), (22 * scale, 4 * scale), -40, COLORS["outline"])
            image.alpha_composite(temp_a)
            image.alpha_composite(temp_b)
    else:  # tap
        temp = draw_rotated_capsule(draw, scale_point(-28, -4, scale), (18 * scale, 5 * scale), -6, COLORS["outline"])
        image.alpha_composite(temp)
        eye = scale_point(30, -6, scale)
        draw.ellipse((eye[0] - 14 * scale, eye[1] - 17 * scale, eye[0] + 14 * scale, eye[1] + 17 * scale), fill=COLORS["outline"])
        shine = scale_point(24, -12, scale)
        draw.ellipse((shine[0] - 4.5 * scale, shine[1] - 4.5 * scale, shine[0] + 4.5 * scale, shine[1] + 4.5 * scale), fill="#FFFFFF")

    if style == "hungry":
        mouth = scale_point(0, 28, scale)
        draw.arc((mouth[0] - 10 * scale, mouth[1] - 8 * scale, mouth[0] + 10 * scale, mouth[1] + 8 * scale), 0, 180, fill=COLORS["outline"], width=6)
        draw.rounded_rectangle((mouth[0] + 8 * scale, mouth[1] + 2 * scale, mouth[0] + 12 * scale, mouth[1] + 20 * scale), radius=4 * scale, fill="#9CDDFB")
    elif style == "sleepy":
        mouth = scale_point(0, 30, scale)
        temp = draw_rotated_capsule(draw, mouth, (12 * scale, 5 * scale), 0, COLORS["outline"])
        image.alpha_composite(temp)
    elif style == "excited":
        mouth = scale_point(0, 28, scale)
        draw.ellipse((mouth[0] - 11 * scale, mouth[1] - 9 * scale, mouth[0] + 11 * scale, mouth[1] + 9 * scale), fill=COLORS["outline"])
        draw.ellipse((mouth[0] - 6 * scale, mouth[1], mouth[0] + 6 * scale, mouth[1] + 6 * scale), fill=COLORS["cheek"])
    elif style in {"eating", "happy", "idle", "rainy", "tap"}:
        mouth = scale_point(0, 24 if style in {"idle", "tap"} else 28, scale)
        draw.arc((mouth[0] - 12 * scale, mouth[1] - 8 * scale, mouth[0] + 12 * scale, mouth[1] + 8 * scale), 0, 180, fill=COLORS["outline"], width=6)
    else:
        mouth = scale_point(0, 30, scale)
        temp = draw_rotated_capsule(draw, mouth, (16 * scale, 4 * scale), 0, COLORS["outline"])
        image.alpha_composite(temp)

    if style == "excited":
        for x, y in ((-70, -64), (0, -106), (70, -64)):
            c = scale_point(x, y, scale)
            draw.line((c[0], c[1] - 9 * scale, c[0], c[1] + 9 * scale), fill=COLORS["belt_pattern"], width=6)
            draw.line((c[0] - 9 * scale, c[1], c[0] + 9 * scale, c[1]), fill=COLORS["belt_pattern"], width=6)
    if style == "sleepy":
        for x, y, r in ((48, -86, 14), (66, -108, 12), (84, -128, 10)):
            center = scale_point(x, y, scale)
            draw.ellipse((center[0] - r / 2 * scale, center[1] - r / 2 * scale, center[0] + r / 2 * scale, center[1] + r / 2 * scale), outline=COLORS["outline"], width=4)
    if style == "rainy":
        canopy = (
            scale_point(26, -84, scale)[0],
            scale_point(26, -84, scale)[1],
            scale_point(78, -60, scale)[0],
            scale_point(78, -60, scale)[1],
        )
        draw.rounded_rectangle(canopy, radius=12 * scale, fill=COLORS["umbrella"], outline=COLORS["outline"], width=4)
        x0, y0 = scale_point(52, -58, scale)
        x1, y1 = scale_point(52, -24, scale)
        draw.line((x0, y0, x1, y1), fill=COLORS["outline"], width=4)
        hook = scale_point(58, -10, scale)
        draw.arc((hook[0] - 6 * scale, hook[1] - 6 * scale, hook[0] + 6 * scale, hook[1] + 6 * scale), 30, 220, fill=COLORS["outline"], width=4)
        for x in (-54, -16, 22, 60):
            d0 = scale_point(x, -104, scale)
            d1 = scale_point(x - 4, -88, scale)
            draw.line((d0[0], d0[1], d1[0], d1[1]), fill=COLORS["rain"], width=5)
    if style == "eating":
        for x, y, rot in ((-16, 18, -20), (8, 16, 12), (20, 24, 28)):
            temp = draw_rotated_capsule(draw, scale_point(x, y, scale), (8 * scale, 4 * scale), rot, COLORS["grain"])
            image.alpha_composite(temp)
    if style == "happy":
        for x, y in ((-58, -82), (54, -78)):
            c = scale_point(x, y, scale)
            left = draw_rotated_capsule(draw, (c[0] - 6 * scale, c[1]), (10 * scale, 12 * scale), -18, COLORS["cheek"])
            right = draw_rotated_capsule(draw, (c[0] + 6 * scale, c[1]), (10 * scale, 12 * scale), 18, COLORS["cheek"])
            image.alpha_composite(left)
            image.alpha_composite(right)
            tail = [scale_point(x - 6, y + 8, scale), scale_point(x + 6, y + 8, scale), scale_point(x, y + 20, scale)]
            draw.polygon(tail, fill=COLORS["cheek"])
    if style == "starving":
        sweat = scale_point(56, 12, scale)
        temp = draw_rotated_capsule(draw, sweat, (10 * scale, 18 * scale), 18, COLORS["rain"])
        image.alpha_composite(temp)
    if style == "tap":
        bubble = scale_point(48, -94, scale)
        draw.ellipse((bubble[0] - 17 * scale, bubble[1] - 13 * scale, bubble[0] + 17 * scale, bubble[1] + 13 * scale), fill=COLORS["bubble_fill"], outline=COLORS["outline"], width=4)
        tail = [scale_point(43, -70, scale), scale_point(53, -70, scale), scale_point(47, -58, scale)]
        draw.polygon(tail, fill=COLORS["bubble_fill"], outline=COLORS["outline"])
        draw.line((bubble[0], bubble[1] - 6 * scale, bubble[0], bubble[1] + 4 * scale), fill=COLORS["outline"], width=4)
        draw.ellipse((bubble[0] - 2 * scale, bubble[1] + 8 * scale, bubble[0] + 2 * scale, bubble[1] + 12 * scale), fill=COLORS["outline"])

    return image


def contact_sheet(paths: list[Path]):
    cols = 3
    cell = 420
    rows = math.ceil(len(paths) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (255, 255, 255, 255))
    draw = ImageDraw.Draw(sheet)
    for idx, path in enumerate(paths):
        image = Image.open(path).convert("RGBA").resize((320, 320), Image.Resampling.LANCZOS)
        x = (idx % cols) * cell + 50
        y = (idx // cols) * cell + 20
        sheet.alpha_composite(image, (x, y))
        draw.text((x, 350), path.stem.replace("fantuan_", ""), fill="#333333")
    sheet.save(PREVIEW_DIR / "fantuan_contact_sheet.png")


def main():
    ANIMATION_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    preview_paths: list[Path] = []
    for name, config in STATE_CONFIG.items():
        animation = animation_json(name, config["style"], config["duration"])
        (ANIMATION_DIR / f"{name}.json").write_text(json.dumps(animation, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

        preview_path = PREVIEW_DIR / f"{name}.png"
        preview_image(config["style"]).save(preview_path)
        preview_paths.append(preview_path)

    contact_sheet(preview_paths)
    print(f"Generated {len(STATE_CONFIG)} animations in {ANIMATION_DIR}")
    print(f"Generated previews in {PREVIEW_DIR}")


if __name__ == "__main__":
    main()
