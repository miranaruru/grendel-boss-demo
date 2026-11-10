@tool
class_name TreeLayout
extends Node3D
## 手工定点的树（方案 A）：每一棵的位置 / 大小来自 LAYOUT_JSON，不随机。
## ZONE_MODELS 定每个区用 assets/env/sketchfab/ 下哪个模型文件夹；文件夹不存在时自动用代码生成的枯树顶替。
## 「一个文件里一排好几棵树」的套装（SPLIT_PACKS）会按空隙切成单棵，每个位置按树的编号挑一棵。
## A1（王座位置）放一组废墟：a1_group；石台外的乱石、长条岩等固定摆放：props。

const ArenaBuilder = preload("res://scripts/arena_builder.gd")

const LAYOUT_JSON := "res://assets/env/tree_layout_v3.json"  # 布局 v3：近景树分 6 簇、留环形通道（v2、方案 A 的文件都还留着）
const LEDGES_JSON := "res://assets/env/ledges_v1.json"  # 石台边上的石头小台子
const MODEL_DIR := "res://assets/env/sketchfab/"
# 区 → 模型文件夹
const ZONE_MODELS := {
	"B": "old_tree",
	"C": "dead_trees_demo",
	"G": "dead_trees_demo",
	"D": "spooky_tree",
	"E": "dead_trees",
	"H": "dead_trees",
	"F": "4k_tree_stump_megascan",
}
const SPLIT_PACKS := ["dead_trees_demo", "dead_trees"]  # 一排多棵的套装：切开用
const STUMP_MODEL := "burnt_stump"
# 大小 → 模型的目标高度（米）/ 代码枯树的尺寸系数
const TARGET_HEIGHT := {"S": 3.5, "M": 6.0, "L": 9.0, "XL": 13.0}
const ZONE_HEIGHT_SCALE := {"F": 0.5}   # F 区是断树干，矮一些
const PROC_SIZE := {"S": 0.6, "M": 0.9, "L": 1.25, "XL": 1.6}
const STUMP_HEIGHT := 1.0
const LEAN := 0.28  # D1 倾斜孤树的倾斜角（弧度）
# 能跑到的范围（和 main.gd 的 PLAY_RADIUS 一致）。在这里面的树 / 灯 / 拱门带碰撞、能被 Boss 打坏；外面的只是远景
const PLAY_RADIUS := 26.0
const TRUNK := {"S": 0.25, "M": 0.35, "L": 0.5, "XL": 0.8}   # 树干碰撞半径
const TREE_HP := {"S": 1.0, "M": 2.0, "L": 3.0, "XL": 4.0}   # 能挨几下；S 号的小树 Boss 走路撞上就断
const LAMP_LIGHT := Color(1.0, 0.72, 0.42)

@export_tool_button("重新生成", "Reload") var regenerate_button := regenerate

var _cache := {}
var _variants := {}


func _ready() -> void:
	regenerate()


