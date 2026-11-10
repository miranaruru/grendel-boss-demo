@tool
class_name Destructible
extends Node3D
## 可破坏物：树 / 灯 / 拱门。放在 "destructible" 组里，Boss 的攻击判定会检查它们（见 boss.gd 的 _hit_destructibles）。
## 结构：本节点 = 底部中心；visual = 模型；body = StaticBody3D（挡玩家和 Boss，也挡镜头）。
## 玩家的攻击不会打坏它们。

signal broken

enum Kind { TREE, LAMP, ARCH }

const DUST_COLOR := Color(0.85, 0.86, 0.88, 0.7)
const RUBBLE_LAYER := 128  # 第 8 层：拱门碎石只挡主角（主角 mask 含这一层），Boss 体型大直接踩过去，不会卡在碎石堆上
const ArenaBuilder = preload("res://scripts/arena_builder.gd")

static var _puff_tex: Texture2D
static var _stone_mat: StandardMaterial3D
static var _rocks: Array = []  # 70_stylized_rocks 切出来的每块石头：[mesh, 居中用的变换, 尺寸]

const ROCK_PACK := "res://assets/env/sketchfab/70_stylized_rocks/scene.gltf"
const ROCK_TINT := Color(0.78, 0.8, 0.8)  # 卡通石头的贴图偏亮偏蓝，压暗一点贴近拱门的石头
# 只用其中 14 块：长宽高差不多的「块状」石头（扁片、细长条不像拱门砌块），也少加载些贴图（每块一张）
const ROCK_PICK := [11, 16, 22, 23, 27, 28, 30, 31, 32, 33, 36, 38, 41, 45]


## 拱门碎块用的石头：第一次用时把石头包拆成一块块（每块挪到自己的中心）
static func _rock_pool() -> Array:
	if _rocks.is_empty() and ResourceLoader.exists(ROCK_PACK):
		var root: Node3D = load(ROCK_PACK).instantiate()
		var all := root.find_children("*", "MeshInstance3D", true, false)
		for idx in ROCK_PICK:
			if idx >= all.size():
				continue
			var mi: MeshInstance3D = all[idx]
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n and n != root:
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var box := xf * mi.get_aabb()
			var mats := []
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				if m is StandardMaterial3D:
					m = m.duplicate()
					m.albedo_color = ROCK_TINT
				mats.append(m)
			_rocks.append([mi.mesh, Transform3D(xf.basis, xf.origin - box.get_center()), box.size, mats])
		root.free()
	return _rocks


## 一块石头（最长边 = size 米），返回 [节点, 用来做碰撞的凸包点（已缩放）]
static func _rock_node(size: float) -> Array:
	var pool := _rock_pool()
	var r: Array = pool[randi() % pool.size()]
	var dims: Vector3 = r[2]
	var k := size / maxf(dims[dims.max_axis_index()], 0.01)
	var mi := MeshInstance3D.new()
	mi.mesh = r[0]
	mi.transform = Transform3D(r[1].basis.scaled(Vector3.ONE * k), r[1].origin * k)
	for si in r[3].size():
		mi.set_surface_override_material(si, r[3][si])
	var pts := PackedVector3Array()
	var verts: PackedVector3Array = r[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0, verts.size(), maxi(1, verts.size() / 160)):  # 凸包抽 ~160 个点：太少的话凸包比石头小，落地会陷进地里
		pts.append(mi.transform * verts[i])
	return [mi, pts]


## 柔和的圆形烟团贴图（不然粒子是硬边方块）
static func _puff() -> Texture2D:
	if _puff_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.6)))
		_puff_tex = ImageTexture.create_from_image(img)
	return _puff_tex


## 碎石材质：真实岩石贴图（三向投影）
static func _stone() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_texture = load("res://assets/env/models/boulder_01/textures/boulder_01_diff_1k.jpg")
		_stone_mat.albedo_color = Color(0.7, 0.7, 0.7)
		_stone_mat.normal_enabled = true
		_stone_mat.normal_texture = load("res://assets/env/models/boulder_01/textures/boulder_01_nor_gl_1k.jpg")
		_stone_mat.roughness = 0.95
		_stone_mat.uv1_triplanar = true
		_stone_mat.uv1_world_triplanar = true
		_stone_mat.uv1_scale = Vector3.ONE * 0.6
	return _stone_mat

