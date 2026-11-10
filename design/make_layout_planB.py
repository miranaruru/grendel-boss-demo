"""犀渠 Boss 战 · 枯树布局示意图（俯视）。
世界坐标：x 向右(东)，z 向下(南)，北(-z) 在图上方。玩家出生 (0, 9)，Boss 出生 (0, -5)，竞技场半径 18。
所有树的位置在这里手工定义（不随机），同时导出 JSON 给游戏用。
"""
import json, math, random, sys

OUT = sys.argv[1]
W = H = 1600
M = 120.0                     # 图覆盖 120m x 120m
S = W / M                     # px / m
CX, CY = W / 2 + 60, H / 2 + 30  # 稍往右下，给标题和左下角图例留位置


def P(x, z):
    return CX + x * S, CY + z * S


# ---------------- 布局定义（每组：名称、中心、树的偏移/尺寸列表） ----------------
# 尺寸：L 大树(8~11m) / M 中树(5~8m) / S 小枯树(2~4m) / T 树桩 / G 断树
rng = random.Random(7)


def cluster(cx, cz, n, spread, sizes, min_d=2.4):
    pts = []
    tries = 0
    while len(pts) < n and tries < 5000:
        tries += 1
        a = rng.random() * math.tau
        r = math.sqrt(rng.random()) * spread
        x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
        if math.hypot(x, z) < 25.5 and sizes[len(pts) % len(sizes)] in "LM":
            continue  # 大树、中树不进镜头区
        if all(math.hypot(x - p[0], z - p[1]) > min_d for p in pts):
            pts.append((x, z, sizes[len(pts) % len(sizes)]))
    return pts


def arc(r0, r1, a0, a1, n, sizes, min_d=2.6):
    pts = []
    tries = 0
    while len(pts) < n and tries < 5000:
        tries += 1
        a = math.radians(rng.uniform(a0, a1))
        r = rng.uniform(r0, r1)
        x, z = math.sin(a) * r, -math.cos(a) * r   # 角度从正北顺时针
        if all(math.hypot(x - p[0], z - p[1]) > min_d for p in pts):
            pts.append((x, z, sizes[len(pts) % len(sizes)]))
    return pts


groups = [
    # id, 名称, 说明, 树
    ("A", "北 · 枯林之墙", "Boss 身后的背景，最密", arc(27, 37, -38, 38, 14, "LMLLM", 3.0)),
    ("K", "枯王树", "全场唯一的巨树，Boss 正后方的剪影", [(0.0, -30.5, "K")]),
    ("B", "西北林", "", cluster(-25, -19, 8, 5.5, "MLMS")),
    ("C", "西林", "", cluster(-31, 4, 9, 6.0, "LMMS")),
    ("D", "东北林", "+2 根倒木", cluster(25, -21, 6, 5.0, "MLM")),
    ("E", "东 · 烧焦空地", "3 棵断树 + 4 个树桩 + 2 根倒木", [(28.0, 3.0, "G"), (31.5, 8.5, "G"), (26.5, 11.0, "G"),
                                               (29.5, 5.5, "T"), (33.0, 2.0, "T"), (27.5, 8.0, "T"), (31.0, 12.5, "T")]),
    ("F", "西南稀林", "", cluster(-23, 26, 5, 6.0, "MSM", 3.5)),
    ("G", "东南来路", "小路两侧各 3 棵", [(17.5, 22.5, "S"), (22.0, 28.0, "M"), (27.0, 33.5, "M"),
                                       (24.0, 19.0, "S"), (28.5, 24.5, "M"), (33.5, 30.0, "M")]),
    ("H", "镜头区点缀", "镜头可能经过，只放矮的", [(math.sin(math.radians(a)) * r, -math.cos(math.radians(a)) * r, k)
                                       for a, r, k in [(205, 21.0, "S"), (245, 22.5, "T"), (292, 21.5, "S"),
                                                       (62, 22.0, "S"), (110, 21.0, "T"), (160, 22.5, "S")]]),
]
logs = [(23.0, -15.5, 35), (28.5, -24.0, -20), (30.0, 9.5, 70), (25.5, 1.0, 10), (-21.0, 20.5, -40)]
far = []
for a0, a1, n in [(-60, 60, 12), (60, 150, 8), (150, 210, 5), (210, 300, 10)]:
    far += arc(42, 56, a0, a1, n, "LM", 4.0)

