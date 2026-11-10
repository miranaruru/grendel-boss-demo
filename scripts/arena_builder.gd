@tool
extends RefCounted
## 程序化搭建：灰败枯木森林里的一块圆形空地，地上一块块的残雪，飘着小雪。
## 地面 / 树皮 / 雪的贴图和石头、倒木、树桩、枯枝模型来自 Poly Haven（CC0，见 assets/env/CREDITS.md）。
## 枯树还是代码生成的（Poly Haven 没有站立的枯树），换成美术资源时直接替换 make_tree()。
## 石头 / 倒木 / 树桩 / 枯枝 / 枯树的摆放由 scenes/env_layout.tscn（EnvScatter）按规则决定，可以在编辑器里调。

## 积雪量（0 = 没雪，1 = 几乎全白）。地面雪块、树 / 石头顶上的雪都跟着它变
const SNOW_COVER := 0.45

## 竞技场石台（半径 18 的战斗区）。高度都是相对外面地面（y = 0）的米数，坡都很缓（< 12°），能直接走上去
const PLATFORM_RADIUS := 12.0
const PLATFORM_TOP := 0.5           # 石台整体比地面高多少（0.25 → 0.5：边上的石头台阶要有高度差才看得出是台阶）
const DAIS_HEIGHT := 0.6            # 北侧（废墟那边）抬高的台子
const DAIS_START_Z := -4.5          # 从 z = -4.5 开始往北慢慢升高（朝拱门那边）
const DAIS_RAMP := 3.0              # 升高用多少米的坡
const TERRACE := [Vector3(-7.0, 0.35, 2.0)]    # 西侧一块抬高的石阶：(x, 高度, z)
const TERRACE_R := 2.2                         # 石阶平顶半径，外面再 1.5 米的坡
const BASIN := [Vector3(6.0, -0.12, 6.0)]      # 东南一块微微下沉的地方
const BASIN_R := 1.5
const GROUND_LAYER := 2             # 地面 / 石台额外放在第 2 个渲染层，预警圈只投到这一层

const ENV := "res://assets/env/"
const TEX := ENV + "textures/"

static var _bark: Material
static var _bark_dark: Material
static var _snow_cap: ShaderMaterial
static var _snow_mask: Texture2D
static var _mask_img: Image


const LAYOUT_SCENE := "res://scenes/env_layout.tscn"

## 方案 B「枯林巢穴」（arena-redesign-b 分支）：true = 用 lair_builder.gd 搭新战场；false = 原来的石台 + 枯林
## 注意：旧石台 + 枯林用的资源（石桥、石板台子、苔石堆、鹅卵石地面等）已从本项目删掉，false 跑不起来了。
## 旧场地完整保存在 ../withered_forest_arena_demo 和 old-arena-forest 分支
const USE_LAIR := true
const LairBuilder = preload("res://scripts/lair_builder.gd")


static func build(root: Node3D, radius: float) -> void:
	if USE_LAIR:
		LairBuilder.build(root)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	ensure_materials()

	_environment(root)
	_ground(root, radius)
	if ResourceLoader.exists(LAYOUT_SCENE):
		root.add_child(load(LAYOUT_SCENE).instantiate())  # 按规则摆边缘石头、散落枯枝（见 env_scatter.gd）
		var trees := Node3D.new()  # 树 / 倒木 / 树桩 / A1 废墟：手工定点（方案 A，见 tree_layout.gd）
		trees.name = "TreeLayout"
		trees.set_script(load("res://scripts/env/tree_layout.gd"))
		root.add_child(trees)
	else:
		_border_rocks(root, radius, rng)
		_props(root, radius, rng)
		_trees(root, radius, rng)
	_platform(root)
	_leaves(root, radius, rng)  # 不要草了；落叶只撒在石台外面
	_snowfall(root, radius)


