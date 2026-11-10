@tool
extends RefCounted
## 方案 B「枯林巢穴」：犀渠的老窝。林子最深处一棵千年古树下，一个往下陷的圆形泥坑，
## 四周是古树盘出来的巨根当围墙，留 4 处根缝。阴雨天，云缝和树冠破口里漏下一束冷光。
## 设计文档：Claude Doc「犀渠战场重设计方案」；俯视布局：design/arena_b_layout_v1.png
##
## 层次：后景 = 古树 + 山崖（青玉矿脉）+ 崖顶半塌山神庙剪影；中景 = 根墙 + 坑里的杂物；前景 = 枯枝、茜草。
## 坑底是平的（y = 0），战斗逻辑不用改；坑外的地形只是看的，碰撞只有一圈根墙（挡镜头）。

const PIT_R := 15.5           # 坑底平地半径 = 能打的地方（v2 是 13.5 + 坡；坡上走不顺、树挡镜头，v3 改回只在坑里打，坑放大）
const PLAY_R := 22.0          # 能跑的范围：坑底 + 坑沿的坡（main.gd 的 PLAY_RADIUS）。坡上有树能躲
const WALL_R := PIT_R + 1.3   # 根墙：树根扎进坑底的位置，也是碰撞墙的内沿
const ROOT_CLUSTERS := [20.0, 55.0, 120.0, 175.0, 228.0, 292.0, 345.0]   # 一簇簇拱起的树根，簇之间留出能走上坡的空当
const BIG_ROOTS := [238.0, 258.0, 282.0, 304.0]   # 古树盘过来的主根（北面）
const PLAYER_ONLY_LAYER := 128  # = Destructible.RUBBLE_LAYER：树根只挡主角，Boss 体型大直接跨过去
const PLAYER_SPAWN := Vector3(0.0, 0.0, 21.0)    # 南口通道里：开场从这里跑进坑（通道两边有墙）
const BOSS_SPAWN := Vector3(0.0, 0.0, -14.5)     # 坑北边、古树主根前：开场亮相后从这里冲过来
const RIM_H := 2.2            # 坑沿比坑底高多少
const GAPS := [90.0, 150.0, 200.0, 318.0]   # 4 处根缝的方向（度；0 = 东，90 = 南，270 = 北）
const GAP_HALF := 1.9         # 根缝半宽（米）
const TREE_POS := Vector3(0.0, 0.0, -34.0)  # 千年古树（北）。11-08 从 -28 往后挪，树根整个埋进土坡里，不伸进坑
const TREE_HEIGHT := 44.0
const TREE_SINK := 5.0      # 古树往土里埋多少米（树根露在外面就加大）
const CLIFF_Z := -40.0        # 山崖脚（v1 在 -46，雾里完全看不见，只剩矿脉和庙窗飘在天上）
const SHRINE_X := 22.0         # 山神庙在崖顶的横向位置（高度、前后按崖顶算）
const SHAFT_FROM := Vector3(-5.0, 36.0, -9.0)   # 主光束：从树冠破口斜照进坑
const SHAFT_TO := Vector3(1.5, 0.0, 0.5)
const GROUND_LAYER := 2       # 和 arena_builder.gd 一样：预警圈只投到这一层

const ENV := "res://assets/env/"
const TEX := ENV + "textures/"
const SK := ENV + "sketchfab/"

const JADE := Color(0.35, 1.0, 0.82)
const WARM := Color(1.0, 0.62, 0.32)
const SKY_LIGHT := Color(0.80, 0.86, 0.96)
const ANCIENT_TREE := "ancient_tree/scene.gltf"   # Boss 身后的古树（DJMaesen，CC-BY）；找不到就用旧的 gnarled tree
const ANCIENT_LEAVES := false                     # true = 留着模型自带的树叶
# 坑周围的树：之前下载的几种模型混着用（"" = 代码生成的枯树，能挂小孩衣物）
const RING_TREES := ["old_tree", "dead_trees_demo", "spooky_tree", "dead_trees", "", "dead_trees_demo", "old_tree", "dead_trees", ""]

static var _noise: FastNoiseLite
static var _mask_tex: Texture2D
static var _bark: StandardMaterial3D
static var _bark_dark: StandardMaterial3D
static var _jade_mat: StandardMaterial3D
static var shaft: SpotLight3D
static var env: Environment
static var rain: Node3D
static var daynight: Node
static var _sky_mat: ProceduralSkyMaterial
static var _overcast: DirectionalLight3D
static var _gap_lights: Array = []
static var _warm: Array = []   # [灯, 白天的亮度]：昼夜脚本按天色调
static var _glow_tex: Texture2D
static var _lanterns: Array = []  # [灯, 夜里的亮度, 火苗材质, 光晕材质, Destructible]：白天灭、天黑才点
static var _tl: Node  # 借 tree_layout.gd 的模型加载（切套装、按树干底部贴地）
static var _cliff_nz: FastNoiseLite
const CLIFF_TOP := 30.0


## 崖面在 (x, y) 处的 z
static func _cliff_z(x: float, y: float) -> float:
	return CLIFF_Z - 6.0 * absf(_cliff_nz.get_noise_2d(x, y)) - y * 0.22 - absf(x) * 0.12


static func _cliff_top(x: float) -> float:
	return CLIFF_TOP + 5.0 * _cliff_nz.get_noise_1d(x * 0.3)


