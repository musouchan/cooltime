#!/usr/bin/env python3
"""characters/menubar/*.svg と characters/motion.json から、Swift のデータ
（Sources/Cooltime/CharacterData.swift）を作る。

SVG を実行時に読むのをやめて、あらかじめ「パスの列」に変換しておく：
  - 円・楕円・長方形・多角形・パスを、すべて M / L / C / Z だけの絶対座標のパスにそろえる
    （円弧 A と 二次ベジェ Q は、三次ベジェ C に直す。回転した楕円は、回転を焼き込む）
  - 動かすグループ（root / look / eyes / zz）の外枠から、回転・拡大の原点を計算しておく
Swift 側は、パスを塗るだけで済む。使い方: python3 scripts/gen_characters.py
"""
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "characters"
OUT = ROOT / "Sources" / "Cooltime" / "CharacterData.swift"
NS = "{http://www.w3.org/2000/svg}"
TRACKED = {"root", "look", "eyes", "zz"}
ORDER = ["bunny", "cat", "bear", "pig", "frog"]
NAMES = {"bunny": "うさぎ", "cat": "ねこ", "bear": "くま", "pig": "ぶた", "frog": "かえる"}
STATES = ["ok", "limit", "fail"]
K = 0.5522847498307936  # 円を4本の三次ベジェで描く定数


def f(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---- パスの組み立て（M / L / C / Z）----------------------------------------
class P:
    def __init__(self):
        self.cmds = []  # ("M", [x,y]) ("L", [x,y]) ("C", [x1,y1,x2,y2,x,y]) ("Z", [])

    def m(self, x, y): self.cmds.append(("M", [x, y]))
    def l(self, x, y): self.cmds.append(("L", [x, y]))
    def c(self, *a): self.cmds.append(("C", list(a)))
    def z(self): self.cmds.append(("Z", []))

    def transform(self, fn):
        out = P()
        for op, a in self.cmds:
            pts = [fn(a[i], a[i + 1]) for i in range(0, len(a), 2)]
            out.cmds.append((op, [v for p in pts for v in p]))
        return out

    def text(self):
        return " ".join(op + (" " + " ".join(f(v) for v in a) if a else "") for op, a in self.cmds)

    def points(self):
        """外枠の計算用に、曲線を細かく刻んだ点を返す。"""
        pts, cur = [], (0.0, 0.0)
        for op, a in self.cmds:
            if op in ("M", "L"):
                cur = (a[0], a[1]); pts.append(cur)
            elif op == "C":
                p0 = cur
                for i in range(1, 17):
                    t = i / 16
                    u = 1 - t
                    x = u**3 * p0[0] + 3 * u * u * t * a[0] + 3 * u * t * t * a[2] + t**3 * a[4]
                    y = u**3 * p0[1] + 3 * u * u * t * a[1] + 3 * u * t * t * a[3] + t**3 * a[5]
                    pts.append((x, y))
                cur = (a[4], a[5])
        return pts


def ellipse(cx, cy, rx, ry):
    p = P()
    p.m(cx + rx, cy)
    p.c(cx + rx, cy + K * ry, cx + K * rx, cy + ry, cx, cy + ry)
    p.c(cx - K * rx, cy + ry, cx - rx, cy + K * ry, cx - rx, cy)
    p.c(cx - rx, cy - K * ry, cx - K * rx, cy - ry, cx, cy - ry)
    p.c(cx + K * rx, cy - ry, cx + rx, cy - K * ry, cx + rx, cy)
    p.z()
    return p


def rect(x, y, w, h, rx, ry):
    rx = min(rx, w / 2); ry = min(ry or rx, h / 2)
    p = P()
    if rx <= 0:
        p.m(x, y); p.l(x + w, y); p.l(x + w, y + h); p.l(x, y + h); p.z()
        return p
    p.m(x + rx, y)
    p.l(x + w - rx, y)
    p.c(x + w - rx + K * rx, y, x + w, y + ry - K * ry, x + w, y + ry)
    p.l(x + w, y + h - ry)
    p.c(x + w, y + h - ry + K * ry, x + w - rx + K * rx, y + h, x + w - rx, y + h)
    p.l(x + rx, y + h)
    p.c(x + rx - K * rx, y + h, x, y + h - ry + K * ry, x, y + h - ry)
    p.l(x, y + ry)
    p.c(x, y + ry - K * ry, x + rx - K * rx, y, x + rx, y)
    p.z()
    return p


def arc_to_cubics(x1, y1, rx, ry, phi_deg, large, sweep, x2, y2):
    """SVG の円弧（端点表記）を、三次ベジェの列にする。"""
    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2):
        return [(x1, y1, x2, y2, x2, y2)]
    phi = math.radians(phi_deg)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = (x1p**2) / (rx**2) + (y1p**2) / (ry**2)
    if lam > 1:
        s = math.sqrt(lam); rx *= s; ry *= s
    num = rx**2 * ry**2 - rx**2 * y1p**2 - ry**2 * x1p**2
    den = rx**2 * y1p**2 + ry**2 * x1p**2
    co = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    th1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dth = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dth > 0: dth -= 2 * math.pi
    if sweep and dth < 0: dth += 2 * math.pi
    n = max(1, math.ceil(abs(dth) / (math.pi / 2) - 1e-9))
    d = dth / n
    t = 4 / 3 * math.tan(d / 4)
    out = []
    for i in range(n):
        a1 = th1 + i * d
        a2 = a1 + d
        def pt(a, dx_=0, dy_=0):
            x = rx * math.cos(a); y = ry * math.sin(a)
            return x, y
        p1 = (rx * (math.cos(a1) - t * math.sin(a1)), ry * (math.sin(a1) + t * math.cos(a1)))
        p2 = (rx * (math.cos(a2) + t * math.sin(a2)), ry * (math.sin(a2) - t * math.cos(a2)))
        p3 = (rx * math.cos(a2), ry * math.sin(a2))
        def tr(p): return (cp * p[0] - sp * p[1] + cx, sp * p[0] + cp * p[1] + cy)
        c1, c2, e = tr(p1), tr(p2), tr(p3)
        out.append((c1[0], c1[1], c2[0], c2[1], e[0], e[1]))
    return out