## 共享材质：树皮、积雪覆盖层、积雪噪声图（编辑器里预览摆放时也会调用）
static func ensure_materials() -> void:
	if _snow_cap:
		return
	_make_snow_mask()
	_bark = _bark_mat(Color(0.62, 0.6, 0.58))
	_bark_dark = _bark_mat(Color(0.38, 0.37, 0.36))
	_snow_cap = ShaderMaterial.new()
	_snow_cap.shader = load(ENV + "snow_cap.gdshader")
	_snow_cap.set_shader_parameter("snow_albedo", load(TEX + "snow_02/snow_02_diffuse_1k.jpg"))
	_snow_cap.set_shader_parameter("snow_mask", _snow_mask)
	_snow_cap.set_shader_parameter("cover", SNOW_COVER)


static func snow_cap() -> ShaderMaterial:
	ensure_materials()
	return _snow_cap


static func _mat(c: Color, rough: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _bark_mat(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "bark_willow_02/bark_willow_02_diffuse_1k.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + "bark_willow_02/bark_willow_02_nor_gl_1k.jpg")
	m.roughness_texture = load(TEX + "bark_willow_02/bark_willow_02_rough_1k.jpg")
	m.uv1_triplanar = true          # 代码生成的圆柱 UV 会拉伸，用三向投影贴树皮
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.8
	return m


## 一张无缝噪声图：地面雪块分布、树 / 石头顶上雪的边缘都用它；草也按它避开雪块
static func _make_snow_mask() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1471
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	_mask_img = noise.get_seamless_image(512, 512)
	_snow_mask = ImageTexture.create_from_image(_mask_img)


## 世界坐标 (x, z) 处地面有没有雪（和 ground_snow.gdshader 用同一套算法）
static func _snow_at(x: float, z: float, radius: float) -> float:
	var cover := SNOW_COVER * lerpf(0.5, 1.0, smoothstep(radius * 0.6, radius + 3.0, Vector2(x, z).length()))
	var u := fposmod(x * 0.04, 1.0)
	var v := fposmod(z * 0.04, 1.0)
	var n := _mask_img.get_pixel(int(u * 511.0), int(v * 511.0)).r
	return smoothstep(1.0 - cover - 0.05, 1.0 - cover + 0.05, n)


static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.38, 0.41)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.53, 0.58)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.44, 0.47)
	env.fog_density = 0.035
	env.glow_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.55
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(0.82, 0.84, 0.90)
	sun.shadow_enabled = true
	root.add_child(sun)
	var moon := DirectionalLight3D.new()  # 月光：冷蓝、较暗，雪地会反出蓝白色
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.shadow_enabled = true
	root.add_child(moon)
	# 昼夜循环：按时间转动太阳 / 月亮，调天空、雾、环境光
	var dn: Node = load("res://scripts/day_night.gd").new()
	dn.name = "DayNight"
	root.add_child(dn)
	dn.setup(env, sun, moon)


static func _ground(root: Node3D, radius: float) -> void:
	# 碰撞：一整块大地板（玩家/ Boss 的活动范围在脚本里按圆形限制）
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	col.shape = box
	col.position.y = -0.5
	body.add_child(col)
	root.add_child(body)

	# 地面：枯叶 + 积雪（竞技场中间被踩过，雪少一点）
	var m := ShaderMaterial.new()
	m.shader = load(ENV + "ground_snow.gdshader")
	m.set_shader_parameter("leaves_albedo", load(TEX + "winter_leaves/winter_leaves_diffuse_1k.jpg"))
	m.set_shader_parameter("leaves_normal", load(TEX + "winter_leaves/winter_leaves_nor_gl_1k.jpg"))
	m.set_shader_parameter("leaves_rough", load(TEX + "winter_leaves/winter_leaves_rough_1k.jpg"))
	m.set_shader_parameter("snow_albedo", load(TEX + "snow_02/snow_02_diffuse_1k.jpg"))
	m.set_shader_parameter("snow_normal", load(TEX + "snow_02/snow_02_nor_gl_1k.jpg"))
	m.set_shader_parameter("snow_rough", load(TEX + "snow_02/snow_02_rough_1k.jpg"))
	m.set_shader_parameter("snow_mask", _snow_mask)
	m.set_shader_parameter("snow_cover", SNOW_COVER)
	m.set_shader_parameter("arena_radius", radius)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.material_override = m
	ground.layers = 1 | GROUND_LAYER
	root.add_child(ground)


