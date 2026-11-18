"""Draw the six original IVE pixel characters. Run with Pillow to rebuild their PNGs."""
from dataclasses import dataclass
from math import cos, pi, sin
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "assets-local"
ROWS = (6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8)
INK = "#332c47"
BLUSH = "#f4a6b4"
PEARL = "#fff9ed"


@dataclass(frozen=True)
class Character:
    name: str
    fur: str
    shade: str


CREW = (
    Character("green-clip", "#fff3d8", "#dfcbb5"),
    Character("bell-tail", "#fac58e", "#d99775"),
    Character("bow-chick", "#ffe28a", "#e3b269"),
    Character("pink-clip", "#fff9fa", "#ddcee0"),
    Character("heart-cheek", "#fff8e8", "#e0cac3"),
    Character("green-charm", "#f9c9d9", "#dfabbe"),
)


class PixelPen:
    """Cubic contours sampled onto a single low-resolution pixel grid."""
    def __init__(self, image, x=0, y=0):
        self.image = image
        self.draw = ImageDraw.Draw(image)
        self.x, self.y = x, y

    def offset(self, x, y):
        return PixelPen(self.image, self.x + x, self.y + y)

    def point(self, x, y):
        return round(self.x + x), round(self.y + y)

    def oval(self, box, color, edge=None, width=1):
        x, y, r, b = box
        self.draw.ellipse((self.point(x, y), self.point(r, b)), color, edge, width)

    def path(self, coords, color=None, edge=INK, width=1):
        # Start point followed by straight endpoints or cubic control/control/end triples.
        x, y = coords[0]
        points = [self.point(x, y)]
        for step in coords[1:]:
            if len(step) == 2:
                x, y = step
                points.append(self.point(x, y))
            else:
                a, b, c, d, e, f = step
                for i in range(1, 13):
                    t = i / 12
                    s = 1 - t
                    points.append(self.point(s**3*x + 3*s*s*t*a + 3*s*t*t*c + t**3*e,
                                             s**3*y + 3*s*s*t*b + 3*s*t*t*d + t**3*f))
                x, y = e, f
        if color:
            self.draw.polygon(points, color)
            points.append(points[0])
        if edge is not None:
            self.draw.line(points, edge, width, joint="curve")


def heart(p, x, y, tint, large=True):
    pen = p.offset(x, y)
    if large:
        pen.path([(0, 2), (-5, -1, -6, -5, -3, -5), (-1, -6, 0, -4, 0, -4),
                  (4, -8, 8, -3, 0, 2)], tint)
        pen.oval((-3, -4, -2, -3), PEARL)
    else:
        pen.path([(-2, -1), (-1, -2), (0, -1), (1, -2), (2, -1), (0, 1)], tint, None)


def gem(p, box, base, glint):
    p.oval(box, base, INK)
    x, y = box[:2]
    p.oval((x+2, y+1, x+3, y+2), glint)


def ear(p, k, left, bounce):
    # Mirrored construction leaves bows, badges, facial markings and the tail asymmetric.
    def pts(coords):
        return [tuple(n if i % 2 or left else 64-n for i, n in enumerate(step)) for step in coords]
    def shape(coords, color, edge=INK, width=1):
        p.path(pts(coords), color, edge, width)
    if k.name in ("green-clip", "pink-clip"):
        end = 44 if k.name == "green-clip" else 57
        shape([(24, 22), (18, 17, 14, 23, 12, 31), (10, 37, 8, end-4, 10, end),
               (14, end+5, 21, end+2, 22, end-3), (25, 36, 27, 29, 24, 22)], k.fur, width=2)
        shape([(11, end-4), (13, end+1, 18, end+1, 21, end-4),
               (20, end+2, 13, end+4, 11, end-1)], k.shade, None)
    elif k.name == "bow-chick":
        shape([(22, 23), (19, 15, 12, 17, 11, 24), (10, 27),
               (6, 35, 14, 39, 20, 32), (23, 26)], k.fur, width=2)
        shape([(10, 30), (13, 36, 16, 34, 19, 31)], None, k.shade)
    elif k.name == "green-charm":
        shape([(25, 24), (22, 14, 12, 16, 12, 24), (10, 32, 20, 35, 23, 30)], k.fur, width=2)
        shape([(21, 23), (17, 17, 13, 22, 15, 27), (17, 30), (21, 30)], "#fff0f2", None)
    else:
        lift = 2 if k.name == "bell-tail" else 0
        tip = 16-lift+bounce
        shape([(15, 31), (14, 25, 14, tip+3, 16, tip), (18, tip-2, 24, tip+3, 27, 23),
               (24, 30)], k.fur if k.name == "bell-tail" else "#f5ca82", width=2)
        shape([(17, 25), (17, tip+4), (19, tip+1, 22, 22, 23, 24)], "#f0a798", None)