static func build(root: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261106
	_warm = []        # 静态变量在按 R 重开时不会清空
	_lanterns = []
	Destructible.dust_override = Color(0.30, 0.28, 0.25, 0.55)  # 泥灰，不是雪
	_gap_lights = []
	_init_shared()
	_render_scale(root)
	_environment(root)
	_terrain(root)
	_wall_collision(root)
	_roots(root, rng)
	_slope_trees(root, rng)
	_south_foreground(root, rng)
	_pit_logs(root, rng)
	_pots(root, rng)
	_giant_tree(root)
	_canopy(root, rng)
	_forest(root, rng)
	_cliff(root, rng)
	_shrine(root)
	_props(root, rng)
	_madder(root, rng)
	_pebbles(root, rng)
	_lights(root)
	rain = load("res://scripts/env/rain.gd").new()
	rain.name = "Rain"
	root.add_child(rain)
	rain.set("intensity", 0.75)
	daynight = load("res://scripts/env/lair_daynight.gd").new()
	daynight.name = "LairDayNight"
	daynight.env = env
	daynight.sky_mat = _sky_mat
	daynight.overcast = _overcast
	daynight.shaft = shaft
	daynight.gap_lights = _gap_lights
	daynight.warm = _warm
	daynight.lanterns = _lanterns
	root.add_child(daynight)


# ---------------- 地形 ----------------

static func _init_shared() -> void:
	if _noise:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = 1106
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.06
	_noise.fractal_octaves = 3
	var mn := FastNoiseLite.new()
	mn.seed = 77
	mn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mn.frequency = 0.012
	mn.fractal_octaves = 4
	_mask_tex = ImageTexture.create_from_image(mn.get_seamless_image(512, 512))
	_bark = _bark_mat(Color(0.42, 0.39, 0.36))
	_bark_dark = _bark_mat(Color(0.26, 0.24, 0.22))
	_jade_mat = StandardMaterial3D.new()
	_jade_mat.albedo_color = Color(0.12, 0.35, 0.3)
	_jade_mat.roughness = 0.25
	_jade_mat.emission_enabled = true
	_jade_mat.emission = JADE
	_jade_mat.emission_energy_multiplier = 1.6


static func _bark_mat(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "bark_willow_02/bark_willow_02_diffuse_1k.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + "bark_willow_02/bark_willow_02_nor_gl_1k.jpg")
	m.roughness_texture = load(TEX + "bark_willow_02/bark_willow_02_rough_1k.jpg")
	m.roughness = 0.75  # 淋湿的树皮比干的亮一点
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 离哪个根缝多近：1 = 在根缝正中，0 = 不在根缝里
static func gap_k(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var a := atan2(z, x)
	var k := 0.0
	for g in GAPS:
		var d := wrapf(a - deg_to_rad(g), -PI, PI)
		if absf(d) > PI * 0.5:
			continue
		var perp := absf(sin(d)) * r
		k = maxf(k, 1.0 - smoothstep(GAP_HALF, GAP_HALF + 2.2, perp))
	return k


## 世界坐标 (x, z) 处地面高度。坑底（半径 PIT_R 以内）一律是 0
static func terrain_h(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	if r <= PIT_R:
		return 0.0
	_init_shared()
	var rim := smoothstep(PIT_R + 0.3, PIT_R + 6.5, r) * RIM_H
	var h := rim * (1.0 - 0.8 * gap_k(x, z))
	h += _noise.get_noise_2d(x, z) * 0.9 * smoothstep(PIT_R + 1.0, PIT_R + 8.0, r)
	var dt := Vector2(x - TREE_POS.x, z - TREE_POS.z).length()
	h += 4.5 * (1.0 - smoothstep(8.0, 20.0, dt)) * smoothstep(PIT_R, PIT_R + 3.0, r)  # 古树根部隆起（盖住树根）
	return h


static func _terrain(root: Node3D) -> void:
	# 碰撞：高度图（1 米一格，和地面网格一致），坑底平地 + 坑沿的坡都能走
	var hh := 40
	var w := hh * 2 + 1
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = w
	var data := PackedFloat32Array()
	data.resize(w * w)
	for j in w:
		for i in w:
			data[j * w + i] = terrain_h(i - hh, j - hh)
	hm.map_data = data
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var col := CollisionShape3D.new()
	col.shape = hm
	body.add_child(col)
	root.add_child(body)

	var half := 75
	var step := 1.0
	var n := int(half * 2 / step) + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var x := -half + i * step
			var z := -half + j * step
			var h := terrain_h(x, z)
			var e := 0.5
			var nx := terrain_h(x + e, z) - terrain_h(x - e, z)
			var nz := terrain_h(x, z + e) - terrain_h(x, z - e)
			verts.append(Vector3(x, h, z))
			norms.append(Vector3(-nx, 2.0 * e, -nz).normalized())
			uvs.append(Vector2(x, z))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx.append_array(PackedInt32Array([a, a + 1, a + n, a + 1, a + n + 1, a + n]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_tangents()
	var mesh := st.commit()

	var m := ShaderMaterial.new()
	m.shader = load(ENV + "ground_wet.gdshader")
	m.set_shader_parameter("leaves_albedo", load(TEX + "winter_leaves/winter_leaves_diffuse_1k.jpg"))
	m.set_shader_parameter("leaves_normal", load(TEX + "winter_leaves/winter_leaves_nor_gl_1k.jpg"))
	m.set_shader_parameter("leaves_rough", load(TEX + "winter_leaves/winter_leaves_rough_1k.jpg"))
	m.set_shader_parameter("mask_noise", _mask_tex)
	m.set_shader_parameter("pit_radius", PIT_R)
	var gdir := TEX + "pit_gravel/"
	if ResourceLoader.exists(gdir + "diff.jpg"):
		m.set_shader_parameter("gravel_albedo", load(gdir + "diff.jpg"))
		m.set_shader_parameter("gravel_normal", load(gdir + "nor_gl.jpg"))
		m.set_shader_parameter("gravel_rough", load(gdir + "rough.jpg"))
		m.set_shader_parameter("has_gravel", true)
	var mi := MeshInstance3D.new()
	mi.name = "LairGround"
	mi.mesh = mesh
	mi.material_override = m
	mi.layers = 1 | GROUND_LAYER
	root.add_child(mi)


# ---------------- 树根、古树、树冠 ----------------

## 一根管子（树根 / 树枝）：沿着点列扫一圈圆，半径从 r0 渐变到 r1
static func _tube(arrs: Array, pts: Array, r0: float, r1: float, sides: int = 7) -> void:
	var verts: Array = arrs[0]
	var norms: Array = arrs[1]
	var idx: Array = arrs[2]
	var base := verts.size()
	var cnt := pts.size()
	var nrm := Vector3.ZERO
	for i in cnt:
		var p: Vector3 = pts[i]
		var t: Vector3 = (pts[mini(i + 1, cnt - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i == 0:
			var up := Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT
			nrm = up.cross(t).normalized()
		else:
			nrm = (nrm - t * nrm.dot(t)).normalized()
		var bin := t.cross(nrm)
		var rad := lerpf(r0, r1, float(i) / (cnt - 1))
		for s in sides:
			var ang := TAU * s / sides
			var d := nrm * cos(ang) + bin * sin(ang)
			verts.append(p + d * rad)
			norms.append(d)
	for i in cnt - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a := base + i * sides + s
			var b := base + i * sides + s2
			var c := base + (i + 1) * sides + s
			var d := base + (i + 1) * sides + s2
			idx.append_array([a, c, b, b, c, d])


static func _commit_tubes(root: Node3D, arrs: Array, mat: Material, name_: String, shadows: bool = true) -> MeshInstance3D:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(arrs[0])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(arrs[1])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array(arrs[2])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = am
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


## 二次贝塞尔曲线 + 一点抖动，返回点列
static func _curve(a: Vector3, c: Vector3, b: Vector3, n: int, rng: RandomNumberGenerator, jitter: float) -> Array:
	var pts := []
	for i in n:
		var t := float(i) / (n - 1)
		var p := a.lerp(c, t).lerp(c.lerp(b, t), t)
		if i > 0 and i < n - 1:
			p += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
		pts.append(p)
	return pts


static func _polar(r: float, a_deg: float, y: float) -> Vector3:
	var a := deg_to_rad(a_deg)
	return Vector3(cos(a) * r, y, sin(a) * r)


static func _roots(root: Node3D, rng: RandomNumberGenerator) -> void:
	var arrs := [[], [], []]
	# 1) 一圈从坑外拱起、扎进坑边的根：连成一堵看得见的墙（v2 改成一簇簇、能走上坡，体验不好，又改回来）
	var a := 0.0
	while a < 360.0:
		a += rng.randf_range(3.5, 6.0)
		var test := _polar(WALL_R + 0.7, a, 0.0)
		if gap_k(test.x, test.z) > 0.25:
			continue
		var da := rng.randf_range(-7.0, 7.0)
		var start := _polar(rng.randf_range(WALL_R + 3.5, WALL_R + 9.0), a + da, 0.0)
		start.y = terrain_h(start.x, start.z) - 0.3
		var apex := _polar(rng.randf_range(WALL_R + 0.9, WALL_R + 2.8), a + da * 0.4, 0.0)
		apex.y = terrain_h(apex.x, apex.z) + rng.randf_range(1.2, 3.4)
		var end := _polar(rng.randf_range(WALL_R - 0.2, WALL_R + 0.4), a, -0.5)
		_tube(arrs, _curve(start, apex, end, 14, rng, 0.25), rng.randf_range(0.4, 0.95), rng.randf_range(0.14, 0.3))
	# 2) 沿着坑沿横着盘的根，把竖根连成墙
	a = 0.0
	while a < 360.0:
		a += rng.randf_range(8.0, 13.0)
		var span := rng.randf_range(12.0, 22.0)
		var blocked := false
		for k in 5:
			var t := _polar(WALL_R + 1.0, a + span * k / 4.0, 0.0)
			if gap_k(t.x, t.z) > 0.2:
				blocked = true
		if blocked:
			continue
		var r := rng.randf_range(WALL_R + 0.5, WALL_R + 1.6)
		var p0 := _polar(r + rng.randf_range(-0.4, 0.4), a, 0.0)
		var p1 := _polar(r + rng.randf_range(-0.6, 0.6), a + span * 0.5, 0.0)
		var p2 := _polar(r + rng.randf_range(-0.4, 0.4), a + span, 0.0)
		p0.y = terrain_h(p0.x, p0.z) - 0.2
		p1.y = terrain_h(p1.x, p1.z) + rng.randf_range(0.7, 1.9)
		p2.y = terrain_h(p2.x, p2.z) - 0.2
		_tube(arrs, _curve(p0, p1, p2, 12, rng, 0.2), rng.randf_range(0.35, 0.75), rng.randf_range(0.2, 0.4))
	# 3) 古树盘过来的主根：最粗，从北面压进坑沿
	for k in 7:
		var ang := 236.0 + k * 11.5 + rng.randf_range(-3, 3)
		var s := TREE_POS + (_polar(15.0, ang, 0.0) - TREE_POS).normalized() * 5.0
		s.y = terrain_h(s.x, s.z) + 1.5
		var e := _polar(WALL_R + rng.randf_range(-0.2, 0.5), ang + rng.randf_range(-3, 3), -0.6)
		var c := s.lerp(e, 0.55)
		c.y = terrain_h(c.x, c.z) + rng.randf_range(2.2, 4.0)
		_tube(arrs, _curve(s, c, e, 18, rng, 0.35), rng.randf_range(1.2, 1.8), rng.randf_range(0.35, 0.55), 9)
	# 4) 坑底边上露出地面的细根（很矮，只是看的）
	for k in 48:
		var ang := rng.randf() * 360.0
		var p0 := _polar(WALL_R + 0.2, ang, -0.2)
		var p2 := _polar(rng.randf_range(PIT_R - 1.8, PIT_R - 0.2), ang + rng.randf_range(-10, 10), -0.15)
		var p1 := p0.lerp(p2, 0.5) + Vector3.UP * rng.randf_range(0.08, 0.25)
		_tube(arrs, _curve(p0, p1, p2, 8, rng, 0.06), rng.randf_range(0.08, 0.16), 0.03, 5)
	_commit_tubes(root, arrs, _bark, "RootWall")


## 根墙的碰撞：一圈竖着的方块，只在南口留一条通道（出生点在通道里）；其余三个根缝用倒木封住
static func _wall_collision(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "RootWallCollision"
	var count := 72
	var r := WALL_R + 0.6
	for i in count:
		var a := TAU * i / count
		var x := cos(a) * r
		var z := sin(a) * r
		if z > 0.0 and absf(x) < GAP_HALF + 0.2:  # 南口通道
			continue
		_wall_box(body, Vector3(x, 2.0, z), a, Vector3(TAU * r / count + 0.35, 6.0, 1.2))
	# 南口通道：两侧墙 + 尽头
	var z0 := WALL_R
	var z1 := PLAYER_SPAWN.z + 2.6
	for side in [-1.0, 1.0]:
		var col := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(1.0, 6.0, z1 - z0 + 1.0)
		col.shape = b
		col.position = Vector3(side * (GAP_HALF + 0.7), 2.5, (z0 + z1) * 0.5)
		body.add_child(col)
	var cap := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(GAP_HALF * 2.0 + 2.4, 6.0, 1.0)
	cap.shape = cb
	cap.position = Vector3(0, 2.5, z1 + 0.5)
	body.add_child(cap)
	root.add_child(body)
	# 南口沟和坑的交界：主角进坑以后关上的隐形墙（lair_gate.gd），回不到出生的沟里
	var gate := StaticBody3D.new()
	gate.name = "EntryGate"
	gate.set_script(load("res://scripts/env/lair_gate.gd"))
	gate.collision_layer = PLAYER_ONLY_LAYER
	gate.collision_mask = 0
	gate.set("close_r", PIT_R - 1.5)
	gate.set("player_r", PIT_R + 0.5)   # 进坑以后主角最远到坑底边缘（瞬影斩也不会闪到墙里）
	gate.set("cam_r", PIT_R - 0.3)      # 镜头不钻进根墙
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(GAP_HALF * 2.0 + 2.4, 6.0, 0.6)
	gs.shape = gb
	gs.position = Vector3(0, 2.5, WALL_R - 0.2)
	gate.add_child(gs)
	root.add_child(gate)
	# 其余三个根缝：堆两块大石头堵住（坑里只留一根倒木；光还能从石头上面透进来）
	for g in GAPS:
		if absf(g - 90.0) < 1.0:
			continue
		for k in 2:
			var p := _polar(WALL_R + 0.5 + k * 0.6, g + (k * 2 - 1) * 3.5, 0.0)
			_place(root, ENV + "models/boulder_01/boulder_01.gltf", Vector3(p.x, terrain_h(p.x, p.z) - 0.3, p.z), g * 0.7 + k, 2.2 - k * 0.4)


static func _wall_box(body: StaticBody3D, pos: Vector3, a: float, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	col.shape = b
	col.position = pos
	col.rotation.y = -a - PI * 0.5  # 方块的长边沿着圆周
	body.add_child(col)


## 坑里的倒木和几根断掉的枯树桩：玩家能绕、能躲；倒木只挡主角（Boss 跨过去），树桩会被 Boss 打断
static func _pit_logs(root: Node3D, rng: RandomNumberGenerator) -> void:
	var D = load("res://scripts/env/destructible.gd")
	# 坑里只留一根倒下的枯树干：Boss 的招打到会碎（2 下，重招 1 下）；碎之前挡主角也挡 Boss
	var tmp := Node3D.new()
	var vis := _place(tmp, ENV + "models/dead_tree_trunk_02/dead_tree_trunk_02.gltf", Vector3.ZERO, 0.4, 0.9)
	if vis:
		tmp.remove_child(vis)
		var bb := _bounds(vis)
		var lg = D.make_lamp(vis, null, maxf(bb.size.x, bb.size.z) * 0.35, bb.size.y)
		lg.name = "PitLog"
		lg.hp = 2.0
		lg.contact_breakable = false
		for c in lg.body.get_children():
			c.free()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(bb.size.x * 0.85, bb.size.y * 0.8, bb.size.z * 0.85)
		col.shape = box
		col.transform = vis.transform * Transform3D(Basis(), bb.get_center())
		lg.body.add_child(col)
		lg.position = Vector3(-8.5, -0.05, 3.5)
		root.add_child(lg)
	tmp.free()
	var snags := [Vector3(-6.0, 0, 9.5), Vector3(10.5, 0, -2.0), Vector3(-10.0, 0, -9.0), Vector3(5.5, 0, 11.0)]
	for p in snags:
		var h := rng.randf_range(3.0, 5.5)
		var tr := rng.randf_range(0.3, 0.45)
		var v := _tree_visual(rng, h, tr)
		var d = D.make_tree(v[0], tr, h, 2.0, false)
		d.canopy = 1.4
		d.position = p
		root.add_child(d)
		for hp in v[1]:
			if rng.randf() < 0.5:
				_hang(root, d.position + hp, rng)


## 瓦罐：车床式旋转出罐身；碎的只剩半边。几堆集中在坑中间一圈
static func _pot_mesh(broken: bool, rng: RandomNumberGenerator) -> ArrayMesh:
	var prof := [Vector2(0.10, 0.0), Vector2(0.17, 0.06), Vector2(0.22, 0.18), Vector2(0.19, 0.31), Vector2(0.10, 0.39), Vector2(0.09, 0.42), Vector2(0.115, 0.45)]
	var top_cut := prof.size()
	var arc := TAU
	if broken:
		top_cut = rng.randi_range(3, 5)
		arc = TAU * rng.randf_range(0.45, 0.7)
	var segs := 14
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in top_cut - 1:
		for j in segs:
			var a0 := arc * j / segs
			var a1 := arc * (j + 1) / segs
			var p0: Vector2 = prof[i]
			var p1: Vector2 = prof[i + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			for v in [v00, v10, v01, v01, v10, v11]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


static func _pots(root: Node3D, rng: RandomNumberGenerator) -> void:
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.36, 0.2, 0.12)
	clay.roughness = 0.55  # 淋湿的陶
	clay.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := clay.duplicate() as StandardMaterial3D
	dark.albedo_color = Color(0.18, 0.15, 0.13)  # 黑釉
	var D = load("res://scripts/env/destructible.gd")
	var piles := [Vector2(-4.0, 5.5), Vector2(5.0, 3.0), Vector2(-3.0, -5.5), Vector2(6.0, -5.0), Vector2(-9.0, -0.5), Vector2(2.0, 8.5)]
	for c in piles:
		for k in rng.randi_range(4, 8):
			var broken := rng.randf() < 0.55
			var mi := MeshInstance3D.new()
			mi.mesh = _pot_mesh(broken, rng)
			mi.material_override = dark if rng.randf() < 0.3 else clay
			var s := rng.randf_range(0.8, 1.6)
			mi.scale = Vector3.ONE * s
			var off := Vector2(rng.randf_range(-1.3, 1.3), rng.randf_range(-1.3, 1.3))
			mi.position = Vector3(c.x + off.x, -0.02, c.y + off.y)
			mi.rotation.y = rng.randf() * TAU
			if rng.randf() < 0.35:  # 倒在地上
				mi.rotation.x = PI * 0.5
				mi.position.y = 0.2 * s
			if broken:
				root.add_child(mi)
				continue
			# 完整的陶罐：主角砍一下 / 翻滚撞上就碎，Boss 走过去也会踩碎
			var d = D.make_lamp(mi, null, 0.2 * s, 0.45 * s)
			d.player_breakable = true
			d.contact_breakable = true
			d.shard_color = (mi.material_override as StandardMaterial3D).albedo_color
			d.shard_size = 0.07 * s
			d.shard_count = 9
			d.position = Vector3(mi.position.x, 0.0, mi.position.z)
			mi.position = Vector3(0, mi.position.y, 0)
			root.add_child(d)
		# 碎瓦片
		for k in rng.randi_range(6, 12):
			var mi := MeshInstance3D.new()
			mi.mesh = _pot_mesh(true, rng)
			mi.material_override = clay
			var s := rng.randf_range(0.35, 0.6)
			mi.scale = Vector3(s, s * 0.5, s)
			mi.position = Vector3(c.x + rng.randf_range(-2.2, 2.2), 0.0, c.y + rng.randf_range(-2.2, 2.2))
			mi.rotation = Vector3(rng.randf_range(1.2, 1.9), rng.randf() * TAU, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)


## 一根树根的碰撞：每两个采样点一段胶囊；埋在地下的段跳过
static func _root_collision(body: StaticBody3D, pts: Array, r0: float, r1: float) -> void:
	var n := pts.size()
	for i in range(0, n - 2, 2):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 2]
		var rad := lerpf(r0, r1, float(i + 1) / (n - 1)) * 0.85
		var mid := (a + b) * 0.5
		if maxf(a.y, b.y) + rad < terrain_h(mid.x, mid.z) + 0.15:
			continue
		var cap := CapsuleShape3D.new()
		cap.radius = rad
		cap.height = a.distance_to(b) + rad * 2.0
		var col := CollisionShape3D.new()
		col.shape = cap
		var dir := (b - a).normalized()
		col.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), mid)
		body.add_child(col)


static func _near_angle(a: float, list: Array, w: float) -> bool:
	for x in list:
		if absf(wrapf(a - x, -180.0, 180.0)) < w:
			return true
	return false


## 一棵程序生成的枯树（树干 + 几根枝），返回 [节点, 能挂东西的低枝点（本地坐标）]
static func _tree_visual(rng: RandomNumberGenerator, h: float, tr: float) -> Array:
	var holder := Node3D.new()
	var arrs := [[], [], []]
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * h * 0.05
	var top := Vector3.UP * h + lean
	var trunk := _curve(Vector3(0, -0.4, 0), Vector3.UP * h * 0.5 + lean * 0.3, top, 9, rng, 0.12)
	_tube(arrs, trunk, tr, 0.06, 7)
	var hangs := []
	for b in rng.randi_range(4, 7):
		var i0 := rng.randi_range(3, 7)
		var p0: Vector3 = trunk[i0]
		var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.1, 0.7), rng.randf_range(-1, 1)).normalized()
		var ln := rng.randf_range(1.5, 3.8)
		var p2 := p0 + dirv * ln
		var br := _curve(p0, p0.lerp(p2, 0.5) + Vector3(0, 0.25, 0), p2, 6, rng, 0.08)
		_tube(arrs, br, tr * 0.35, 0.02, 5)
		var hp: Vector3 = br[4]
		if hp.y > 2.2 and hp.y < 4.2:
			hangs.append(hp)
	_commit_tubes(holder, arrs, _bark_dark, "Tree")
	return [holder, hangs]


## 坑沿坡上的枯树：玩家能躲到树后；Boss 的招能把树打断（用原来的 Destructible，镜头被挡时自动变半透明）
static func _slope_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var D = load("res://scripts/env/destructible.gd")
	var spots := []
	var tries := 0
	while spots.size() < 13 and tries < 800:
		tries += 1
		var a := rng.randf() * 360.0
		var p := _polar(rng.randf_range(WALL_R + 1.2, 23.0), a, 0.0)  # 根墙外面（只是挡在墙后的林子）
		if gap_k(p.x, p.z) > 0.05 or p.z < -16.0 or _near_angle(a, ROOT_CLUSTERS, 12.0):
			continue
		# Boss 从古树冲进坑的那条路上不放树（开场镜头也不会被挡）
		if p.distance_to(Geometry3D.get_closest_point_to_segment(p, BOSS_SPAWN, Vector3.ZERO)) < 6.0:
			continue
		var ok := true
		for q in spots:
			if Vector2(q.x - p.x, q.z - p.z).length() < 4.5:
				ok = false
		if ok:
			spots.append(p)
	for i in spots.size():
		var p: Vector3 = spots[i]
		var h := rng.randf_range(7.0, 12.0)
		var tr := rng.randf_range(0.3, 0.55)
		var folder: String = RING_TREES[i % RING_TREES.size()]
		var mv := _model_tree(folder, "ring%d" % i, h, rng)
		if mv:
			var d = D.make_tree(mv, tr, h, 3.0, false)
			d.canopy = 2.2
			d.position = Vector3(p.x, _low_ground(p.x, p.z, 1.6), p.z)
			root.add_child(d)
			continue
		var v := _tree_visual(rng, h, tr)
		var d = D.make_tree(v[0], tr, h, 3.0, false)
		d.canopy = 2.2
		d.position = Vector3(p.x, terrain_h(p.x, p.z), p.z)
		root.add_child(d)
		for hp in v[1]:  # 有些低枝上挂着小孩的衣物
			if rng.randf() < 0.35:
				_hang(root, d.position + hp, rng)


## 坡上种树：取树根一圈里最低的地面再往下埋一点，坡上那一侧的树根埋进土里，不会有一边悬空
static func _low_ground(x: float, z: float, r: float) -> float:
	var lo := terrain_h(x, z)
	for k in 12:
		var a := k * TAU / 12.0
		for rr in [r * 0.5, r]:
			lo = minf(lo, terrain_h(x + cos(a) * rr, z + sin(a) * rr))
	# 别埋太深（南口那种挖下去的地方旁边，最低点会低好几米）
	return maxf(lo, terrain_h(x, z) - 0.8) - 0.2


## 用之前下载的树模型（tree_layout.gd 的加载：套装会切成单棵、按树干底部贴地）。去掉雪、压暗成湿树皮
static func _model_tree(folder: String, id: String, h: float, rng: RandomNumberGenerator) -> Node3D:
	if folder == "":
		return null
	if _tl == null or not is_instance_valid(_tl):
		_tl = load("res://scripts/env/tree_layout.gd").new()
	var vis := Node3D.new()
	vis.rotation.y = rng.randf() * TAU
	if not _tl._model(vis, folder, id, h, 0.0, true):
		vis.free()
		return null
	for mi: MeshInstance3D in vis.find_children("*", "MeshInstance3D", true, false):
		# 带透明的叶片卡片不能叠半透明层（会把整张方片画出来）：只给实心的树皮叠
		var solid := true
		for si in mi.mesh.get_surface_count():
			var m := mi.get_active_material(si) as BaseMaterial3D
			if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				solid = false
		mi.material_overlay = _wet_overlay() if solid else null
	return vis


static var _wet_ov: StandardMaterial3D
## 淋湿的树皮：叠一层半透明的深色（顺便盖掉 tree_layout 加的雪）
static func _wet_overlay() -> StandardMaterial3D:
	if _wet_ov == null:
		_wet_ov = StandardMaterial3D.new()
		_wet_ov.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wet_ov.albedo_color = Color(0.05, 0.05, 0.055, 0.35)
		_wet_ov.roughness = 0.45
	return _wet_ov


## 南口：出生点外面两棵树，中间横着几根低垂的枯枝，挂满小孩的衣物、拨浪鼓；旁边一只翻倒的摇篮
static func _south_foreground(root: Node3D, rng: RandomNumberGenerator) -> void:
	var D = load("res://scripts/env/destructible.gd")
	var hosts := [Vector3(-4.6, 0.0, 19.2), Vector3(4.4, 0.0, 21.0)]
	for i in hosts.size():
		var p: Vector3 = hosts[i]
		p.y = terrain_h(p.x, p.z)
		hosts[i] = p
		var v := _tree_visual(rng, 9.0 + i * 1.5, 0.5)
		var d = D.make_tree(v[0], 0.5, 9.0, 4.0, false)
		d.canopy = 2.2
		d.position = p
		root.add_child(d)
	var arrs := [[], [], []]
	var A: Vector3 = hosts[0]
	var B: Vector3 = hosts[1]
	var spans := [
		[A + Vector3(0.3, 4.2, 0.0), Vector3(3.2, 3.1, 18.2)],
		[B + Vector3(-0.3, 4.6, 0.0), Vector3(-2.6, 3.3, 21.6)],
		[A + Vector3(0.3, 3.6, 0.3), Vector3(1.4, 3.0, 22.8)],
	]
	var hangs := []
	for sp in spans:
		var s: Vector3 = sp[0]
		var e: Vector3 = sp[1]
		e.y += terrain_h(e.x, e.z)
		var m := s.lerp(e, 0.55) + Vector3.DOWN * 0.9  # 往下垂
		var pts := _curve(s, m, e, 12, rng, 0.08)
		_tube(arrs, pts, 0.17, 0.04, 6)
		for k in range(3, 11, 2):
			hangs.append(pts[k])
	_commit_tubes(root, arrs, _bark_dark, "DroopingBranches")
	for hp in hangs:
		_hang(root, hp, rng)
	# 翻倒的摇篮
	var bowl := SphereMesh.new()
	bowl.radius = 0.45
	bowl.height = 0.45
	bowl.is_hemisphere = true
	var wick := StandardMaterial3D.new()
	wick.albedo_color = Color(0.3, 0.23, 0.14)
	wick.roughness = 1.0
	wick.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cr := MeshInstance3D.new()
	cr.name = "Cradle"
	cr.mesh = bowl
	cr.material_override = wick
	cr.scale = Vector3(1.0, 0.7, 0.65)
	cr.position = Vector3(2.9, terrain_h(2.9, 17.2) + 0.25, 17.2)
	cr.rotation = Vector3(deg_to_rad(180), 0.4, deg_to_rad(65))
	root.add_child(cr)


static var _cloth_mats := {}


static func _cloth_mat(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if not _cloth_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(ENV + "cloth_sway.gdshader")
		m.set_shader_parameter("tint", c)
		_cloth_mats[key] = m
	return _cloth_mats[key]


## 在 p 点挂一样东西：小孩的肚兜 / 小褂 / 襁褓布条 / 拨浪鼓，用细绳吊着，衣物在风雨里轻轻晃
static func _hang(root: Node3D, p: Vector3, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.position = p
	holder.rotation.y = rng.randf() * TAU
	root.add_child(holder)
	var sl := rng.randf_range(0.12, 0.45)
	var rope := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.005
	cm.bottom_radius = 0.005
	cm.height = sl
	cm.radial_segments = 4
	rope.mesh = cm
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.15, 0.12, 0.1)
	rope.material_override = rope_mat
	rope.position.y = -sl * 0.5
	rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(rope)
	var kind := rng.randi() % 5
	if kind == 4:
		holder.add_child(_rattle(-sl))
		return
	var kinds := [
		[Vector2(0.3, 0.34), Color(0.42, 0.06, 0.05), 45.0],   # 红肚兜（斜挂成菱形）
		[Vector2(0.42, 0.36), Color(0.30, 0.34, 0.40), 0.0],   # 褪色的小褂
		[Vector2(0.22, 0.85), Color(0.60, 0.56, 0.48), 0.0],   # 襁褓布条
		[Vector2(0.36, 0.3), Color(0.48, 0.30, 0.20), 0.0],    # 小褂（土黄）
	]
	var k: Array = kinds[kind]
	var size: Vector2 = k[0]
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = size
	pm.subdivide_width = 3
	pm.subdivide_depth = 6
	var g := MeshInstance3D.new()
	g.mesh = pm
	g.material_override = _cloth_mat(k[1])
	g.position.y = -sl - size.y * 0.5
	g.rotation.z = deg_to_rad(k[2])
	g.set_instance_shader_parameter("top_y", size.y * 0.5)
	g.set_instance_shader_parameter("len_y", size.y)
	g.set_instance_shader_parameter("phase", rng.randf() * TAU)
	holder.add_child(g)


static func _rattle(y: float) -> Node3D:
	var n := Node3D.new()
	n.position.y = y - 0.04
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.45, 0.08, 0.05)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.12)
	var drum := CylinderMesh.new()
	drum.top_radius = 0.06
	drum.bottom_radius = 0.06
	drum.height = 0.035
	var dm := MeshInstance3D.new()
	dm.mesh = drum
	dm.material_override = red
	dm.rotation.x = PI * 0.5
	n.add_child(dm)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.01
	handle.bottom_radius = 0.012
	handle.height = 0.2
	var hm := MeshInstance3D.new()
	hm.mesh = handle
	hm.material_override = wood
	hm.position.y = -0.16
	n.add_child(hm)
	for side in [-1.0, 1.0]:
		var bead := SphereMesh.new()
		bead.radius = 0.013
		bead.height = 0.026
		var bm := MeshInstance3D.new()
		bm.mesh = bead
		bm.material_override = wood
		bm.position = Vector3(side * 0.085, -0.02, 0)
		n.add_child(bm)
	return n


## 后景的千年古树：Sketchfab「The Ancient Gnarled Tree」放大到 ~44 米
static func _giant_tree(root: Node3D) -> void:
	var path := SK + ANCIENT_TREE
	if not ResourceLoader.exists(path):
		path = SK + "the_ancient_gnarled_tree_3d_model_free/scene.gltf"
		if not ResourceLoader.exists(path):
			return
	var model: Node3D = load(path).instantiate()
	if not ANCIENT_LEAVES:  # 枯林之主：把树叶那几块藏掉，只剩枯枝
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var leafy := false
			for si in mi.mesh.get_surface_count():
				var m := mi.get_active_material(si)
				if m and m.resource_name.to_lower().contains("lea"):
					leafy = true
			if leafy:
				mi.visible = false
	var holder := Node3D.new()
	holder.name = "AncientTree"
	holder.add_child(model)
	var box := _bounds(model, true)
	var k := TREE_HEIGHT / maxf(box.size.y, 0.01)
	model.scale = Vector3.ONE * k
	model.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	holder.position = TREE_POS + Vector3(0, terrain_h(TREE_POS.x, TREE_POS.z) - TREE_SINK, 0)
	holder.rotation.y = PI
	root.add_child(holder)


static func _bounds(model: Node3D, visible_only := false) -> AABB:
	var out := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if visible_only and not mi.visible:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n and n != model:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## 罩在坑上方的枯枝：从古树伸过来，地上投下细碎的枝影；主光束那里留一个破口
static func _canopy(root: Node3D, rng: RandomNumberGenerator) -> void:
	var arrs := [[], [], []]
	var made := 0
	var tries := 0
	while made < 34 and tries < 400:
		tries += 1
		var s := TREE_POS + Vector3(rng.randf_range(-6, 6), rng.randf_range(20, 32), rng.randf_range(-2, 5))
		var e := Vector3(rng.randf_range(-17, 17), rng.randf_range(13, 22), rng.randf_range(-12, 15))
		var c := s.lerp(e, 0.5) + Vector3(0, rng.randf_range(1.0, 4.0), 0)
		var pts := _curve(s, c, e, 16, rng, 0.35)
		if _near_shaft(pts, 3.2):
			continue
		_tube(arrs, pts, rng.randf_range(0.25, 0.55), 0.05, 6)
		made += 1
		# 每根再分出几根细枝
		for b in rng.randi_range(2, 4):
			var i0 := rng.randi_range(5, 13)
			var p0: Vector3 = pts[i0]
			var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.3), rng.randf_range(-1, 1)).normalized()
			var ln := rng.randf_range(3.0, 7.0)
			var p2 := p0 + dirv * ln
			var p1 := p0.lerp(p2, 0.5) + Vector3(0, rng.randf_range(-0.5, 1.0), 0)
			var sub := _curve(p0, p1, p2, 7, rng, 0.2)
			if _near_shaft(sub, 2.6):
				continue
			_tube(arrs, sub, rng.randf_range(0.06, 0.14), 0.02, 4)
	_commit_tubes(root, arrs, _bark_dark, "Canopy")


static func _near_shaft(pts: Array, dist: float) -> bool:
	for p in pts:
		var q := Geometry3D.get_closest_point_to_segment(p, SHAFT_FROM, SHAFT_TO)
		if q.distance_to(p) < dist:
			return true
	return false


## 坑外的枯树林（程序生成的枯树，雾里只剩剪影）
static func _forest(root: Node3D, rng: RandomNumberGenerator) -> void:
	var arrs := [[], [], []]
	var placed := 0
	while placed < 55:
		var a := rng.randf() * TAU
		var r := rng.randf_range(24.0, 60.0)  # 22 米以内是能走的坡，留给有碰撞的树
		var x := cos(a) * r
		var z := sin(a) * r
		if z < CLIFF_Z + 4.0 or Vector2(x - TREE_POS.x, z - TREE_POS.z).length() < 12.0 or gap_k(x, z) > 0.3:
			continue
		placed += 1
		var base := Vector3(x, terrain_h(x, z) - 0.3, z)
		var h := rng.randf_range(7.0, 16.0)
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * h * 0.08
		var top := base + Vector3.UP * h + lean
		var trunk := _curve(base, base.lerp(top, 0.5) + lean * 0.3, top, 8, rng, 0.15)
		_tube(arrs, trunk, rng.randf_range(0.25, 0.5), 0.05, 6)
		for b in rng.randi_range(3, 6):
			var i0 := rng.randi_range(3, 6)
			var p0: Vector3 = trunk[i0]
			var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
			var ln := rng.randf_range(1.5, 4.5)
			var p2 := p0 + dirv * ln
			_tube(arrs, _curve(p0, p0.lerp(p2, 0.5) + Vector3(0, 0.3, 0), p2, 5, rng, 0.1), 0.08, 0.02, 4)
	_commit_tubes(root, arrs, _bark_dark, "DeadForest")
	# 远处再混 18 棵下载的树模型（没有碰撞），林子不再全是一个样
	var models := ["old_tree", "dead_trees", "dead_trees_demo", "spooky_tree", "dead_trees", "old_tree"]
	var n := 0
	var tries := 0
	while n < 18 and tries < 300:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(24.0, 42.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if z < CLIFF_Z + 4.0 or Vector2(x - TREE_POS.x, z - TREE_POS.z).length() < 12.0 or gap_k(x, z) > 0.3:
			continue
		var mv := _model_tree(models[n % models.size()], "far%d" % n, rng.randf_range(8.0, 15.0), rng)
		if mv == null:
			break
		mv.position = Vector3(x, _low_ground(x, z, 2.0), z)
		root.add_child(mv)
		n += 1


# ---------------- 后景：山崖、青玉矿脉、山神庙 ----------------

static func _cliff(root: Node3D, rng: RandomNumberGenerator) -> void:
	_cliff_nz = FastNoiseLite.new()
	_cliff_nz.seed = 33
	_cliff_nz.frequency = 0.05
	_cliff_nz.fractal_octaves = 4
	var cols := 70
	var rows := 30
	var w := 180.0
	var top_h := CLIFF_TOP + 5.0
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		for i in cols + 1:
			var x := -w * 0.5 + w * i / cols
			var y := -3.0 + (top_h + 3.0) * j / rows
			y = minf(y, _cliff_top(x))
			var z := _cliff_z(x, y)
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(x, y))
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			idx.append_array(PackedInt32Array([a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "castle_wall_slates/castle_wall_slates_diff_1k.jpg") if ResourceLoader.exists(TEX + "castle_wall_slates/castle_wall_slates_diff_1k.jpg") else null
	m.albedo_color = Color(0.5, 0.52, 0.55)  # 偏亮一点：隔着雾要看得出崖的轮廓
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.08
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Cliff"
	mi.mesh = st.commit()
	mi.material_override = m
	root.add_child(mi)

	# 青玉矿脉：崖面上几道发冷光的裂纹
	var arrs := [[], [], []]
	for v in 7:
		var x0 := rng.randf_range(-45, 45)
		var y0 := rng.randf_range(3, 22)
		var pts := []
		var p := Vector3(x0, y0, 0)
		for s in 10:
			p += Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.3, 1.0), 0)  # 缓一点，不然像闪电
			var zz := _cliff_z(p.x, p.y) + 0.35
			pts.append(Vector3(p.x, p.y, zz))
		_tube(arrs, pts, rng.randf_range(0.08, 0.16), 0.03, 4)
	var vein := _jade_mat.duplicate() as StandardMaterial3D
	vein.emission_energy_multiplier = 0.9
	_commit_tubes(root, arrs, vein, "JadeVeins", false)


## 崖顶半塌的山神庙：只是远景剪影，方块拼的；破窗里透一点暖光
static func _shrine(root: Node3D) -> void:
	var s := Node3D.new()
	s.name = "ShrineSilhouette"
	var top := _cliff_top(SHRINE_X)
	s.position = Vector3(SHRINE_X, top - 1.0, _cliff_z(SHRINE_X, top) - 6.0)
	s.rotation.y = deg_to_rad(-15)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.11, 0.1)
	dark.roughness = 0.9
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.08, 0.08, 0.09)
	_box(s, Vector3(0, 0.6, 0), Vector3(16, 1.2, 10), dark)        # 台基
	_box(s, Vector3(0, 3.6, 0), Vector3(12, 4.8, 7), dark)         # 殿身
	for x in [-5.0, -1.7, 1.7, 5.0]:                               # 檐柱
		_box(s, Vector3(x, 3.6, 4.2), Vector3(0.5, 4.8, 0.5), dark)
	# 屋顶：一个压扁的三棱柱 + 翘起的檐口；右半边塌了
	var pm := PrismMesh.new()
	pm.size = Vector3(10.0, 3.2, 1.0)
	var r1 := MeshInstance3D.new()
	r1.mesh = pm
	r1.material_override = roof
	r1.position = Vector3(-2.5, 7.6, 0)
	r1.rotation.y = PI * 0.5
	r1.scale = Vector3(1.0, 1.0, 9.0)
	s.add_child(r1)
	var r2 := MeshInstance3D.new()
	r2.mesh = pm
	r2.material_override = roof
	r2.position = Vector3(4.0, 6.6, 0.5)
	r2.rotation = Vector3(0.0, PI * 0.5, deg_to_rad(-24))
	r2.scale = Vector3(1.0, 0.9, 5.0)
	s.add_child(r2)
	_box(s, Vector3(-2.5, 6.05, 0), Vector3(15, 0.25, 10.5), roof)  # 出檐
	# 破窗里的暖光（长明灯）
	var win := StandardMaterial3D.new()
	win.albedo_color = Color(0, 0, 0)
	win.emission_enabled = true
	win.emission = WARM
	win.emission_energy_multiplier = 4.0
	_box(s, Vector3(-3.0, 3.4, 3.52), Vector3(1.4, 1.6, 0.05), win)
	_box(s, Vector3(2.2, 3.0, 3.52), Vector3(1.0, 2.2, 0.05), win)
	_box(s, Vector3(-0.4, 2.5, 3.52), Vector3(1.6, 3.0, 0.05), win)   # 半开的殿门
	_box(s, Vector3(4.6, 3.6, 3.52), Vector3(0.8, 1.2, 0.05), win)
	# 檐下两盏红灯笼
	var lan := StandardMaterial3D.new()
	lan.albedo_color = Color(0.5, 0.1, 0.05)
	lan.emission_enabled = true
	lan.emission = Color(1.0, 0.32, 0.14)
	lan.emission_energy_multiplier = 5.0
	for lp in [Vector3(-6.4, 5.0, 4.8), Vector3(4.2, 4.7, 4.8)]:
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 0.8
		var lm := MeshInstance3D.new()
		lm.mesh = sm
		lm.material_override = lan
		lm.position = lp
		s.add_child(lm)
	# 台基前沿一排蜡烛：远看是一串小光点（不受雾影响，雾再大也看得见）
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_texture = _glow()
	glow.albedo_color = Color(1.0, 0.62, 0.3, 0.55)
	glow.disable_fog = true
	for i in 16:
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (0.9 if i % 3 == 0 else 0.6)
		var gm := MeshInstance3D.new()
		gm.mesh = q
		gm.material_override = glow
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gm.position = Vector3(-7.0 + i * 0.9 + sin(i * 2.3) * 0.2, 1.4 + absf(sin(i * 1.7)) * 0.3, 4.9)
		s.add_child(gm)
	# 照亮殿前的暖光（雾里一团光晕）+ 殿里的长明灯
	for lp in [[Vector3(0, 3.0, 7.0), 7.0, 18.0, 3.0], [Vector3(0, 3.5, 1.0), 3.0, 8.0, 1.0]]:
		var l := OmniLight3D.new()
		l.light_color = WARM
		l.light_energy = lp[1]
		l.omni_range = lp[2]
		l.light_volumetric_fog_energy = lp[3]
		l.position = lp[0]
		s.add_child(l)
		_warm.append([l, lp[1]])
	root.add_child(s)


## 柔和的圆形光斑贴图
static var _flame_t: Texture2D
## 蜡烛火苗：上尖下圆的泪滴，中心偏白黄、外圈橙红、底部一点蓝
static func _flame_tex() -> Texture2D:
	if _flame_t == null:
		var w := 32
		var hh := 64
		var img := Image.create(w, hh, false, Image.FORMAT_RGBA8)
		for y in hh:
			for x in w:
				var v := 1.0 - float(y) / (hh - 1)          # 0 = 底，1 = 顶
				var u := (float(x) - (w - 1) * 0.5) / ((w - 1) * 0.5)  # -1 .. 1
				# 泪滴宽度：底部圆、往上收尖
				var half := sin(clampf(v, 0.0, 1.0) * PI * 0.5 + 0.35) * pow(1.0 - v, 0.6) * 0.95
				var d := absf(u) / maxf(half, 0.001)
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = pow(a, 0.7) * smoothstep(0.0, 0.08, v)
				var core := clampf(1.0 - d * 1.6, 0.0, 1.0) * (1.0 - smoothstep(0.35, 0.8, v))
				var col := Color(1.0, 0.42, 0.12).lerp(Color(1.0, 0.85, 0.45), clampf(1.0 - d, 0.0, 1.0)).lerp(Color(1.0, 0.98, 0.9), core)
				if v < 0.12:
					col = col.lerp(Color(0.35, 0.5, 1.0), (0.12 - v) / 0.12 * 0.6)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
		_flame_t = ImageTexture.create_from_image(img)
	return _flame_t


static func _glow() -> Texture2D:
	if _glow_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.2)))
		_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------- 中景 / 前景 小东西 ----------------