func regenerate() -> void:
	for c in get_children():
		c.free()
	ArenaBuilder.ensure_materials()
	var f := FileAccess.open(LAYOUT_JSON, FileAccess.READ)
	if f == null:
		push_warning("找不到树的布局文件：" + LAYOUT_JSON)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var near_trees := []
	var obstacles := []  # 拱门、灯
	for t in data["trees"]:
		if t.get("ruins", false):
			_a1_group(data.get("a1_group", []), Vector3(t["x"], 0.0, t["z"]))
			continue
		var vis := Node3D.new()
		vis.rotation.y = _hash01(t["id"]) * TAU
		if t.get("leaning", false):
			vis.rotation.z = LEAN  # 往一边歪
		var folder: String = t.get("model", ZONE_MODELS.get(t["zone"], ""))
		var h: float = TARGET_HEIGHT[t["size"]] * ZONE_HEIGHT_SCALE.get(t["zone"], 1.0)
		if not _model(vis, folder, t["id"], h, 0.0, true):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(t["id"])
			ArenaBuilder.make_tree(vis, Vector3.ZERO, rng, PROC_SIZE[t["size"]])
		var node: Node3D = vis
		var near: bool = not t.get("far", false) and _reachable(t["x"], t["z"])  # 远景树只是背景，没有碰撞
		if near:
			node = Destructible.make_tree(vis, TRUNK[t["size"]], h, TREE_HP[t["size"]], t["size"] == "S")
			var cb := _bounds(vis, vis.find_children("*", "MeshInstance3D", true, false))
			node.canopy = clampf(maxf(cb.size.x, cb.size.z) * 0.5, 0.8, 6.0)
			near_trees.append(node)
		node.name = t["id"]
		add_child(node)
		node.position = Vector3(t["x"], ArenaBuilder.ground_height(t["x"], t["z"]), t["z"])
	for l in data.get("logs", []):
		var n: Node3D = load("res://assets/env/models/dead_tree_trunk_02/dead_tree_trunk_02.gltf").instantiate()
		n.position = Vector3(l["x"], -0.1, l["z"])
		n.rotation.y = deg_to_rad(l["rot_deg"])
		n.scale = Vector3.ONE * (l["length_m"] / 4.05)  # 原模型长 4.05 米
		_snow(n)
		add_child(n)
		if _reachable(l["x"], l["z"]):  # 能跑到的倒木挡路（可以跳过去）
			add_child(_box_body(Vector3(l["length_m"] * 0.95, 0.7, 0.7), n.position + Vector3(0, 0.35, 0), n.rotation.y))
	for s in data.get("stumps", []):
		var holder := _holder(s["id"], s["x"], s["z"], _hash01(s["id"]) * TAU)
		if not _model(holder, STUMP_MODEL, s["id"], STUMP_HEIGHT, 0.0, true):
			var n: Node3D = load("res://assets/env/models/tree_stump_01/tree_stump_01.gltf").instantiate()
			n.position.y = -0.1
			_snow(n)
			holder.add_child(n)
		if _reachable(s["x"], s["z"]):
			add_child(_box_body(Vector3(1.2, 1.0, 1.2), holder.position + Vector3(0, 0.5, 0), 0.0))
	for p in data.get("props", []):
		var n := _prop(p)
		if n is Destructible:
			obstacles.append(n)
	_spread_canopies(near_trees, obstacles)
	_ledges()


## 树冠互相穿插 / 穿进拱门和灯里的，往外挪（离布局坐标最多 MAX_NUDGE 米）
const MAX_NUDGE := 1.5
func _spread_canopies(trees: Array, obstacles: Array) -> void:
	var home := {}
	for t in trees:
		home[t] = t.position
	for it in 12:
		var moved := false
		for i in trees.size():
			var a: Node3D = trees[i]
			var push := Vector3.ZERO
			for j in trees.size():
				if i == j:
					continue
				var b: Node3D = trees[j]
				var d := a.position - b.position
				d.y = 0.0
				var want: float = (a.canopy + b.canopy) * 0.55  # 树冠可以稍微交叠一点，看起来才像林子
				if d.length() < want:
					push += (d.normalized() if d.length() > 0.01 else Vector3.RIGHT) * (want - d.length()) * 0.5
			for o in obstacles:
				var d: Vector3 = a.position - o.position
				d.y = 0.0
				var want: float = a.canopy * 0.6 + (5.5 if o.kind == Destructible.Kind.ARCH else 0.8)
				if d.length() < want:
					push += (d.normalized() if d.length() > 0.01 else Vector3.RIGHT) * (want - d.length())
			if push.length() > 0.01:
				var p: Vector3 = a.position + push * 0.5
				var off: Vector3 = p - home[a]
				off.y = 0.0
				if off.length() > MAX_NUDGE:
					off = off.normalized() * MAX_NUDGE
				p = home[a] + off
				p.y = ArenaBuilder.ground_height(p.x, p.z)
				if p.distance_to(a.position) > 0.02:
					a.position = p
					moved = true
		if not moved:
			break