def head(p, k, gaze_x, gaze_y, blink, ear_bob):
    for left in (True, False):
        ear(p, k, left, ear_bob)
    face = [(32, 18), (43, 18, 49, 26, 50, 36), (52, 45, 46, 49, 33, 49),
            (20, 50, 13, 46, 14, 37), (14, 26, 20, 18, 32, 18)]
    if k.name == "heart-cheek":
        face = [(31, 19), (40, 18, 45, 18, 49, 24), (51, 29, 52, 40, 49, 44),
                (46, 49, 38, 50, 32, 50), (23, 50, 15, 48, 14, 43),
                (12, 37, 13, 27, 16, 23), (18, 19, 25, 18, 31, 19)]
    elif k.name == "bow-chick":
        face = [(32, 18), (46, 18, 50, 26, 50, 35), (50, 40, 51, 45, 47, 47),
                (40, 50, 25, 49, 19, 47), (14, 46, 14, 43, 14, 37),
                (13, 26, 19, 18, 32, 18)]
    p.path(face, k.fur, width=2)
    p.path([(16, 41), (20, 47, 44, 49, 49, 40), (49, 46, 42, 48, 33, 48),
            (23, 48, 18, 46, 16, 43)], k.shade, None)
    f = p.offset(gaze_x, gaze_y)
    if k.name in ("bell-tail", "heart-cheek", "green-charm"):
        # Clip markings to the head so the up/down poses retain a clean silhouette.
        layer = Image.new("RGBA", p.image.size)
        m = PixelPen(layer, f.x, f.y)
        if k.name == "heart-cheek":
            m.path([(6, 14), (56, 14), (56, 34), (50, 37, 46, 35, 44, 31),
                    (42, 36, 33, 36, 31, 29), (29, 35, 22, 36, 20, 32),
                    (17, 35, 11, 36, 6, 33)], "#f5ca82", None)
        else:
            if k.name == "bell-tail":
                m.path([(5, 42), (14, 41, 17, 38, 20, 34), (24, 29, 29, 31, 32, 37),
                        (37, 30, 42, 29, 46, 35), (51, 41), (57, 41), (56, 51), (5, 51)], "#fff6e9", None)
            else:
                m.path([(7, 40), (16, 39, 22, 41, 27, 42), (30, 38, 34, 38, 38, 41),
                        (43, 42, 46, 39, 55, 40), (56, 50), (8, 50)], "#fff0f3", None)
            for x in (29, 34):
                m.path([(x, 15), (x+3, 16), (x+2, 24, x+1, 27, x, 27), (x-1, 23)], k.shade, None)
        mask = Image.new("L", p.image.size)
        PixelPen(mask, p.x, p.y).path(face, 255, 0, 3)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", layer.size), mask))
        p.image.alpha_composite(layer)
    else:
        for x in (26, 30):
            f.path([(x, 25), (x-1, 27, x, 30, x+3, 30)], None, k.shade)
    # Floppy ears join the crown with a narrow arc, while the bows sit on top.
    if k.name in ("green-clip", "pink-clip"):
        for sign in (-1, 1):
            x = 32 + sign*15
            p.path([(x, 29), (x-sign*3, 33, x-sign, 40, x+sign, 43)], None, "#9e889d")
    if k.name in ("green-clip", "pink-clip"):
        x = 40 if k.name == "green-clip" else 32
        base, light = ("#8bc871", "#e4faa8") if k.name == "green-clip" else ("#ee80a8", "#ffdbdf")
        gem(p, (x, 17, x+6, 23), base, light)
        gem(p, (x-5, 16, x+1, 23), base, light)
    if k.name == "bow-chick":
        p.path([(40, 20), (35, 13, 32, 20, 36, 24), (40, 23), (45, 28, 49, 24, 46, 21),
                (44, 19)], "#b394d7", width=1)
        gem(p, (38, 18, 43, 23), "#efbc64", "#ffedaa")
    for sign in (-1, 1):
        x = 32 + sign*8
        f.oval((x-4, 40, x-1, 42) if sign < 0 else (x+1, 40, x+4, 42), BLUSH)
        if blink:
            f.path([(x-3, 37), (x-2, 39, x+1, 39, x+3, 37)], None, INK, 2)
        else:
            f.oval((x-3, 33, x+3, 39), INK)
            f.oval((x-1, 37, x+1, 38), "#796076")
            f.oval((x, 34, x+1, 35), PEARL)
            if k.name != "green-clip":
                f.path([(x+sign*2, 35), (x+sign*4, 34)], None, INK)
    if k.name == "bow-chick":
        f.oval((29, 39, 35, 43), "#f3a76b", INK)
        f.path([(30, 41), (34, 41)], None, "#ab705d")
    else:
        f.oval((31, 39, 33, 40), INK)
        f.path([(28, 42), (29, 44, 31, 44, 32, 42), (33, 44, 35, 44, 36, 42)], None, INK)
    if k.name == "heart-cheek":
        heart(f, 43, 42, "#ee9d94", False)
    for x in {"bow-chick": (24,), "pink-clip": (42,), "green-charm": (20, 44), "bell-tail": (36,)}.get(k.name, ()):
        f.oval((x, 44, x, 44), INK)