var kind: Kind = Kind.TREE
var hp := 2.0                     ## 能挨几下（按次数算，不按伤害）：普通招 1 下，重招（重劈 / 扑击）算 2 下
var radius := 0.4                 ## 粗细（米）：判定是否在攻击范围里、是否挡住攻击
var height := 6.0
var contact_breakable := false    ## Boss 走路撞上就直接撞断（小树）
var damaged_by := ["claw", "slam", "pounce", "sweep"]  ## 哪些招能打坏它
var visual: Node3D
var body: StaticBody3D
var light: Light3D                ## 灯：碎了就灭
var rubble_shapes := []           ## 拱门：倒塌后留下的碎石堆碰撞 [Vector3 尺寸, Vector3 位置]
var is_broken := false
var player_breakable := false     ## 主角的攻击 / 翻滚也能打碎（陶罐）
var shard_color := Color(0.55, 0.56, 0.55)  ## 灯 / 陶罐碎掉时碎块的颜色
var shard_size := 0.25
var shard_count := 6
var _wobble := 0.0
var canopy := 2.0                 ## 树冠半径（米），摆放时量出来
# 被推弯：Boss / 玩家挤进树冠时，树往反方向弯，走开后带阻尼弹回来
const BEND_STIFF := 28.0
const BEND_DAMP := 5.5
var _bend := Vector2.ZERO          # 当前弯曲（绕 x / z 轴的角度）
var _bend_vel := Vector2.ZERO
var _bend_target := Vector2.ZERO
var _base_rot := Vector3.ZERO      # 模型本来的朝向 / 倾斜（倾斜孤树）
var _brush_cd := 0.0
var fade_target := 0.0            ## 镜头被挡住时由 camera_rig 设成 > 0：树变半透明
var _fade := 0.0
var _fade_meshes: Array = []


func _ready() -> void:
	add_to_group("destructible")
	if visual:
		_base_rot = visual.rotation
	if kind == Kind.ARCH and not Engine.is_editor_hint():
		_rock_pool()  # 开场就把碎石准备好，打碎的那一下不卡


## 有东西挤进树冠：from_pos = 它的位置，body_r = 它的身体半径，max_angle = 最多弯多少（弧度）。
## 弯的角度 ≈ 把树冠推开「挤进来的深度」需要的角度（深度 / 树冠高度），所以挤得越深弯得越多
func push(from_pos: Vector3, body_r: float, max_angle: float) -> void:
	if is_broken or kind != Kind.TREE:
		return
	var d := Vector2(global_position.x - from_pos.x, global_position.z - from_pos.z)
	var dist := d.length()
	var overlap := body_r + canopy - dist
	if overlap <= 0.0 or dist < 0.001:
		return
	var ang := minf(atan(overlap / maxf(height * 0.6, 1.0)) * 2.0, max_angle)
	var away := d / dist * ang
	# 往 away 方向倒：绕 z 轴转 -away.x，绕 x 轴转 away.y
	var t := Vector2(away.y, -away.x)
	if t.length() > _bend_target.length():
		_bend_target = t


## 树：一根圆柱碰撞（只挡树干）
static func make_tree(visual_node: Node3D, trunk_radius: float, tree_height: float, tree_hp: float, small: bool) -> Destructible:
	var d := Destructible.new()
	d.kind = Kind.TREE
	d.hp = tree_hp
	d.radius = trunk_radius
	d.height = tree_height
	d.contact_breakable = small
	d.visual = visual_node
	d.add_child(visual_node)
	d.body = _static_body([[CylinderShape3D, Vector3(trunk_radius, 3.0, 0), Vector3(0, 1.5, 0)]])
	d.add_child(d.body)
	return d


## 灯：一个小圆柱碰撞，碎了灯光熄灭
static func make_lamp(visual_node: Node3D, lamp_light: Light3D, lamp_radius: float, lamp_height: float) -> Destructible:
	var d := Destructible.new()
	d.kind = Kind.LAMP
	d.hp = 1.0
	d.radius = lamp_radius
	d.height = lamp_height
	d.contact_breakable = true
	d.visual = visual_node
	d.add_child(visual_node)
	d.light = lamp_light
	if lamp_light:
		d.add_child(lamp_light)
	d.body = _static_body([[CylinderShape3D, Vector3(lamp_radius, lamp_height, 0), Vector3(0, lamp_height * 0.5, 0)]])
	d.add_child(d.body)
	return d