# ---------------- 画图 ----------------
svg = []
A = svg.append
A(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="PingFang SC, Hiragino Sans GB, sans-serif">')
A('<defs><radialGradient id="fog" cx="50%" cy="50%" r="50%"><stop offset="55%" stop-color="#2a2826" stop-opacity="0"/><stop offset="100%" stop-color="#9aa0a8" stop-opacity="0.55"/></radialGradient>'
  '<filter id="soft"><feGaussianBlur stdDeviation="6"/></filter></defs>')
A(f'<rect width="{W}" height="{H}" fill="#3b3631"/>')
# 残雪
srng = random.Random(3)
for i in range(70):
    x, z = srng.uniform(-58, 58), srng.uniform(-58, 58)
    if math.hypot(x, z) < 15:
        continue
    px, py = P(x, z)
    A(f'<ellipse cx="{px:.0f}" cy="{py:.0f}" rx="{srng.uniform(18, 60):.0f}" ry="{srng.uniform(12, 40):.0f}" fill="#d9dde2" opacity="0.13" filter="url(#soft)"/>')
# 雾边界 / 镜头区 / 战斗区
px, py = P(0, 0)
A(f'<circle cx="{px}" cy="{py}" r="{45 * S}" fill="none" stroke="#8c939c" stroke-width="2" stroke-dasharray="4 10" opacity="0.6"/>')
A(f'<circle cx="{px}" cy="{py}" r="{25.5 * S}" fill="#4a443d" fill-opacity="0.45" stroke="#c9b27a" stroke-width="2.5" stroke-dasharray="14 10"/>')
A(f'<circle cx="{px}" cy="{py}" r="{18 * S}" fill="#5a5148" stroke="#e0c98f" stroke-width="3"/>')
# 小路
pts = [P(13, 14), P(20, 21), P(26, 27), P(31, 32), P(40, 41)]
d = "M " + " L ".join(f"{x:.0f} {y:.0f}" for x, y in pts)
A(f'<path d="{d}" stroke="#6b6155" stroke-width="{3.2 * S:.0f}" stroke-linecap="round" fill="none" opacity="0.8"/>')
# 边缘石头
rr = random.Random(11)
for i in range(26):
    a = math.tau * i / 26 + rr.uniform(-0.06, 0.06)
    r = 18 + rr.uniform(0.4, 1.4)
    x, y = P(math.cos(a) * r, math.sin(a) * r)
    A(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{rr.uniform(4, 9):.0f}" fill="#8f9399" stroke="#e6e9ee" stroke-width="1.5"/>')
# 倒木
for x, z, ang in logs:
    cx, cy = P(x, z)
    A(f'<rect x="{cx - 2.0 * S:.0f}" y="{cy - 5:.0f}" width="{4.0 * S:.0f}" height="10" rx="5" fill="#6d5a47" stroke="#cfc6b8" stroke-width="1.5" transform="rotate({ang} {cx:.0f} {cy:.0f})"/>')


def tree(x, z, k, color="#141210", legend=False):
    cx, cy = P(x, z)
    if k == "T":
        A(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="7" fill="#6d5a47" stroke="#e8e1d6" stroke-width="2"/>')
        return
    if k == "G":
        A(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="9" fill="#2b241d" stroke="#d07a4a" stroke-width="2.5"/>')
        return
    r = {"S": 8, "M": 12, "L": 17, "K": 34}[k]
    n = {"S": 5, "M": 6, "L": 7, "K": 11}[k]
    # 树冠：放射状枯枝
    if legend:
        r = min(r, 14)
    for i in range(n):
        a = math.tau * i / n + (x * 0.37 + z * 0.21)
        l = r * (2.2 if k != "K" else 2.6) * (0.55 if legend else 1.0) * (0.75 + 0.25 * math.sin(i * 2.3 + x))
        A(f'<line x1="{cx:.0f}" y1="{cy:.0f}" x2="{cx + math.cos(a) * l:.0f}" y2="{cy + math.sin(a) * l:.0f}" stroke="{color}" stroke-width="{2.4 if k != "K" else 4.5}" stroke-linecap="round" opacity="0.85"/>')
    A(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r * 0.55:.0f}" fill="{color}" stroke="#e8e1d6" stroke-width="{1.5 if k != "K" else 3}"/>')


for x, z, k in far:
    tree(x, z, k, "#5d5953")
for gid, name, note, trees in groups:
    for x, z, k in trees:
        tree(x, z, k, "#0e0c0a" if gid != "K" else "#0a0807")

# 组标签
label_pos = {"A": (0, -43.5), "K": (11.0, -33.5), "B": (-27, -29.5), "C": (-42, -5.5), "D": (27, -31.0), "E": (40.0, 18.0),
             "F": (-25, 36.5), "G": (42, 37.0), "H": (-9, 30.0)}
for gid, name, note, trees in groups:
    x, y = P(*label_pos[gid])
    cnt = len([t for t in trees if t[2] in "LMSKG"])
    extra = f"  {len(trees)} 处" if gid in "EH" else f"  {cnt} 棵"
    A(f'<g><rect x="{x - 95:.0f}" y="{y - 22:.0f}" width="190" height="34" rx="8" fill="#000" opacity="0.55"/>'
      f'<text x="{x:.0f}" y="{y + 2:.0f}" fill="#f2e6c9" font-size="19" text-anchor="middle" font-weight="600">{gid} {name}{extra}</text></g>')

# 玩家 / Boss / 镜头
bx, by = P(0, -5)
A(f'<circle cx="{bx}" cy="{by}" r="{1.3 * S}" fill="#7a1f1a" stroke="#ffb36b" stroke-width="3"/>')
A(f'<text x="{bx + 26}" y="{by + 7}" fill="#ffcf9e" font-size="20">犀渠出生点</text>')
qx, qy = P(0, 9)
A(f'<polygon points="{qx},{qy - 14} {qx - 11},{qy + 10} {qx + 11},{qy + 10}" fill="#d8c27a" stroke="#fff" stroke-width="2"/>')
A(f'<text x="{qx + 18}" y="{qy + 8}" fill="#f3e3b0" font-size="20">玩家出生点</text>')
cx2, cy2 = P(0, 16.5)
A(f'<path d="M {cx2} {cy2} L {qx} {qy + 16}" stroke="#9ec7ff" stroke-width="3" stroke-dasharray="6 6"/>')
A(f'<circle cx="{cx2}" cy="{cy2}" r="6" fill="#9ec7ff"/>')
A(f'<text x="{cx2 - 14}" y="{cy2 + 6}" fill="#9ec7ff" font-size="17" text-anchor="end">镜头（玩家身后 7.5m）</text>')
# 圈标签
for txt, z, col in [("战斗区 半径 18m：不放树（只散几根枯枝装饰）", -14.0, "#e0c98f"), ("镜头区 18~25.5m：只放矮的（小枯树 / 树桩 / 倒木）", -22.3, "#c9b27a"), ("雾线 ≈45m：外面只剩灰色剪影", -46.2, "#aab1ba")]:
    x, y = P(0, z)
    A(f'<text x="{x}" y="{y}" fill="{col}" font-size="18" text-anchor="middle" stroke="#2a2622" stroke-width="4" paint-order="stroke">{txt}</text>')
# 指北针 / 比例尺
A('<g transform="translate(1530,150)"><polygon points="0,-38 12,8 0,0 -12,8" fill="#e8e1d6"/><text x="0" y="34" fill="#e8e1d6" font-size="20" text-anchor="middle">北</text></g>')
A(f'<line x1="1430" y1="230" x2="{1430 + 10 * S:.0f}" y2="230" stroke="#e8e1d6" stroke-width="4"/><text x="{1430 + 5 * S:.0f}" y="258" fill="#e8e1d6" font-size="18" text-anchor="middle">10 米</text>')
# 标题
A('<rect x="0" y="0" width="1600" height="78" fill="#1f1d1b" opacity="0.92"/>')
A('<text x="800" y="52" fill="#f2e6c9" font-size="34" text-anchor="middle" font-weight="700">犀渠 Boss 战 · 枯树布局示意（俯视，手工定点，不随机）</text>')
# 左下：图例
near = sum(len([t for t in g[3] if t[2] in "LMSKG"]) for g in groups)
stumps = sum(len([t for t in g[3] if t[2] == "T"]) for g in groups)
A('<rect x="20" y="1120" width="420" height="465" rx="14" fill="#141210" opacity="0.9" stroke="#5a5148"/>')
A('<text x="44" y="1160" fill="#f2e6c9" font-size="22" font-weight="700">图例</text>')
items = [("K", "枯王树（全场唯一巨树）"), ("L", "大枯树 8~11 米"), ("M", "中枯树 5~8 米"), ("S", "小枯树 2~4 米"), ("G", "烧焦断树"), ("T", "树桩")]
for i, (k, t) in enumerate(items):
    ly = 1205 + i * 42
    tree(((80 - CX) / S), ((ly - CY) / S), k, legend=True)
    A(f'<text x="130" y="{ly + 7}" fill="#e8e1d6" font-size="19">{t}</text>')
ly = 1205 + 6 * 42
A(f'<rect x="58" y="{ly - 6}" width="44" height="12" rx="6" fill="#6d5a47" stroke="#cfc6b8"/><text x="130" y="{ly + 7}" fill="#e8e1d6" font-size="19">倒木 ×{len(logs)}</text>')
ly += 42
A(f'<circle cx="80" cy="{ly}" r="7" fill="#8f9399" stroke="#e6e9ee"/><text x="130" y="{ly + 7}" fill="#e8e1d6" font-size="19">边缘石头 ×26（已有，不变）</text>')
ly += 42
A(f'<circle cx="80" cy="{ly}" r="8" fill="#5d5953"/><text x="130" y="{ly + 7}" fill="#e8e1d6" font-size="19">雾里的远景树（灰色剪影）</text>')
# 右下：统计 + 设计意图
A('<rect x="1020" y="1330" width="560" height="250" rx="14" fill="#141210" opacity="0.88" stroke="#5a5148"/>')
lines = [("统计", "#f2e6c9", 22, True),
         (f"近景枯树 {near} 棵 · 树桩 {stumps} 个 · 倒木 {len(logs)} 根", "#e8e1d6", 19, False),
         (f"远景剪影 {len(far)} 棵（北 12 / 东 8 / 南 5 / 西 10）", "#e8e1d6", 19, False),
         ("北面最密：Boss 身后的「枯林之墙」+ 枯王树剪影", "#bdb6aa", 18, False),
         ("南面最稀：玩家 / 镜头这一侧，不挡视线", "#bdb6aa", 18, False),
         ("东侧烧焦空地 + 东南进场小路，打破对称", "#bdb6aa", 18, False),
         ("每一棵坐标已固定（tree_layout.json）", "#9ec7ff", 18, False)]
for i, (t, c, fs, b) in enumerate(lines):
    A(f'<text x="1044" y="{1370 + i * 31}" fill="{c}" font-size="{fs}" font-weight="{700 if b else 400}">{t}</text>')
A('</svg>')
open(OUT + ".svg", "w").write("\n".join(svg))

data = {"arena_radius": 18, "groups": [{"id": g[0], "name": g[1], "note": g[2], "trees": [{"x": round(t[0], 2), "z": round(t[1], 2), "kind": t[2]} for t in g[3]]} for g in groups],
        "logs": [{"x": l[0], "z": l[1], "angle_deg": l[2]} for l in logs],
        "far": [{"x": round(t[0], 2), "z": round(t[1], 2), "kind": t[2]} for t in far]}
json.dump(data, open(OUT + ".json", "w"), ensure_ascii=False, indent=1)
print("near", near, "stumps", stumps, "far", len(far))