## 世界坐标 (x, z) 处脚下地面的高度（石台上 / 石台外）
static func ground_height(x: float, z: float) -> float:
	if USE_LAIR:
		return LairBuilder.terrain_h(x, z)
	if Vector2(x, z).length() > PLATFORM_RADIUS - 0.2:
		return 0.0
	return _platform_h(x, z)


static func _platform_h(x: float, z: float) -> float:
	var dais := smoothstep(DAIS_START_Z, DAIS_START_Z - DAIS_RAMP, z)
	# 边缘缓坡降到地面，能走上走下：南边 1.2 米宽；北边高台更高，坡放宽到 2.5 米（坡度都在 35° 以内）
	var edge := 1.0 - smoothstep(PLATFORM_RADIUS - 1.2 - 1.3 * dais, PLATFORM_RADIUS, Vector2(x, z).length())
	var h := PLATFORM_TOP
	h += DAIS_HEIGHT * dais
	for t in TERRACE:
		h += t.y * (1.0 - smoothstep(TERRACE_R, TERRACE_R + 1.5, Vector2(x - t.x, z - t.z).length()))
	for b in BASIN:
		h += b.y * (1.0 - smoothstep(BASIN_R, BASIN_R + 2.0, Vector2(x - b.x, z - b.z).length()))
	return h * edge


## 石台边缘不规则（缺角、碎边）
static func _edge_r(a: float) -> float:
	return PLATFORM_RADIUS + sin(a * 5.0) * 0.25 + sin(a * 13.0 + 1.3) * 0.18 + sin(a * 29.0) * 0.08


static func _platform(root: Node3D) -> void:
	var rings := 46
	var segs := 160
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in rings + 1:
		var row := []
		for j in segs:
			var a := TAU * j / segs
			var r := _edge_r(a) * float(i) / rings
			var x := cos(a) * r
			var z := sin(a) * r
			var h := _platform_h(x, z)
			row.append(Vector3(x, h, z))
		pts.append(row)
	var center := Vector3(0, _platform_h(0, 0), 0)
	for j in segs:
		var j2 := (j + 1) % segs
		_tri(st, center, pts[1][j], pts[1][j2])  # Godot 正面 = 顺时针；从上往下看要朝上
		for i in range(1, rings):
			_tri(st, pts[i][j], pts[i + 1][j], pts[i][j2])
			_tri(st, pts[i][j2], pts[i + 1][j], pts[i + 1][j2])
	st.generate_normals()
	st.generate_tangents()
	var top := st.commit()

	var m := ShaderMaterial.new()
	m.shader = load(ENV + "platform_stone.gdshader")
	m.set_shader_parameter("stone_albedo", load(TEX + "cobblestone_large_01/cobblestone_large_01_diffuse_1k.jpg"))
	m.set_shader_parameter("stone_normal", load(TEX + "cobblestone_large_01/cobblestone_large_01_nor_gl_1k.jpg"))
	m.set_shader_parameter("stone_rough", load(TEX + "cobblestone_large_01/cobblestone_large_01_rough_1k.jpg"))
	m.set_shader_parameter("stone_disp", load(TEX + "cobblestone_large_01/cobblestone_large_01_displacement_1k.jpg"))
	m.set_shader_parameter("snow_albedo", load(TEX + "snow_02/snow_02_diffuse_1k.jpg"))
	m.set_shader_parameter("snow_mask", _snow_mask)
	var mi := MeshInstance3D.new()
	mi.name = "ArenaPlatform"
	mi.mesh = top
	mi.material_override = m
	mi.layers = 1 | GROUND_LAYER
	root.add_child(mi)

	# 碰撞：台面本身（外面的大地板还在下面）
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = top.create_trimesh_shape()
	body.add_child(col)
	root.add_child(body)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