## 拱门：几个简化的盒子碰撞（不用 194 万面的原网格）；只有重招（重劈 / 扑击）能打坏
static func make_arch(visual_node: Node3D, shapes: Array, rubble: Array, arch_hp: float, arch_radius: float) -> Destructible:
	var d := Destructible.new()
	d.kind = Kind.ARCH
	d.hp = arch_hp
	d.radius = arch_radius
	d.height = 7.0
	d.damaged_by = ["slam", "pounce", "claw"]
	d.visual = visual_node
	d.add_child(visual_node)
	d.rubble_shapes = rubble
	d.body = _static_body(shapes)
	d.add_child(d.body)
	return d


## 通用：shapes = [[形状类型, 尺寸, 位置], ...]（Box 用 size；Cylinder 用 (半径, 高, -)）
static func _static_body(shapes: Array) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	for s in shapes:
		var cs := CollisionShape3D.new()
		if s[0] == BoxShape3D:
			var b := BoxShape3D.new()
			b.size = s[1]
			cs.shape = b
		else:
			var c := CylinderShape3D.new()
			c.radius = s[1].x
			c.height = s[1].y
			cs.shape = c
		cs.position = s[2]
		sb.add_child(cs)
	return sb


## Boss 的身体挤进树冠：树抖一下、掉一团雪（小树直接撞断）；每棵树 0.8 秒最多一次
func brush(from_pos: Vector3) -> void:
	if is_broken or kind != Kind.TREE or _brush_cd > 0.0:
		return
	if contact_breakable:
		hit(999.0, from_pos, "contact")
		return
	_brush_cd = 0.8
	_wobble = 1.0
	_dust(global_position + Vector3.UP * height * 0.6, 1.2)


## 被 Boss 打到。attack = 招式名（claw / slam / pounce / sweep / contact）
func hit(dmg: float, from_pos: Vector3, attack: String) -> void:
	if is_broken:
		return
	if attack == "contact":
		if not contact_breakable:
			return
		hp = 0.0
	elif attack == "player":
		if not player_breakable:
			return
		hp = 0.0
	elif not attack in damaged_by:
		return
	else:
		hp -= 2.0 if attack in ["slam", "pounce"] else 1.0
	_wobble = 1.0
	if hp <= 0.0:
		_break(from_pos)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_brush_cd = maxf(0.0, _brush_cd - delta)
	if kind == Kind.TREE and not is_broken and visual:
		# 弹簧：朝目标弯，没人推了就弹回来（会稍微晃过头一点）
		var acc := (_bend_target - _bend) * BEND_STIFF - _bend_vel * BEND_DAMP
		_bend_vel += acc * delta
		_bend += _bend_vel * delta
		_bend_target = Vector2.ZERO  # 每帧由 Boss / 玩家重新设
		var w := _wobble
		visual.rotation = _base_rot + Vector3(_bend.x + sin(w * 30.0) * 0.03 * w, 0.0, _bend.y + cos(w * 26.0) * 0.03 * w)
	if not is_equal_approx(_fade, fade_target) and visual:
		_fade = move_toward(_fade, fade_target, delta * 3.0)
		if _fade_meshes.is_empty():
			_fade_meshes = visual.find_children("*", "GeometryInstance3D", true, false)
		for g in _fade_meshes:
			g.transparency = _fade
	fade_target = 0.0  # 镜头每帧重新设，不设就慢慢恢复
	if _wobble > 0.0 and not is_broken:
		_wobble = maxf(0.0, _wobble - delta * 3.0)  # 被打一下抖一抖（叠加在弯曲上）


func _break(from_pos: Vector3) -> void:
	is_broken = true
	broken.emit()
	var away := global_position - from_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	_game_call("shake", [0.35 if kind == Kind.ARCH else 0.15])
	match kind:
		Kind.TREE:
			_topple(away)
		Kind.LAMP:
			_shatter(away, shard_count, shard_size, shard_color)
			if light:
				light.remove_from_group("lamp_light")  # 不再被昼夜循环调亮
				create_tween().tween_property(light, "light_energy", 0.0, 0.25)
		Kind.ARCH:
			_collapse(away)