## 坑底撒碎石：用 rock_09 / rock_07 的网格做 MultiMesh（几百颗只占两次绘制），没有碰撞
static func _pebbles(root: Node3D, rng: RandomNumberGenerator) -> void:
	for spec in [["rock_09", 700, 0.04, 0.12], ["rock_07", 160, 0.1, 0.28]]:
		var path: String = ENV + "models/%s/%s.gltf" % [spec[0], spec[0]]
		if not ResourceLoader.exists(path):
			continue
		var model: Node3D = load(path).instantiate()
		var mis := model.find_children("*", "MeshInstance3D", true, false)
		if mis.is_empty():
			model.free()
			continue
		var src: MeshInstance3D = mis[0]
		var mesh: Mesh = src.mesh
		var mat: Material = src.get_active_material(0)
		var size := mesh.get_aabb().size
		var base_k := 1.0 / maxf(maxf(size.x, size.z), 0.001)  # 网格缩到 1 米宽，再按每颗的大小缩
		model.free()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = spec[1]
		for i in spec[1]:
			# 坑里多、靠根墙和泥地更多一点；有的扎堆
			var a := rng.randf() * TAU
			var r := pow(rng.randf(), 0.7) * (PIT_R - 0.6)
			var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
			var sz := rng.randf_range(spec[2], spec[3]) * base_k
			var b := Basis(Vector3(rng.randf_range(-1, 1), 1.0, rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.5, 0.9), sz))
			mm.set_instance_transform(i, Transform3D(b, p + Vector3(0, -size.y * sz * 0.25, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Pebbles_" + spec[0]
		mmi.multimesh = mm
		if mat:
			mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if spec[0] == "rock_09" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mmi)


## 石灯笼（可破坏的灯）。白天是灭的，天黑时（昼夜脚本）一盏盏点起来；energy 是夜里的亮度
static func _lamp(root: Node3D, pos: Vector3, rot_y: float, h: float, energy: float, rng_: float) -> void:
	var path := SK + "japanese_stone_lantern_scan_2/scene.gltf"
	if not ResourceLoader.exists(path):
		return
	var tmp := Node3D.new()
	var vis := _place(tmp, path, Vector3.ZERO, rot_y, h)
	tmp.remove_child(vis)
	tmp.free()
	var light := OmniLight3D.new()
	light.light_color = WARM
	light.light_energy = 0.0
	light.omni_range = rng_
	light.light_volumetric_fog_energy = 1.5
	light.shadow_enabled = false
	light.position = Vector3(0, h * 0.72, 0)
	# 灯室里一根短蜡烛（白天也在，只是没点）+ 火苗（泪滴形、会跳）+ 一圈很淡的光晕
	# 灯室中心是实心的石头，窗口只是浅浅的凹槽：蜡烛往前（模型 +Z）挪进窗口里，整根连火苗都得塞进窗口高度
	var fz := h * 0.075
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.62, 0.56, 0.46)
	wax.roughness = 0.6
	var cm := CylinderMesh.new()
	cm.top_radius = h * 0.012
	cm.bottom_radius = h * 0.014
	cm.height = h * 0.025
	var candle := MeshInstance3D.new()
	candle.mesh = cm
	candle.material_override = wax
	candle.position = Vector3(0, h * 0.625 + cm.height * 0.5, fz)
	vis.add_child(candle)
	var wick_top := h * 0.625 + cm.height
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	flame_mat.albedo_texture = _flame_tex()
	flame_mat.billboard_keep_scale = true
	flame_mat.albedo_color = Color(1.0, 0.85, 0.6, 0.0)
	var fq := QuadMesh.new()
	fq.size = Vector2(h * 0.028, h * 0.055)
	fq.center_offset = Vector3(0, fq.size.y * 0.45, 0)  # 底部对准灯芯，跳动时往上拉长
	var flame := MeshInstance3D.new()
	flame.mesh = fq
	flame.material_override = flame_mat
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.position = Vector3(0, wick_top - h * 0.004, fz)
	vis.add_child(flame)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.albedo_texture = _glow()
	halo_mat.albedo_color = Color(1.0, 0.55, 0.25, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2.ONE * h * 0.18
	var halo := MeshInstance3D.new()
	halo.mesh = q
	halo.material_override = halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(0, wick_top + h * 0.025, fz)
	vis.add_child(halo)
	light.position = Vector3(0, wick_top + h * 0.03, 0) + Basis(Vector3.UP, rot_y) * Vector3(0, 0, fz + h * 0.015)  # 稍在蜡烛前面，照亮烛身正面
	var D = load("res://scripts/env/destructible.gd")
	var d = D.make_lamp(vis, light, 0.35, h)
	_lanterns.append([light, energy, flame_mat, halo_mat, d, flame])
	d.position = Vector3(pos.x, terrain_h(pos.x, pos.z), pos.z)
	root.add_child(d)


static func _place(root: Node3D, path: String, pos: Vector3, rot_y: float, target_h: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = load(path).instantiate()
	var box := _bounds(model)
	var k := target_h / maxf(box.size.y, 0.01)
	model.scale = Vector3.ONE * k
	model.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	var holder := Node3D.new()
	holder.add_child(model)
	holder.position = pos
	holder.rotation.y = rot_y
	root.add_child(holder)
	return holder


static func _props(root: Node3D, rng: RandomNumberGenerator) -> void:
	var pm := ENV + "models/%s/%s.gltf"
	# 坑沿外：倒木、树桩、烧焦的树桩、石头
	var items := [["dead_tree_trunk", 1.2, 4], ["dead_tree_trunk_02", 1.0, 3], ["tree_stump_01", 1.0, 4], ["tree_stump_02", 1.0, 3], ["boulder_01", 1.6, 4]]
	for it in items:
		for k in it[2]:
			var a := rng.randf() * TAU
			var r := rng.randf_range(22.5, 28.0)  # 能走的坡（22 米以内）上不放没碰撞的东西
			var x := cos(a) * r
			var z := sin(a) * r
			if gap_k(x, z) > 0.3 or z < -36.0:
				continue
			var n := _place(root, pm % [it[0], it[0]], Vector3(x, terrain_h(x, z) - 0.1, z), rng.randf() * TAU, it[1] * rng.randf_range(0.8, 1.3))
			if n and it[0] == "dead_tree_trunk":
				n.rotation.z = rng.randf_range(-0.1, 0.1)
	for k in 5:
		var a := rng.randf() * TAU
		var r := rng.randf_range(22.5, 27.0)
		_place(root, SK + "burnt_stump/scene.gltf", Vector3(cos(a) * r, terrain_h(cos(a) * r, sin(a) * r) - 0.1, sin(a) * r), rng.randf() * TAU, rng.randf_range(0.8, 1.6))
	# 坑里散落的枯枝（没有碰撞）
	for k in 10:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (PIT_R - 1.0)
		_place(root, pm % ["dry_branches_medium_01", "dry_branches_medium_01"], Vector3(cos(a) * r, -0.02, sin(a) * r), rng.randf() * TAU, rng.randf_range(0.25, 0.45))
	# 南口两侧的石灯笼（一盏还亮着，一盏早灭了）
	# 石灯笼都是可破坏的灯（有碰撞，Boss 打到会碎、灯灭；挡镜头时变半透明）
	_lamp(root, Vector3(-3.0, 0.0, 16.0), 0.3, 1.7, 1.6, 6.0)
	_lamp(root, Vector3(3.2, 0.0, 16.4), -0.4, 1.6, 1.3, 5.0)
	# 西南：将灭的石灯（以后旁边摆翻倒的牛车）
	_lamp(root, Vector3(-11.6, 0.0, 7.6), 0.8, 1.5, 0.9, 4.5)
	# 东北：露出青玉的断石
	var rock := _place(root, pm % ["rock_07", "rock_07"], Vector3(11.4, -0.2, -8.6), 0.6, 1.4)
	if rock:
		var arrs := [[], [], []]
		for c in 6:
			var b := Vector3(11.4 + rng.randf_range(-0.6, 0.6), 0.5 + rng.randf_range(0, 0.5), -8.6 + rng.randf_range(-0.6, 0.6))
			var d := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()
			_tube(arrs, [b, b + d * rng.randf_range(0.25, 0.6)], rng.randf_range(0.07, 0.13), 0.01, 5)
		_commit_tubes(root, arrs, _jade_mat, "JadeShards", false)
		var rb := StaticBody3D.new()  # 断石挡主角
		rb.collision_layer = PLAYER_ONLY_LAYER
		rb.collision_mask = 0
		var rc := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.8
		cy.height = 1.6
		rc.shape = cy
		rc.position = Vector3(11.4, 0.6, -8.6)
		rb.add_child(rc)
		root.add_child(rb)
	# 树根下的残烛供品：几根矮蜡烛
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.55, 0.5, 0.42)
	var flame := StandardMaterial3D.new()
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(1.0, 0.7, 0.35)
	flame.emission_enabled = true
	flame.emission = WARM
	flame.emission_energy_multiplier = 6.0
	var candles := Node3D.new()
	candles.name = "Candles"
	candles.position = Vector3(-1.6, 0.0, -15.0)
	for c in 7:
		var h := rng.randf_range(0.06, 0.22)
		var off := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.3, 0.3))
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.04
		cm.height = h
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = wax
		mi.position = off + Vector3(0, h * 0.5, 0)
		candles.add_child(mi)
		if c < 4:
			var f := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.018
			sm.height = 0.06
			f.mesh = sm
			f.material_override = flame
			f.position = off + Vector3(0, h + 0.03, 0)
			candles.add_child(f)
	root.add_child(candles)