func _holder(id: String, x: float, z: float, rot_y: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = id
	holder.position = Vector3(x, ArenaBuilder.ground_height(x, z), z)
	holder.rotation.y = rot_y
	add_child(holder)
	return holder


## 一个固定摆放的物件：{model, x, z, rot_deg | face_center, height | width, lamp?, breakable_arch?}
func _prop(p: Dictionary) -> Node3D:
	var rot := deg_to_rad(p.get("rot_deg", 0.0))
	if p.get("face_center", false):
		rot = atan2(p["x"], p["z"])  # 正面（-Z）朝竞技场中心
	var vis := Node3D.new()
	if not _model(vis, p["model"], str(p.get("note", p["model"])), p.get("height", 0.0), p.get("width", 0.0)):
		vis.free()
		return null
	var node: Node3D = vis
	var reach := _reachable(p["x"], p["z"])
	if p.get("lamp", false):
		var h: float = p.get("height", 2.0)
		var light := OmniLight3D.new()  # 灯光：昼夜循环会调亮 / 调暗（组 lamp_light）
		light.light_color = LAMP_LIGHT
		light.omni_range = 7.0
		light.light_energy = 1.0
		light.position = Vector3(0, h * 0.72, 0)
		light.add_to_group("lamp_light")
		if reach:
			node = Destructible.make_lamp(vis, light, 0.4, h)
		else:
			vis.add_child(light)
	elif p.get("breakable_arch", false) and reach:
		var w: float = p.get("width", 11.0)
		var pillar := Vector3(w * 0.2, 7.0, w * 0.24)
		node = Destructible.make_arch(vis,
			[[BoxShape3D, pillar, Vector3(-w * 0.39, 3.5, 0)], [BoxShape3D, pillar, Vector3(w * 0.39, 3.5, 0)]],
			[[BoxShape3D, Vector3(w * 0.27, 1.4, w * 0.27), Vector3(-w * 0.36, 0.7, 0)], [BoxShape3D, Vector3(w * 0.27, 1.0, w * 0.27), Vector3(w * 0.36, 0.5, 0)], [BoxShape3D, Vector3(w * 0.36, 0.7, w * 0.23), Vector3(0, 0.35, w * 0.07)]],
			3.0, w * 0.4)
	node.name = str(p.get("note", p["model"]))
	add_child(node)
	node.position = Vector3(p["x"], ArenaBuilder.ground_height(p["x"], p["z"]), p["z"])
	node.rotation.y = rot
	return node


## 石台边上的石头台阶：从树林走上石台的入口。
## rock_formation_scan_2 是一层层的石板，沿模型 -X 方向一级级升高（长边 Z 是台阶的宽度）。
## "approach" 模式：按方位角摆，高的一头朝石台中心、边缘落在 inner_r；最高那级和那里的石台面齐平，
## 最低那级稍微埋进林地里——走上来是一级级的小台阶，接上石台没有坎。
## 其它（备用的木桩台子）还按 x / z / rot_deg / height 摆。碰撞用模型三角面，也放进预警圈投影的那一层
const LEDGE_SINK := 0.08
const STEP_LOW := 0.08  # 模型最低一级台阶的顶面在总高度的大约 8%（量出来的）
func _ledges() -> void:
	var f := FileAccess.open(LEDGES_JSON, FileAccess.READ)
	if f == null:
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for l in data.get("ledges", []):
		if not l.get("enabled", true):
			continue
		var approach: bool = l.get("mode", "") == "approach"
		var vis := Node3D.new()
		if not _model(vis, l["model"], l["id"], 0.0, l["width"] if approach else l["length"]):
			vis.free()
			continue
		var meshes := vis.find_children("*", "MeshInstance3D", true, false)
		var box := _bounds(vis, meshes)
		var holder := Node3D.new()
		holder.name = l["id"]
		holder.add_child(vis)
		if approach:
			var az := deg_to_rad(l["azimuth_deg"])
			var out := Vector3(sin(az), 0.0, cos(az))  # 从中心往外
			holder.rotation.y = az - PI / 2.0  # 模型 -X（高的一头）朝中心
			var inner: Vector3 = out * l["inner_r"]
			var top: float = ArenaBuilder.ground_height(inner.x, inner.z) + 0.03
			var outer: Vector3 = out * (l["inner_r"] + box.size.x)
			var low: float = ArenaBuilder.ground_height(outer.x, outer.z) - 0.05
			vis.scale.y = (top - low) / maxf(box.end.y * (1.0 - STEP_LOW), 0.01)
			var p: Vector3 = out * (l["inner_r"] - box.position.x) - Basis(Vector3.UP, holder.rotation.y) * Vector3(0, 0, box.get_center().z)
			holder.position = Vector3(p.x, top - box.end.y * vis.scale.y, p.z)
		else:
			vis.scale.y = l["height"] / maxf(box.size.y, 0.01)
			holder.rotation.y = deg_to_rad(l["rot_deg"])
			# 脚下地面最低处（石台边缘是斜坡）
			var g := INF
			var basis := Basis(Vector3.UP, holder.rotation.y)
			for i in 5:
				for j in 3:
					var off := basis * Vector3((j - 1) * box.size.x * 0.45, 0, (i - 2) * box.size.z * 0.22)
					g = minf(g, ArenaBuilder.ground_height(l["x"] + off.x, l["z"] + off.z))
			holder.position = Vector3(l["x"], g - LEDGE_SINK, l["z"])
		add_child(holder)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("ledge")  # Boss 顶到时直接迈上去（boss.gd _step_up）
		holder.add_child(body)
		for mi: MeshInstance3D in meshes:
			mi.layers = 1 | ArenaBuilder.GROUND_LAYER
		var cs := CollisionShape3D.new()
		cs.shape = _ledge_collision(holder, meshes)
		body.add_child(cs)


## 台阶的碰撞：不用模型本身（一块 30 万个三角形，Boss / 主角在上面走时物理一帧要几百毫秒），
## 而是在台阶上铺一张 LEDGE_CELL 米一格的「高度网」：每格取落在里面的顶点的最高点；
## 外面多铺一圈贴地的格子，边缘变成陡坡（不会从侧面钻进去）。几百个三角形
const LEDGE_CELL := 0.3
func _ledge_collision(holder: Node3D, meshes: Array) -> ConcavePolygonShape3D:
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in meshes:
		var xf := _rel_xform(holder, mi)
		for si in mi.mesh.get_surface_count():
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for i in range(0, v.size(), maxi(1, v.size() / 60000)):
				pts.append(xf * v[i])
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var nx := int(ceil((hi.x - lo.x) / LEDGE_CELL)) + 2
	var nz := int(ceil((hi.z - lo.z) / LEDGE_CELL)) + 2
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	h.fill(lo.y)
	for q in pts:
		var i := int((q.x - lo.x) / LEDGE_CELL) + 1
		var j := int((q.z - lo.z) / LEDGE_CELL) + 1
		h[j * nx + i] = maxf(h[j * nx + i], q.y)
	var corner := func(i: int, j: int) -> Vector3:
		return Vector3(lo.x + (i - 0.5) * LEDGE_CELL, h[j * nx + i], lo.z + (j - 0.5) * LEDGE_CELL)
	var faces := PackedVector3Array()
	for j in nz - 1:
		for i in nx - 1:
			var a: Vector3 = corner.call(i, j)
			var b: Vector3 = corner.call(i + 1, j)
			var c: Vector3 = corner.call(i, j + 1)
			var d: Vector3 = corner.call(i + 1, j + 1)
			faces.append_array([a, b, c, b, d, c])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape


func _reachable(x: float, z: float) -> bool:
	return Vector2(x, z).length() < PLAY_RADIUS + 1.0


## 简单的盒子碰撞（倒木、树桩）
func _box_body(size: Vector3, pos: Vector3, rot_y: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	sb.position = pos
	sb.rotation.y = rot_y
	return sb


## A1：残拱 + 古树 + 两盏石灯。一个模型都没有就放占位废墟
func _a1_group(items: Array, pos: Vector3) -> void:
	var placed := 0
	for p in items:
		if _prop(p):
			placed += 1
	if placed == 0:
		_ruins_placeholder(pos)


## 把 MODEL_DIR/<folder> 里的模型放进 holder，缩放到 target_h 高（或 target_w 宽）、底部贴地、居中。没有模型返回 false
func _model(holder: Node3D, folder: String, id: String, target_h: float, target_w: float = 0.0, trunk: bool = false) -> bool:
	if folder == "":
		return false
	var n: Node3D
	if folder in SPLIT_PACKS:
		var vs := _pack_variants(folder)
		if vs.is_empty():
			return false
		n = Node3D.new()
		for part in vs[absi(hash(id + "#variant")) % vs.size()]:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1]
			n.add_child(mi)
	else:
		var scene := _scene_in(folder)
		if scene == null:
			return false
		n = scene.instantiate()
	holder.add_child(n)
	var meshes := n.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		n.free()
		return false
	var box := _bounds(holder, meshes)
	var k := 1.0
	if target_w > 0.0:
		k = target_w / maxf(maxf(box.size.x, box.size.z), 0.01)
	elif target_h > 0.0:
		k = target_h / maxf(box.size.y, 0.01)
	n.scale *= k
	box = _bounds(holder, meshes)
	if trunk:
		# 树：按「树干底部」贴地，而不是包围盒底部——很多模型的树根往外、往下伸得很长，
		# 按包围盒对齐的话树根尖碰地、树干悬在半空。树根多出来的部分埋进土里。
		var base := _trunk_base(holder, meshes, box)
		n.position -= Vector3(base.x, base.y + TRUNK_SINK, base.z)
	else:
		n.position -= Vector3(box.get_center().x, box.position.y + 0.05, box.get_center().z)  # 底部中心对准原点，稍微埋进地里
	_snow(n)
	return true


const TRUNK_SINK := 0.25  # 树干底部再往地里埋多少米


## 树干底部（holder 坐标）：把底部 40% 的高度切成 16 片，量每一片里顶点离中心的「宽度」，
## 从下往上找第一片宽度 ≤ 最窄那片 × 1.4 的——那就是树根散开结束、树干开始的地方。
## 没有树根的断树：最下面那片就已经够窄，相当于直接按底部对齐。
func _trunk_base(holder: Node3D, meshes: Array, box: AABB) -> Vector3:
	var pts := PackedVector3Array()
	for m: MeshInstance3D in meshes:
		var xf := _rel_xform(holder, m)
		for si in m.mesh.get_surface_count():
			var v: PackedVector3Array = m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, v.size() / 8000)
			for i in range(0, v.size(), step):
				pts.append(xf * v[i])
	var y0 := box.position.y
	var h := box.size.y
	# 树干中心：离地 20%~40% 那段的中位数
	var xs := []
	var zs := []
	for p in pts:
		if p.y > y0 + h * 0.2 and p.y < y0 + h * 0.4:
			xs.append(p.x)
			zs.append(p.z)
	if xs.size() < 5:
		return Vector3(box.get_center().x, y0, box.get_center().z)
	xs.sort()
	zs.sort()
	var c := Vector2(xs[xs.size() / 2], zs[zs.size() / 2])
	var slices := 16
	var span := h * 0.4
	var widths := []
	for k in slices:
		widths.append([])
	for p in pts:
		var k := int((p.y - y0) / span * slices)
		if k >= 0 and k < slices:
			widths[k].append(Vector2(p.x, p.z).distance_to(c))
	var w := []
	for k in slices:
		var arr: Array = widths[k]
		if arr.size() < 3:
			w.append(INF)
			continue
		arr.sort()
		w.append(arr[int(arr.size() * 0.8)])  # 80% 分位：不被个别伸出去的树根带偏
	var wmin: float = w.min()
	var base_k := 0
	for k in slices:
		if w[k] <= wmin * 1.4:
			base_k = k
			break
	return Vector3(c.x, y0 + span * base_k / slices, c.y)