## 把一个 Poly Haven 模型摆进场景，并给所有网格盖上积雪覆盖层
static func _place(root: Node3D, model: String, pos: Vector3, rot_y: float, scl: float, tilt: Vector3 = Vector3.ZERO) -> Node3D:
	var n: Node3D = load(ENV + "models/%s/%s.gltf" % [model, model]).instantiate()
	n.position = pos
	n.rotation = Vector3(tilt.x, rot_y, tilt.z)
	n.scale = Vector3.ONE * scl
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _snow_cap
	root.add_child(n)
	return n


static func _border_rocks(root: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	# 竞技场边缘一圈石头（真实扫描模型，放大成大石块）
	var count := 26
	for i in count:
		var a: float = TAU * i / count + rng.randf_range(-0.06, 0.06)
		var r := radius + rng.randf_range(0.4, 1.4)
		var pos := Vector3(cos(a) * r, -0.05, sin(a) * r)
		if i % 5 == 0:
			_place(root, "boulder_01", pos, rng.randf() * TAU, rng.randf_range(0.6, 1.1))
		elif i % 2 == 0:
			_place(root, "rock_07", pos, rng.randf() * TAU, rng.randf_range(4.0, 7.0))
		else:
			_place(root, "rock_09", pos, rng.randf() * TAU, rng.randf_range(8.0, 13.0))


static func _props(root: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	# 倒木、树桩、枯枝：放在竞技场外面一圈（不挡打斗），枯枝也散一点在场内（没有碰撞，只是装饰）
	var outside := [["dead_tree_trunk_02", 1.0, 4], ["dead_tree_trunk", 1.3, 5], ["tree_stump_01", 1.1, 4], ["tree_stump_02", 1.1, 4], ["dry_branches_medium_01", 1.2, 8]]
	for item in outside:
		for k in item[2]:
			var a := rng.randf() * TAU
			var r := rng.randf_range(radius + 1.8, radius + 7.0)
			_place(root, item[0], Vector3(cos(a) * r, -0.05, sin(a) * r), rng.randf() * TAU, item[1] * rng.randf_range(0.8, 1.2))
	for k in 7:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (radius - 2.0)
		_place(root, "dry_branches_medium_01", Vector3(cos(a) * r, -0.02, sin(a) * r), rng.randf() * TAU, rng.randf_range(0.7, 1.0))


static func _trees(root: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	# 紧贴空地边缘的一圈 + 远处若干，雾会把远处吃掉
	for i in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius + 1.5, radius + 7.0)
		make_tree(root, Vector3(cos(a) * r, 0, sin(a) * r), rng, rng.randf_range(0.8, 1.3))
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius + 7.0, radius + 30.0)
		make_tree(root, Vector3(cos(a) * r, 0, sin(a) * r), rng, rng.randf_range(0.9, 1.6))


static func make_tree(root: Node3D, pos: Vector3, rng: RandomNumberGenerator, size: float) -> void:
	ensure_materials()
	var tree := Node3D.new()
	tree.position = pos
	tree.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf() * TAU, rng.randf_range(-0.12, 0.12))
	var mat := _bark if rng.randf() < 0.6 else _bark_dark

	var broken := rng.randf() < 0.2  # 断树桩
	var h := rng.randf_range(5.0, 11.0) * size
	if broken:
		h = rng.randf_range(1.2, 3.0)

	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22 if broken else 0.07
	cm.bottom_radius = rng.randf_range(0.25, 0.45) * size
	cm.height = h
	cm.radial_segments = 7
	cm.rings = 2
	trunk.mesh = cm
	trunk.position.y = h * 0.5
	trunk.material_override = mat
	trunk.material_overlay = _snow_cap
	tree.add_child(trunk)

	if not broken:
		for i in rng.randi_range(3, 7):
			_branch(tree, rng.randf_range(h * 0.3, h * 0.92), rng.randf_range(0.8, 3.2) * size, rng, mat, true)
	root.add_child(tree)