def frame(k, row, col):
    phase = 2*pi*col/ROWS[row]
    wave = sin(phase)
    look_x = look_y = travel = step = lift = lean = nod = 0
    blink = False
    left_arm = right_arm = 0
    if row == 0:                           # breath and blink
        lift = (0, 1, 2, 2, 1, 0)[col]
        nod = (0, 0, -1, 0, 0, 1)[col]
        blink = col == 3
    elif row in (1, 2):                    # two walking directions
        direction = 1 if row == 1 else -1
        step, travel = round(3*wave), round(2*wave)*direction
        lift, lean = round(3*abs(wave)), direction
        look_x = 3*direction
        left_arm, right_arm = step, -step
    elif row == 3:                         # one-handed wave
        right_arm = (0, -4, -8, -5)[col]
        lean = (0, -1, 0, 1)[col]
    elif row == 4:                         # jump with anticipation and landing
        lift = (0, 4, 10, 5, 0)[col]
        nod = (1, 0, -1, 0, 2)[col]
        left_arm = right_arm = -lift//2
    elif row == 5:                         # sleepy crouch
        nod = (0, 1, 2, 4, 5, 3, 2, 0)[col]
        lift = -(nod//3)
        blink = 2 <= col <= 6
        lean = (0, 0, -1, -1, 0, 1, 1, 0)[col]
    elif row == 6:                         # cheerful two-paw sway
        lean = (0, -2, -3, 0, 3, 2)[col]
        left_arm, right_arm = -4+lean, -4-lean
        lift = round(2*abs(wave))
    elif row == 7:                         # paw to cheek
        left_arm = (0, -3, -6, -7, -5, -2)[col]
        lean = -round(2*sin(pi*col/5))
        blink = col == 4
    elif row == 8:                         # nod and recover
        nod = (0, 1, 3, 4, 2, 0)[col]
        look_y = (0, 1, 2, 3, 2, 1)[col]
        blink = col in (3, 4)
    else:
        angle = ((row-9)*8 + col)*pi/8
        look_x, look_y = round(4*sin(angle)), -round(4*cos(angle))

    canvas = Image.new("RGBA", (64, 70))
    body = PixelPen(canvas, travel, -lift)
    if k.name == "bell-tail":
        tail = body.offset(0, round(wave) if row < 9 else 0)
        tail.path([(41, 53), (48, 53, 47, 42, 52, 42), (58, 41, 57, 52, 54, 55),
                   (51, 59, 45, 59, 41, 57)], k.fur, width=2)
        tail.path([(48, 55), (52, 54, 54, 50, 54, 47)], None, k.shade)
    for side in (-1, 1):
        x = 32 + side*6 + side*step//2
        stride = round(3*cos(phase))*side if row in (1, 2) else 0
        foot = body.offset(x, -max(0, stride))
        foot.oval((-4, 57, 4, 65), k.shade, INK, 2)
        foot.oval((-2, 60, 2, 63), k.fur)
    body.oval((20, 40, 44, 62), k.shade, INK, 2)
    body.oval((22, 41, 42, 59), k.fur)
    if k.name in ("bell-tail", "heart-cheek", "green-charm"):
        accent = {"bell-tail": "#68b9d4", "heart-cheek": "#efc86b", "green-charm": "#c89dab"}[k.name]
        body.path([(22, 46), (27, 51, 37, 51, 42, 46), (41, 49),
                   (37, 53, 27, 53, 23, 49)], accent)
    head(body.offset(lean, nod), k, look_x, look_y, blink, round(wave) if row in (1, 2) else 0)
    # The reference's heart between the paws is held in idle and released for gestures.
    for sign, reach in ((-1, left_arm), (1, right_arm)):
        arm = body.offset(0, reach)
        if reach < -2:
            x = 32 + sign*13
            arm.oval((x-3, 51, x+3, 57), k.fur, INK)
        else:
            x = 32 + sign*7
            arm.oval((x-5, 51, x+5, 57), k.fur, INK)
            arm.path([(x-2, 55), (x+1, 56)], None, k.shade)
    if k.name in ("bell-tail", "heart-cheek", "green-charm"):
        pendant = {"bell-tail": "#f7c356", "heart-cheek": "#eb9763", "green-charm": "#95c85c"}[k.name]
        gem(body, (30, 49, 34, 53), pendant, PEARL)
    heart(body, 32, 59 + (1 if row == 0 and col == 2 else 0), "#f08fa5")
    return canvas.resize((192, 210), Image.Resampling.NEAREST).crop((0, 0, 192, 208))


if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    for character in CREW:
        sheet = Image.new("RGBA", (1536, 2288))
        for row_index, count in enumerate(ROWS):
            for column in range(count):
                sheet.paste(frame(character, row_index, column), (192*column, 208*row_index))
        sheet.save(ROOT / f"skin-ive-{character.name}.png", optimize=True)