## 茜草：暗红色的枯草丛 + 小红果，长在根缝、坑边和前景
static func _madder(root: Node3D, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 16:
		var a := TAU * k / 16.0 + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.06, 0.2)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.012
		var top := lean + Vector3(0, rng.randf_range(0.22, 0.5), 0)
		st.set_normal(Vector3.UP)
		st.add_vertex(-side)
		st.add_vertex(side)
		st.add_vertex(top)
	var tuft := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.7
	tuft.surface_set_material(0, m)
	var palette := [Color(0.34, 0.09, 0.07), Color(0.27, 0.07, 0.06), Color(0.40, 0.14, 0.09), Color(0.24, 0.12, 0.08)]
	var berry_mesh := SphereMesh.new()
	berry_mesh.radius = 0.028
	berry_mesh.height = 0.056
	berry_mesh.radial_segments = 6
	berry_mesh.rings = 3
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.45, 0.02, 0.04)
	bm.roughness = 0.25
	berry_mesh.material = bm

	var spots := []  # 丛中心：(x, z, 半径, 数量)
	for g in GAPS:
		for side in [-1.0, 1.0]:
			var a := deg_to_rad(g)
			var c: Vector2 = Vector2(cos(a), sin(a)) * (WALL_R - 0.3) + Vector2(-sin(a), cos(a)) * side * (GAP_HALF + 0.6)
			spots.append([c.x, c.y, 1.3, 60])
	for k in 10:
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rng.randf_range(PIT_R - 2.0, PIT_R)
		spots.append([c.x, c.y, 1.0, 40])
	for k in 26:  # 坑里到处零星几丛，跑着跑着脚底下就踩到
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (PIT_R - 2.0)
		spots.append([c.x, c.y, rng.randf_range(0.5, 1.0), rng.randi_range(10, 28)])
	for k in 10:  # 坑外前景
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rng.randf_range(16.5, 21.0)
		spots.append([c.x, c.y, 1.6, 60])

	var tx := []
	var bx := []
	for sp in spots:
		for i in sp[3]:
			var a := rng.randf() * TAU
			var r: float = sqrt(rng.randf()) * sp[2]
			var x: float = sp[0] + cos(a) * r
			var z: float = sp[1] + sin(a) * r
			var y := terrain_h(x, z)
			var s := rng.randf_range(0.7, 1.4)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.3), s))
			tx.append(Transform3D(basis, Vector3(x, y, z)))
			if rng.randf() < 0.35:
				for b in 3:
					bx.append(Transform3D(Basis(), Vector3(x + rng.randf_range(-0.08, 0.08), y + rng.randf_range(0.12, 0.35) * s, z + rng.randf_range(-0.08, 0.08))))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft
	mm.instance_count = tx.size()
	for i in tx.size():
		mm.set_instance_transform(i, tx[i])
		mm.set_instance_color(i, palette[rng.randi() % palette.size()])
	var inst := MultiMeshInstance3D.new()
	inst.name = "Madder"
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)
	var mb := MultiMesh.new()
	mb.transform_format = MultiMesh.TRANSFORM_3D
	mb.mesh = berry_mesh
	mb.instance_count = bx.size()
	for i in bx.size():
		mb.set_instance_transform(i, bx[i])
	var binst := MultiMeshInstance3D.new()
	binst.name = "MadderBerries"
	binst.multimesh = mb
	binst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(binst)