## 树：以树根为轴往被打的反方向倒下，落地激起一团雪，倒下后不再挡路
func _topple(away: Vector3) -> void:
	var axis := Vector3.UP.cross(away).normalized()
	var hinge := Node3D.new()  # 绕树根转
	add_child(hinge)
	visual.reparent(hinge, true)
	var start := hinge.basis
	var tw := create_tween()
	tw.tween_method(func(a: float): hinge.basis = Basis(axis, a) * start, 0.0, PI * 0.47, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(a: float): hinge.basis = Basis(axis, a) * start, PI * 0.47, PI * 0.44, 0.18).set_trans(Tween.TRANS_SINE)  # 落地弹一下
	tw.tween_callback(func():
		_dust(global_position + away * height * 0.6, 1.6)
		_game_call("shake", [0.2]))
	body.collision_layer = 0  # 倒下的树不再挡路（太长会把场地切断）


## 灯：碎成几块，带物理飞出去，几秒后消失
func _shatter(away: Vector3, pieces: int, size: float, color: Color) -> void:
	visual.visible = false
	body.collision_layer = 0
	_dust(global_position + Vector3.UP * 0.8, 0.8)
	var mat: StandardMaterial3D = _stone().duplicate()
	mat.albedo_color = color
	for i in pieces:
		_chunk(global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, 1.4), randf_range(-0.3, 0.3)),
			Vector3.ONE * size * randf_range(0.7, 1.3), mat, (away + Vector3(randf_range(-0.6, 0.6), randf_range(0.6, 1.2), randf_range(-0.6, 0.6))) * 3.0, 6.0)


## 拱门：上半截塌下来变成一堆碎石（带物理），原地留一个有碰撞的碎石堆
func _collapse(away: Vector3) -> void:
	visual.visible = false
	body.collision_layer = 0
	var use_rocks := not _rock_pool().is_empty()
	var mat := _stone()
	for i in 22:
		# 起点高于碎石堆（碎石堆的碰撞最高 ~1.4 米，碎块生成在里面会被弹飞）
		var p := global_position + global_basis * Vector3(randf_range(-4.5, 4.5), randf_range(2.6, 6.5), randf_range(-1.0, 1.0))
		var imp := away * randf_range(0.5, 2.0) + Vector3(randf_range(-1, 1), randf_range(0, 2), randf_range(-1, 1))
		if use_rocks:
			# 8 块大的落地后留下（带碰撞，人和 Boss 能迈上去），其余小块几秒后缩小消失
			var big := i < 8
			_rock_chunk(p, randf_range(0.9, 1.5) if big else randf_range(0.35, 0.8), imp, 0.0 if big else randf_range(5.0, 8.0))
		else:
			_chunk(p, Vector3(randf_range(0.6, 1.4), randf_range(0.4, 0.9), randf_range(0.5, 1.1)), mat, imp, 0.0)
	for i in 3:
		_dust(global_position + global_basis * Vector3(randf_range(-4, 4), 1.0, 0), 2.5)
	# 留下的碎石堆（还挡路）
	var shapes := rubble_shapes if not rubble_shapes.is_empty() else [[BoxShape3D, Vector3(9.0, 1.2, 2.4), Vector3(0, 0.6, 0)]]
	var pile := _static_body(shapes)
	pile.collision_layer = RUBBLE_LAYER
	add_child(pile)
	if use_rocks:
		for s in shapes:  # 每块碰撞盒里堆几块石头：大的垫底，小的堆在上面
			var size: Vector3 = s[1]
			var n := clampi(int(size.x * size.z / 1.2), 3, 7)
			for j in n:
				var big := j < 2
				var d := minf(size.x, size.z) * (0.9 if big else randf_range(0.45, 0.7))
				var rock := Node3D.new()  # 包一层：石头网格的顶点不在自己原点上，居中靠的是 MeshInstance 自己的变换
				rock.add_child(_rock_node(d)[0])
				rock.position = s[2] + Vector3(randf_range(-0.35, 0.35) * size.x, (-0.5 + (0.3 if big else randf_range(0.4, 0.75))) * size.y, randf_range(-0.35, 0.35) * size.z)
				rock.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
				rock.get_child(0).material_overlay = ArenaBuilder.snow_cap()
				add_child(rock)
		return
	var boulder: PackedScene = load("res://assets/env/models/boulder_01/boulder_01.gltf")
	for s in shapes:  # 每块碰撞上堆一块真实的扫描石头（大小对上碰撞盒）
		var rock: Node3D = boulder.instantiate()
		rock.position = s[2] - Vector3(0, s[1].y * 0.5, 0)
		rock.rotation.y = randf() * TAU
		rock.scale = Vector3(s[1].x / 1.27, s[1].y / 1.0, s[1].z / 1.83) * 1.1  # boulder_01 原大小 1.27 × 1.0 × 1.83
		for mi in rock.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = ArenaBuilder.snow_cap()
		add_child(rock)