def parse_path(d):
    toks = re.findall(r"[MLHVCQAZ]|-?\d*\.?\d+(?:e-?\d+)?", d)
    p = P()
    i, cur, start, cmd = 0, (0.0, 0.0), (0.0, 0.0), None

    def num(n):
        nonlocal i
        vals = [float(toks[i + k]) for k in range(n)]
        i += n
        return vals
    while i < len(toks):
        if re.fullmatch(r"[MLHVCQAZ]", toks[i]):
            cmd = toks[i]; i += 1
            if cmd == "Z":
                p.z(); cur = start
                continue
        if cmd == "M":
            x, y = num(2); p.m(x, y); cur = start = (x, y); cmd = "L"
        elif cmd == "L":
            x, y = num(2); p.l(x, y); cur = (x, y)
        elif cmd == "H":
            (x,) = num(1); p.l(x, cur[1]); cur = (x, cur[1])
        elif cmd == "V":
            (y,) = num(1); p.l(cur[0], y); cur = (cur[0], y)
        elif cmd == "C":
            a = num(6); p.c(*a); cur = (a[4], a[5])
        elif cmd == "Q":
            qx, qy, x, y = num(4)
            p.c(cur[0] + 2 / 3 * (qx - cur[0]), cur[1] + 2 / 3 * (qy - cur[1]),
                x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y), x, y)
            cur = (x, y)
        elif cmd == "A":
            rx, ry, rot, large, sweep, x, y = num(7)
            for c in arc_to_cubics(cur[0], cur[1], rx, ry, rot, int(large), int(sweep), x, y):
                p.c(*c)
            cur = (x, y)
        else:
            raise SystemExit(f"未対応のパス命令: {cmd}")
    return p


def rotate_fn(deg, cx, cy):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    return lambda x, y: (cx + c * (x - cx) - s * (y - cy), cy + s * (x - cx) + c * (y - cy))