# ---------------- 光、雾、天气 ----------------

## 3D 画面按 0.75 倍分辨率渲染再用 FSR 放大（2D 的 HUD / 字幕不受影响）。
## 体积雾 + SSR + SSAO 在 2560×1440 全屏只有约 74 fps，这样约 99 fps。按 R 重开会再设一次，值一样
const RENDER_SCALE := 0.75
const FSR_SHARPNESS := 0.2   # 0 最锐，2 最糊

static func _render_scale(root: Node3D) -> void:
	var vp := root.get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = RENDER_SCALE
	vp.fsr_sharpness = FSR_SHARPNESS


static func _environment(root: Node3D) -> void:
	env = Environment.new()
	# 灰暗的阴天天空：主要给水洼一个可以倒映的天光（不然水洼是一块块黑斑）
	var sky_mat := ProceduralSkyMaterial.new()
	_sky_mat = sky_mat
	sky_mat.sky_top_color = Color(0.13, 0.14, 0.16)
	sky_mat.sky_horizon_color = Color(0.24, 0.25, 0.27)
	sky_mat.ground_horizon_color = Color(0.24, 0.25, 0.27)
	sky_mat.ground_bottom_color = Color(0.07, 0.07, 0.08)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.52)
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.17, 0.19, 0.22)
	env.fog_density = 0.011
	env.fog_sky_affect = 1.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.014
	env.volumetric_fog_albedo = Color(0.82, 0.84, 0.88)
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.12
	env.ssr_enabled = true  # 水洼倒影
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.62
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)