## 拱门碎块：一块 70_stylized_rocks 的石头，凸包碰撞。
## life = 0：落地停稳后冻结、留在原地并开始挡主角（RUBBLE_LAYER；主角能迈上小块）；life > 0：到时间缩小消失
func _rock_chunk(pos: Vector3, size: float, impulse: Vector3, life: float) -> void:
	var made := _rock_node(size)
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = size * size * size * 12.0
	rb.linear_damp = 0.4
	rb.angular_damp = 2.0  # 石头落地后别一直滚
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = made[1]
	cs.shape = shape
	rb.add_child(cs)
	rb.add_child(made[0])
	get_tree().current_scene.add_child(rb)
	rb.global_position = pos
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	# 直接给初速度：刚加进场景的刚体用 apply_*_impulse 时物理服务器还没拿到 mass（按 1 算），大石头会被打飞几十米
	rb.linear_velocity = impulse
	rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	var fade := func():
		var tw := rb.create_tween()
		tw.tween_property(made[0], "scale", made[0].scale * 0.01, 0.8)
		tw.tween_callback(rb.queue_free)
	if life > 0.0:
		_timer(rb, life).timeout.connect(fade)
	else:
		var origin := global_position
		var t := _timer(rb, 3.0)
		var tries := [0]
		t.timeout.connect(func():
			# 落地停稳、离拱门不远的才留下；飞远了、或者 7 秒还没停的缩小消失（不会冻在半空）
			if rb.global_position.distance_to(origin) > 12.0:
				fade.call()
				return
			if rb.linear_velocity.length() > 0.4 and tries[0] < 4:
				tries[0] += 1
				t.start(1.0)
				return
			if rb.linear_velocity.length() > 0.4:
				fade.call()
				return
			rb.freeze = true
			rb.collision_layer = RUBBLE_LAYER)


## 一块带物理的碎块；life > 0 就几秒后消失，否则落地后冻结留在原地
func _chunk(pos: Vector3, size: Vector3, mat: Material, impulse: Vector3, life: float) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 0   # 碎块只和地面碰撞，不挡人
	rb.collision_mask = 1
	rb.mass = size.x * size.y * size.z * 20.0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	rb.add_child(mi)
	get_tree().current_scene.add_child(rb)
	rb.global_position = pos
	rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	rb.apply_central_impulse(impulse * rb.mass)
	rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * rb.mass)
	# 计时器挂在碎块自己身上：重开场景时跟着一起被释放
	var timer := _timer(rb, life if life > 0.0 else 5.0)
	if life > 0.0:
		timer.timeout.connect(rb.queue_free)
	else:
		timer.timeout.connect(rb.set.bind("freeze", true))


## 一团雪 / 灰尘
## 方案 B（阴雨泥地）：灰尘改成受光照的泥灰色，夜里不会是一团发亮的白雪。a = 0 时用原来的雪
static var dust_override := Color(0, 0, 0, 0)


func _dust(pos: Vector3, size: float) -> void:
	var dc: Color = dust_override if dust_override.a > 0.0 else DUST_COLOR
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.6
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.5
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0 * size
	pm.gravity = Vector3(0, -1.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, dc)
	ramp.set_color(1, Color(dc, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.6 * size
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if dust_override.a > 0.0 else BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _puff()
	q.material = qm
	p.draw_pass_1 = q
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	_timer(p, 3.0).timeout.connect(p.queue_free)


static func _timer(owner_node: Node, seconds: float) -> Timer:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = seconds
	t.autostart = true
	owner_node.add_child(t)
	return t


func _game_call(method: String, args: Array) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g:
		g.callv(method, args)