# ---- SVG を読む -----------------------------------------------------------
def read_svg(path):
    root = ET.parse(path).getroot()
    elements, boxes = [], {}

    def walk(node, chain):
        for ch in node:
            tag = ch.tag.replace(NS, "")
            if tag == "g":
                gid = ch.get("id")
                walk(ch, chain + [gid] if gid in TRACKED else chain)
                continue
            a = ch.attrib
            if tag == "circle":
                shape = ellipse(float(a["cx"]), float(a["cy"]), float(a["r"]), float(a["r"]))
            elif tag == "ellipse":
                shape = ellipse(float(a["cx"]), float(a["cy"]), float(a["rx"]), float(a["ry"]))
            elif tag == "rect":
                rx = float(a.get("rx", 0))
                shape = rect(float(a["x"]), float(a["y"]), float(a["width"]), float(a["height"]), rx, float(a.get("ry", rx)))
            elif tag == "polygon":
                pts = [tuple(map(float, q.split(","))) for q in a["points"].split()]
                shape = P(); shape.m(*pts[0])
                for q in pts[1:]: shape.l(*q)
                shape.z()
            elif tag == "path":
                shape = parse_path(a["d"])
            else:
                raise SystemExit(f"未対応の要素: {tag}")
            m = re.fullmatch(r"rotate\(([-\d.]+) ([-\d.]+) ([-\d.]+)\)", a.get("transform", ""))
            if m:
                shape = shape.transform(rotate_fn(float(m[1]), float(m[2]), float(m[3])))
            elif a.get("transform"):
                raise SystemExit(f"未対応の transform: {a['transform']}")
            fill = a.get("fill", "currentColor")
            stroke_color = a.get("stroke")
            el = {
                "chain": chain,
                "cutout": a.get("data-cutout") == "true",
                "fill": fill not in ("none",),
                "stroke": float(a["stroke-width"]) if stroke_color and stroke_color != "none" else 0.0,
                "round": a.get("stroke-linecap") == "round" or a.get("stroke-linejoin") == "round",
                "opacity": float(a.get("opacity", 1)),
                "path": shape.text(),
            }
            elements.append(el)
            if not el["cutout"]:  # 外枠は、抜き以外の形から取る
                for g in chain:
                    boxes.setdefault(g, []).extend(shape.points())
    walk(root, [])
    origins = {}
    for g, pts in boxes.items():
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        cx = (min(xs) + max(xs)) / 2
        # root は下中央、ほかは中央（motion.json の約束）
        origins[g] = (cx, max(ys) if g == "root" else (min(ys) + max(ys)) / 2)
    return elements, origins


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    motion = json.loads((SRC / "motion.json").read_text(encoding="utf-8"))
    out = ["// 自動生成: scripts/gen_characters.py（characters/menubar/*.svg と characters/motion.json から）。",
           "// 直接は編集しない。絵や動きを変えたら、スクリプトを実行し直す。", "",
           "enum CharacterData {",
           f"    static let ids: [String] = [{', '.join(swift_str(i) for i in ORDER)}]",
           "    static let names: [String: String] = [" + ", ".join(f"{swift_str(k)}: {swift_str(v)}" for k, v in NAMES.items()) + "]",
           "", "    /// \"id-state\" → 描く順の部品", "    static let shapes: [String: [CharElement]] = ["]
    origins_out = []
    for cid in ORDER:
        for st in STATES:
            els, origins = read_svg(SRC / "menubar" / f"{cid}-{st}.svg")
            key = f"{cid}-{st}"
            out.append(f"        {swift_str(key)}: [")
            for e in els:
                chain = "[" + ", ".join(swift_str(g) for g in e["chain"]) + "]"
                out.append(f"            CharElement(chain: {chain}, cutout: {str(e['cutout']).lower()}, fill: {str(e['fill']).lower()}, "
                           f"stroke: {f(e['stroke'])}, round: {str(e['round']).lower()}, opacity: {f(e['opacity'])}, path: {swift_str(e['path'])}),")
            out.append("        ],")
            o = ", ".join(f"{swift_str(g)}: [{f(x)}, {f(y)}]" for g, (x, y) in sorted(origins.items()))
            origins_out.append(f"        {swift_str(key)}: [{o}],")
    out += ["    ]", "", "    /// \"id-state\" → グループ名 → 回転・拡大の原点 [x, y]", "    static let origins: [String: [String: [Double]]] = ["]
    out += origins_out
    out += ["    ]", "", "    /// characters/motion.json の中身（そのまま）", "    static let motionJSON = #\"\"\"",
            json.dumps(motion, ensure_ascii=False, indent=1), "\"\"\"#", "}", "",
            "struct CharElement {",
            "    /// 外側から順に、この部品にかかる動かすグループ（root / look / eyes / zz）",
            "    let chain: [String]",
            "    /// 「抜き」（透明にくり抜く）",
            "    let cutout: Bool",
            "    let fill: Bool",
            "    /// 線の太さ（0 なら線なし）",
            "    let stroke: Double",
            "    /// 線の端と角を丸くする",
            "    let round: Bool",
            "    let opacity: Double",
            "    /// M / L / C / Z だけの絶対座標のパス（viewBox は -6 -6 112 112）",
            "    let path: String",
            "}", ""]
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"書き出しました: {OUT.relative_to(ROOT)}（{len(ORDER) * len(STATES)} 通り）", file=sys.stderr)


if __name__ == "__main__":
    main()