static func _lights(root: Node3D) -> void:
	# 阴天的散光：很弱、偏冷，带阴影（透过头顶枯枝投下细碎的影子，雾里一道道细光）
	var sky := DirectionalLight3D.new()
	_overcast = sky
	sky.name = "Overcast"
	sky.light_color = SKY_LIGHT
	sky.light_energy = 0.45
	sky.light_volumetric_fog_energy = 1.2
	sky.shadow_enabled = true
	sky.directional_shadow_max_distance = 70.0
	sky.rotation_degrees = Vector3(-62.0, 200.0, 0.0)
	root.add_child(sky)

	# 主光束：云缝 + 树冠破口漏下来的一束冷光，斜照在坑底偏中间
	shaft = SpotLight3D.new()
	shaft.name = "LightShaft"
	shaft.light_color = SKY_LIGHT
	shaft.light_energy = 9.0
	shaft.light_volumetric_fog_energy = 4.0
	shaft.spot_range = 60.0
	shaft.spot_angle = 9.0
	shaft.spot_angle_attenuation = 0.6
	shaft.spot_attenuation = 0.3
	shaft.shadow_enabled = true
	root.add_child(shaft)
	shaft.look_at_from_position(SHAFT_FROM, SHAFT_TO, Vector3.FORWARD)

	# 根缝透光：每个根缝外面一盏低角度的冷光，往坑里拉出一条亮带，也给玩家指路
	for g in GAPS:
		var a := deg_to_rad(g)
		var from := Vector3(cos(a) * 25.0, 0.0, sin(a) * 25.0)
		from.y = terrain_h(from.x, from.z) + 3.2
		var to := Vector3(cos(a) * 7.0, 0.0, sin(a) * 7.0)
		var sl := SpotLight3D.new()
		sl.name = "GapLight"
		sl.light_color = Color(0.72, 0.78, 0.9)
		sl.light_energy = 3.5
		sl.light_volumetric_fog_energy = 2.5
		sl.spot_range = 30.0
		sl.spot_angle = 13.0
		sl.spot_attenuation = 0.5
		sl.shadow_enabled = false
		root.add_child(sl)
		sl.look_at_from_position(from, to, Vector3.UP)
		_gap_lights.append(sl)

	# 暖光点缀：树根下的残烛（石灯笼的光在 _lamp 里）
	for p in [[Vector3(-1.6, 0.35, -15.0), 1.1, 4.0]]:
		var o := OmniLight3D.new()
		o.light_color = WARM
		o.light_energy = p[1]
		o.omni_range = p[2]
		o.light_volumetric_fog_energy = 1.5
		o.shadow_enabled = false
		o.position = p[0]
		root.add_child(o)
		_warm.append([o, p[1]])

	# 青玉的冷光：崖面矿脉整体一盏弱光 + 断石旁一盏
	for p in [[Vector3(0, 12, CLIFF_Z + 4.0), 2.0, 30.0], [Vector3(11.0, 1.0, -8.0), 0.8, 3.5]]:
		var o := OmniLight3D.new()
		o.light_color = JADE
		o.light_energy = p[1]
		o.omni_range = p[2]
		o.shadow_enabled = false
		o.position = p[0]
		root.add_child(o)


## 二阶段（犀渠狂怒）：光束变暗、变红，雾带一点血色，雨更大（颜色由昼夜脚本按 rage 混进去）
static func phase2(root: Node) -> void:
	var tw := root.create_tween().set_parallel(true)
	if daynight:
		tw.tween_property(daynight, "rage", 1.0, 2.5)
	if rain:
		tw.tween_property(rain, "intensity", 1.0, 2.0)