func _bounds(holder: Node3D, meshes: Array) -> AABB:
	var box := AABB()
	var first := true
	for m: MeshInstance3D in meshes:
		var b := _rel_xform(holder, m) * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## m 相对 holder 的变换（不依赖是否已进场景树）
func _rel_xform(holder: Node, m: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = m
	while n and n != holder:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## 套装切成单棵：先找贴地的树根（最低 8% 高度里的顶点，按 x 分组，组之间有空隙就是两棵树），
## 再把每个三角形分给离它最近的树根。返回 [ [ [ArrayMesh, Transform3D], ... ]（一棵树）, ... ]
func _pack_variants(folder: String) -> Array:
	if _variants.has(folder):
		return _variants[folder]
	var t0 := Time.get_ticks_msec()
	var result := []
	var scene := _scene_in(folder)
	if scene == null:
		_variants[folder] = result
		return result
	var root: Node3D = scene.instantiate()
	var pieces := []  # [mesh, surface, xform, arrays, 每个三角形中心（x, z）]
	var all_pts := PackedVector3Array()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := _rel_xform(root, mi)
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
				arr[Mesh.ARRAY_INDEX] = idx
			var wv := PackedVector3Array()
			wv.resize(verts.size())
			for k in verts.size():
				wv[k] = xf * verts[k]
			all_pts.append_array(wv)
			var tc := PackedVector2Array()
			tc.resize(idx.size() / 3)
			for t in tc.size():
				var c := (wv[idx[t * 3]] + wv[idx[t * 3 + 1]] + wv[idx[t * 3 + 2]]) / 3.0
				tc[t] = Vector2(c.x, c.z)
			pieces.append([mi.mesh, si, xf, arr, tc])
	var box := AABB(all_pts[0], Vector3.ZERO)
	for p in all_pts:
		box = box.expand(p)
	# 树根：贴地的顶点按 x 分组
	var low := []
	for p in all_pts:
		if p.y < box.position.y + box.size.y * 0.08:
			low.append(p)
	low.sort_custom(func(a, b): return a.x < b.x)
	var gap := maxf(box.size.x, box.size.z) * 0.02
	var bases := []  # Vector2 树根中心
	var acc := Vector3.ZERO
	var cnt := 0
	for k in low.size():
		if k > 0 and low[k].x - low[k - 1].x > gap:
			bases.append(Vector2(acc.x, acc.z) / cnt)
			acc = Vector3.ZERO
			cnt = 0
		acc += low[k]
		cnt += 1
	if cnt > 0:
		bases.append(Vector2(acc.x, acc.z) / cnt)
	var count := bases.size()
	for v in count:
		result.append([])
	for p in pieces:
		var arr: Array = p[3]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var tc: PackedVector2Array = p[4]
		var per := []
		for v in count:
			per.append([])
		for t in tc.size():
			var best := 0
			var bd := INF
			for v in count:
				var d: float = tc[t].distance_squared_to(bases[v])
				if d < bd:
					bd = d
					best = v
			var list: Array = per[best]
			list.append(idx[t * 3])
			list.append(idx[t * 3 + 1])
			list.append(idx[t * 3 + 2])
		for v in count:
			if per[v].is_empty():
				continue
			var a2 := _compact(arr, per[v])
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			am.surface_set_material(0, p[0].surface_get_material(p[1]))
			result[v].append([am, p[2]])
	root.free()
	result = result.filter(func(r): return not r.is_empty())
	_variants[folder] = result
	print_verbose("切套装 %s：%d 棵，%d ms" % [folder, result.size(), Time.get_ticks_msec() - t0])
	return result


## 只保留这棵树用到的顶点（不然网格的包围盒还是整个套装那么大，缩放 / 居中会错）
func _compact(arr: Array, tri_idx: Array) -> Array:
	var remap := {}
	var used := PackedInt32Array()
	var new_idx := PackedInt32Array()
	new_idx.resize(tri_idx.size())
	for k in tri_idx.size():
		var o: int = tri_idx[k]
		if not remap.has(o):
			remap[o] = used.size()
			used.append(o)
		new_idx[k] = remap[o]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nv := PackedVector3Array()
	nv.resize(used.size())
	for k in used.size():
		nv[k] = vtx[used[k]]
	out[Mesh.ARRAY_VERTEX] = nv
	if arr[Mesh.ARRAY_NORMAL] != null:
		var src: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var d := PackedVector3Array()
		d.resize(used.size())
		for k in used.size():
			d[k] = src[used[k]]
		out[Mesh.ARRAY_NORMAL] = d
	if arr[Mesh.ARRAY_TANGENT] != null:
		var src: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		var d := PackedFloat32Array()
		d.resize(used.size() * 4)
		for k in used.size():
			for c in 4:
				d[k * 4 + c] = src[used[k] * 4 + c]
		out[Mesh.ARRAY_TANGENT] = d
	for ch in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arr[ch] != null:
			var src: PackedVector2Array = arr[ch]
			var d := PackedVector2Array()
			d.resize(used.size())
			for k in used.size():
				d[k] = src[used[k]]
			out[ch] = d
	if arr[Mesh.ARRAY_COLOR] != null:
		var src: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var d := PackedColorArray()
		d.resize(used.size())
		for k in used.size():
			d[k] = src[used[k]]
		out[Mesh.ARRAY_COLOR] = d
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


func _scene_in(folder: String) -> PackedScene:
	if folder == "":
		return null
	if _cache.has(folder):
		return _cache[folder]
	var found: PackedScene = null
	var dir := MODEL_DIR + folder + "/"
	if DirAccess.dir_exists_absolute(dir):
		for fname in DirAccess.get_files_at(dir):
			if fname.get_extension().to_lower() in ["gltf", "glb", "fbx"]:
				found = load(dir + fname)
				break
	_cache[folder] = found
	return found


func _snow(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = ArenaBuilder.snow_cap()


## A1 占位废墟：断柱 + 残拱 + 石台（没有任何废墟模型时用）
func _ruins_placeholder(pos: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "A1_Ruins"
	holder.position = pos
	holder.rotation.y = atan2(pos.x, pos.z)  # 正面（-Z）朝竞技场中心
	add_child(holder)
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load("res://assets/env/models/boulder_01/textures/boulder_01_diff_1k.jpg")
	stone.albedo_color = Color(0.75, 0.74, 0.72)
	stone.normal_enabled = true
	stone.normal_texture = load("res://assets/env/models/boulder_01/textures/boulder_01_nor_gl_1k.jpg")
	stone.roughness = 0.95
	stone.uv1_triplanar = true
	stone.uv1_world_triplanar = true
	stone.uv1_scale = Vector3.ONE * 0.5
	var parts := [
		[Vector3(1.1, 5.2, 1.1), Vector3(-2.6, 2.6, 0.0), Vector3(0, 0, 0.03)],
		[Vector3(1.1, 3.1, 1.1), Vector3(2.6, 1.55, 0.0), Vector3(0, 0, -0.05)],
		[Vector3(4.2, 0.9, 1.2), Vector3(-1.2, 5.6, 0.0), Vector3(0, 0, -0.12)],
		[Vector3(1.1, 1.0, 2.6), Vector3(3.6, 0.45, 1.4), Vector3(0.1, 0.6, 1.45)],
		[Vector3(3.0, 0.9, 1.8), Vector3(0.0, 0.45, -1.4), Vector3(0, 0.08, 0)],
		[Vector3(6.4, 0.35, 4.2), Vector3(0.0, 0.1, 0.0), Vector3(0, 0, 0)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		mi.mesh = bm
		mi.position = p[1]
		mi.rotation = p[2]
		mi.material_override = stone
		mi.material_overlay = ArenaBuilder.snow_cap()
		holder.add_child(mi)


func _hash01(s: String) -> float:
	return float(absi(hash(s)) % 10007) / 10007.0