static func _branch(parent: Node3D, y: float, length: float, rng: RandomNumberGenerator, mat: Material, allow_child: bool) -> void:
	var pivot := Node3D.new()
	pivot.position.y = y
	pivot.rotation = Vector3(0, rng.randf() * TAU, 0)
	var tilt := Node3D.new()
	tilt.rotation.z = rng.randf_range(0.5, 1.3)  # 向外斜伸
	pivot.add_child(tilt)
	var b := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.015
	bm.bottom_radius = 0.07 * clampf(length / 2.0, 0.4, 1.2)
	bm.height = length
	bm.radial_segments = 5
	bm.rings = 1
	b.mesh = bm
	b.position.y = length * 0.5
	b.material_override = mat
	b.material_overlay = _snow_cap
	tilt.add_child(b)
	if allow_child and length > 1.5:
		for i in rng.randi_range(1, 2):
			_branch(tilt, rng.randf_range(length * 0.4, length * 0.8), length * 0.45, rng, mat, false)
	parent.add_child(pivot)


## 枯草丛：几根细长的三角形叶片拼成一簇，只长在没雪的地方
static func _grass(root: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 14:
		var a := TAU * k / 14.0 + rng.randf_range(-0.3, 0.3)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.04, 0.16)
		var side := Vector3(-sin(a), 0, cos(a)) * 0.008
		var top := lean + Vector3(0, rng.randf_range(0.16, 0.36), 0)
		st.set_normal(Vector3.UP)
		st.add_vertex(-side)
		st.add_vertex(side)
		st.add_vertex(top)
	var tuft := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	tuft.surface_set_material(0, m)

	var palette := [Color(0.36, 0.32, 0.25), Color(0.30, 0.27, 0.22), Color(0.40, 0.36, 0.28), Color(0.27, 0.25, 0.22)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tuft
	var xforms := []
	for i in 9000:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (radius + 14.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if _snow_at(x, z, radius) > 0.3:
			continue
		var s := rng.randf_range(0.8, 1.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.3), s))
		xforms.append(Transform3D(basis, Vector3(x, 0.0, z)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, palette[rng.randi() % palette.size()])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)


static func _leaves(root: Node3D, radius: float, rng: RandomNumberGenerator) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 0.6)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true  # 调色板写的是 sRGB 颜色；不标的话会被当线性色，显得发白
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	quad.material = m

	var palette := [Color(0.24, 0.20, 0.15), Color(0.19, 0.16, 0.12), Color(0.28, 0.25, 0.20), Color(0.17, 0.17, 0.15)]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 700  # 地面贴图本身就是枯叶了，散落的叶片只点缀一下
	for i in mm.instance_count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range((PLATFORM_RADIUS + 0.5) * (PLATFORM_RADIUS + 0.5), 38.0 * 38.0))  # 只撒在石台外面
		var s := rng.randf_range(0.12, 0.32)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5 + rng.randf_range(-0.3, 0.3))
		basis = basis.scaled(Vector3(s, s, s))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(cos(a) * r, 0.02 + rng.randf() * 0.03, sin(a) * r)))
		mm.set_instance_color(i, palette[rng.randi() % palette.size()])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	root.add_child(inst)


static func _snowfall(root: Node3D, radius: float) -> void:
	# 小雪：慢慢飘落、带一点横风
	var p := GPUParticles3D.new()
	p.amount = 900
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.position.y = 12.0
	p.visibility_aabb = AABB(Vector3(-40, -16, -40), Vector3(80, 20, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40.0, 1.0, 40.0)  # 盖住整个能跑的树林
	pm.direction = Vector3(0.25, -1.0, 0.1)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.9
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.0, -0.05, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.95, 0.96, 1.0, 0.8)
	q.material = qm
	p.draw_pass_1 = q
	root.add_child(p)
