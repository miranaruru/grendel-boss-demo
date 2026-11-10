extends Node3D
## 打击特效：火花、闪光、地面冲击环、裂地、尘土、爪痕、落雷、灰烬、屏幕边缘泛色。
## 全部代码生成，不用外部贴图。粒子节点开局就建好放进池子里轮流用（打斗中途新建粒子会编译着色器 → 卡一下）。
## 不加任何碰撞体。其它脚本通过 get_tree().get_first_node_in_group("fx") 调用。

const ArenaBuilder = preload("res://scripts/arena_builder.gd")
const POOL := 4        # 每种粒子几个轮流用（同一时刻最多叠几团）
const DECAL_POOL := 6

var _pools := {}       # 名字 → [GPUParticles3D…]
var _pool_i := {}
var _decals: Array[Decal] = []
var _decal_i := 0
var _tex := {}
var _vignette: ColorRect
var _vig_color := Color(0, 0, 0, 0)
var _vig_t := 0.0
var _vig_dur := 1.0
var _vig_hold := Color(0, 0, 0, 0)  # 持续的一层（慢动作时发暗），跟随真实时间


func _ready() -> void:
	add_to_group("fx")
	_make_textures()
	_make_pool("spark", _spark_particles)
	_make_pool("gash", _gash_particles)
	_make_pool("ember_spray", _ember_spray_particles)
	_make_pool("blood", _blood_particles)
	_make_pool("dust", _dust_particles)
	_make_pool("kick", _kick_particles, 10)
	_make_pool("ember", _ember_particles, 1)
	_make_pool("wisp", _wisp_particles)
	_make_pool("smoke", _smoke_particles, 2)
	_make_pool("dirt", _dirt_particles, 2)
	for i in PEBBLE_KINDS:
		_make_pool("pebble%d" % i, _pebble_particles.bind(i), 2)
	# 小石子落地会弹一下停在地上：GPU 粒子碰撞用的高度图（只在 GPU 上算，不是物理碰撞体；只在挪动时重画一次）
	var hf := GPUParticlesCollisionHeightField3D.new()
	hf.size = Vector3(60, 20, 60)
	hf.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	hf.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	add_child(hf)
	hf.global_position = Vector3(0, 2, 0)
	for i in DECAL_POOL:
		var d := Decal.new()
		d.cull_mask = ArenaBuilder.GROUND_LAYER
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.visible = false
		add_child(d)
		_decals.append(d)
	var layer := CanvasLayer.new()
	layer.layer = 0  # 在 HUD 下面
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.0);
void fragment() {
	float d = length((UV - 0.5) * vec2(1.6, 1.0));
	COLOR = vec4(tint.rgb, tint.a * smoothstep(0.35, 0.95, d));
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_vignette.material = sm
	layer.add_child(_vignette)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)  # 屏幕泛色按真实时间淡出，不受顿帧 / 慢动作影响
	_vig_t = maxf(0.0, _vig_t - real)
	var c := _vig_color
	c.a *= _vig_t / _vig_dur
	if _vig_hold.a > c.a:
		c = _vig_hold
	(_vignette.material as ShaderMaterial).set_shader_parameter("tint", c)
	_vignette.visible = c.a > 0.01


# ================= 对外接口 =================

## 金属火花：pos 位置，dir 大致朝向（喷向哪边），size 1 = 普通一刀
func sparks(pos: Vector3, dir: Vector3, color: Color, size: float = 1.0) -> void:
	var p := _take("spark")
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	pm.initial_velocity_min = 4.0 * size
	pm.initial_velocity_max = 9.0 * size
	pm.color = color
	p.amount_ratio = clampf(0.35 * size, 0.2, 1.0)
	_fire(p, pos)
	flash(pos, color, 0.5 + 0.35 * size)


## 主角砍中：暗红血花 + 几颗橙红余烬（呼应 Boss 手臂上发光的裂纹），顺着挥剑方向扇形甩出去。
## Boss 是血肉 / 枯木不是铁，金色火花看着像打铁。size 1 = 普通一刀，反击约 2
## dir = 挥剑方向，plane_n = 挥剑平面的法线：扇面落在挥剑平面里
func slash_spray(pos: Vector3, dir: Vector3, size: float = 1.0, plane_n: Vector3 = Vector3.ZERO) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var n := plane_n - d * plane_n.dot(d)
	if n.length() < 0.01:  # 没给平面：随便取一个和 d 垂直的
		n = d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.FORWARD)
	n = n.normalized()
	# 发射器局部坐标：X = 挥剑方向，Y = 平面法线。flatness 把 Y 方向的散开压扁 → 扇面落在挥剑平面里
	var b := Basis(d, n, d.cross(n)).orthonormalized()
	for key in ["gash", "ember_spray"]:
		var p := _take(key)
		var pm := p.process_material as ParticleProcessMaterial
		p.global_basis = b
		pm.direction = Vector3.RIGHT
		var fast := 1.3 if key == "ember_spray" else 1.0  # 余烬飞得更远
		pm.initial_velocity_min = 5.0 * size * fast
		pm.initial_velocity_max = 12.0 * size * fast
		p.amount_ratio = clampf(0.55 * size, 0.45, 1.0)
		_fire(p, pos)
	flash(pos, Color(0.9, 0.3, 0.12, 0.8), 0.5 + 0.35 * size, _tex["k_flare"])


## 一闪：发光的小球，瞬间放大后消失
func flash(pos: Vector3, color: Color, size: float = 1.0, tex: Texture2D = null) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	mi.material_override = _additive(color, tex if tex else _tex["glow"], true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween()
	tw.set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.2, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.16)
	tw.chain().tween_callback(mi.queue_free)


## 受击血雾（暗红）
func blood(pos: Vector3, dir: Vector3, size: float = 1.0) -> void:
	var p := _take("blood")
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = (dir.normalized() + Vector3.UP * 0.5).normalized()
	pm.initial_velocity_max = 4.0 * size
	_fire(p, pos)


## 地上扩散的冲击环（投射到地面，石台高低不平也贴地）
func ring(pos: Vector3, radius: float, color: Color, dur: float = 0.45) -> void:
	var d := _take_decal()
	d.texture_albedo = _tex["ring"]
	d.texture_emission = _tex["ring_glow"]
	d.emission_energy = 2.0
	d.modulate = color
	_place_decal(d, pos, radius * 0.25)
	var tw := d.create_tween()
	d.set_meta("tween", tw)
	tw.set_parallel()
	tw.tween_property(d, "size", Vector3(radius * 2.0, 6.0, radius * 2.0), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(d, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(d.set.bind("visible", false))


## 裂地：一圈放射状裂纹，停一会儿再淡掉
## big = 重劈：更宽的裂缝 + 中间一个坑，裂缝里的红光更亮、留得更久
func cracks(pos: Vector3, radius: float, big: bool = false) -> void:
	var d := _take_decal()
	d.texture_albedo = _tex["crack_big" if big else "crack"]
	d.texture_emission = _tex["crack_big_glow" if big else "crack_glow"]
	d.emission_energy = 4.0 if big else 1.2
	d.modulate = Color(1, 1, 1, 1)
	d.rotation.y = randf() * TAU
	_place_decal(d, pos, radius)
	var tw := d.create_tween()
	d.set_meta("tween", tw)
	tw.tween_property(d, "emission_energy", 0.0, 1.5 if big else 0.6).set_ease(Tween.EASE_IN)
	tw.tween_interval(2.5 if big else 1.4)
	tw.tween_property(d, "modulate:a", 0.0, 1.0)
	tw.tween_callback(d.set.bind("visible", false))


## 贴地一圈往外卷的尘土
func dust(pos: Vector3, radius: float, amount: float = 1.0) -> void:
	var p := _take("dust")
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_ring_radius = radius * 0.6
	pm.emission_ring_inner_radius = radius * 0.4
	pm.initial_velocity_min = radius * 0.8
	pm.initial_velocity_max = radius * 1.8
	p.amount_ratio = clampf(amount, 0.1, 1.0)
	_fire(p, pos + Vector3.UP * 0.15)


## 爪痕 / 刀弧：一道弯月形的光，fwd 朝向，tilt 绕前进方向倾斜（弧度）
func slash_arc(pos: Vector3, fwd: Vector3, radius: float, color: Color, tilt: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_mesh()
	mi.material_override = _additive(color, null, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	mi.global_transform = Transform3D(Basis.looking_at(f), pos) * Transform3D(Basis(Vector3.FORWARD, tilt), Vector3.ZERO)
	mi.scale = Vector3.ONE * radius * 0.7
	var tw := mi.create_tween()
	tw.set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


## 落雷：天上劈下一道光柱
func lightning(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.3
	cyl.height = 30.0
	cyl.radial_segments = 8
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = _additive(Color(0.75, 0.88, 1.0, 1.0), null, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3.UP * 15.0
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.85, 1.0)
	light.light_energy = 6.0
	light.omni_range = 10.0
	light.shadow_enabled = false
	mi.add_child(light)
	light.position = Vector3.DOWN * 13.0
	var tw := mi.create_tween()
	tw.set_parallel()
	tw.tween_property(mi, "scale:x", 0.1, 0.25)
	tw.tween_property(mi, "scale:z", 0.1, 0.25)
	tw.tween_property(mi.material_override, "albedo_color:a", 0.0, 0.25)
	tw.tween_property(light, "light_energy", 0.0, 0.25)
	tw.chain().tween_callback(mi.queue_free)


## 脚下扬起一小团尘土（翻滚），dir = 往哪边飘，size 1 = 蹬地那一下
func kick(pos: Vector3, dir: Vector3, size: float = 1.0) -> void:
	var p := _take("kick")
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = (Vector3(dir.x, 0.0, dir.z).normalized() + Vector3.UP * 0.6).normalized()
	pm.initial_velocity_max = 2.2 * size
	p.amount_ratio = clampf(size, 0.3, 1.0)
	_fire(p, pos + Vector3.UP * 0.1)


## 震晕：三颗黄色五角星绕头转（各自自转、上下浮动）+ 头顶一圈旋涡 + 零星闪光，dur 秒
func dizzy(target: Node3D, dur: float, height: float = 2.0) -> void:
	var pivot := Node3D.new()
	target.add_child(pivot)
	pivot.position = Vector3.UP * height
	pivot.rotation.x = 0.25  # 轨道稍微斜一点，从镜头后方也看得出在绕圈
	var star_mat := _billboard_mat(Color(1.0, 0.85, 0.2, 1.0), _tex["k_star"], false)
	var stars: Array[MeshInstance3D] = []
	for i in 3:
		var mi := _quad(0.42, star_mat)
		pivot.add_child(mi)
		stars.append(mi)
	# 旋涡：平躺在头顶慢慢转
	var swirl := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 1.3
	swirl.mesh = plane
	var swirl_mat := _additive(Color(1.0, 0.9, 0.55, 0.55), _tex["k_twirl"], false)
	swirl.material_override = swirl_mat
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(swirl)
	var sparkle_mat := _additive(Color(1.0, 0.95, 0.6, 1.0), _tex["k_sparkle"], true)
	var tw := pivot.create_tween()
	tw.tween_method(func(k: float):
		var a0 := k * dur * 7.0  # 一秒绕一圈多
		for i in stars.size():
			var a := a0 + TAU * i / stars.size()
			stars[i].position = Vector3(cos(a) * 0.55, sin(a0 * 1.7 + i * 2.0) * 0.08, sin(a) * 0.55)
		swirl.rotation.y = -a0 * 0.8
		var fade := clampf((1.0 - k) * dur / 0.25, 0.0, 1.0)  # 最后 0.25 秒淡掉
		star_mat.albedo_color.a = fade
		swirl_mat.albedo_color.a = 0.55 * fade
		if randf() < 0.25 and fade > 0.5:  # 零星闪一下
			_sparkle(pivot, sparkle_mat)
	, 0.0, 1.0, dur)
	tw.tween_callback(pivot.queue_free)


func _sparkle(parent: Node3D, mat: Material) -> void:
	var mi := _quad(0.22, mat)
	parent.add_child(mi)
	var a := randf() * TAU
	mi.position = Vector3(cos(a) * 0.5, randf_range(-0.1, 0.2), sin(a) * 0.5)
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.1)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.15)
	tw.tween_callback(mi.queue_free)


func _quad(size: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 重劈砸地：落点一团闪光 + 翻滚的烟尘 + 飞溅的碎土
func slam_burst(pos: Vector3, radius: float) -> void:
	var ground := Vector3(pos.x, ArenaBuilder.ground_height(pos.x, pos.z), pos.z)
	flash(ground + Vector3.UP * 0.6, Color(1.0, 0.75, 0.45, 0.9), radius * 1.6, _tex["k_flare"])
	var s := _take("smoke")
	(s.process_material as ParticleProcessMaterial).emission_ring_radius = radius * 0.7
	(s.process_material as ParticleProcessMaterial).emission_ring_inner_radius = radius * 0.3
	_fire(s, ground + Vector3.UP * 0.3)
	_fire(_take("dirt"), ground + Vector3.UP * 0.2)
	for i in PEBBLE_KINDS:
		_fire(_take("pebble%d" % i), ground + Vector3.UP * 0.3)


## 一缕蓝色残影烟（完美闪避 / 瞬影斩的起点和终点）
func wisp(pos: Vector3) -> void:
	_fire(_take("wisp"), pos + Vector3.UP * 0.9)


## Boss 死亡：从身体里往上飘灰烬火星，持续一阵
func ashes(pos: Vector3, height: float, dur: float = 3.5) -> void:
	var p := _take("ember")
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_box_extents = Vector3(1.6, height * 0.4, 1.6)
	p.one_shot = false
	_fire(p, pos + Vector3.UP * height * 0.45)
	get_tree().create_timer(dur).timeout.connect(func(): p.emitting = false)


## 屏幕边缘泛色（受击泛红等），dur 秒内淡掉
func vignette(color: Color, dur: float = 0.5) -> void:
	if color.a < _vig_color.a * _vig_t / _vig_dur:
		return
	_vig_color = color
	_vig_t = dur
	_vig_dur = dur


## 持续的边缘发暗（慢动作期间），a = 0 关掉
func vignette_hold(color: Color) -> void:
	_vig_hold = color


# ================= 池子 =================

func _make_pool(key: String, maker: Callable, n: int = POOL) -> void:
	var arr: Array[GPUParticles3D] = []
	for i in n:
		var p: GPUParticles3D = maker.call()
		p.one_shot = true
		p.emitting = false
		p.local_coords = false
		p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 12, 16))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		p.global_position = Vector3(0, -50, 0)
		p.emitting = true  # 开局在地下先放一次：着色器提前编译好
		arr.append(p)
	_pools[key] = arr
	_pool_i[key] = 0


func _take(key: String) -> GPUParticles3D:
	var arr: Array = _pools[key]
	var i: int = _pool_i[key]
	_pool_i[key] = (i + 1) % arr.size()
	return arr[i]


func _fire(p: GPUParticles3D, pos: Vector3) -> void:
	p.global_position = pos
	p.restart()
	p.emitting = true


func _take_decal() -> Decal:
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	var old: Tween = d.get_meta("tween") if d.has_meta("tween") else null
	if old and old.is_valid():
		old.kill()  # 池子转了一圈回来，上一次的淡出还没放完
	d.rotation.y = 0.0
	return d


func _place_decal(d: Decal, pos: Vector3, radius: float) -> void:
	d.visible = true
	d.global_position = Vector3(pos.x, ArenaBuilder.ground_height(pos.x, pos.z), pos.z)
	d.size = Vector3(radius * 2.0, 6.0, radius * 2.0)


# ================= 粒子定义 =================

func _quad_draw(size: Vector2, tex: Texture2D, mode: BaseMaterial3D.BillboardMode, additive: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = mode
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.vertex_color_is_srgb = true  # 不开的话粒子颜色按线性算，深褐色会被提亮成浅灰（像水蒸气）
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.disable_fog = true
	m.no_depth_test = false
	q.material = m
	return q


func _fade_ramp(c0: Color, c1: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


func _spark_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.35
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.spread = 55.0
	pm.gravity = Vector3(0, -14, 0)
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _fade_ramp(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2(0.035, 0.35), _tex["glow"], BaseMaterial3D.BILLBOARD_DISABLED, true)
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY  # 面朝镜头、沿飞行方向拉长（材质上的 FIXED_Y 公告板会把火花全立成竖线）
	return p


## 扇形喷射的共同设置：扇面 ±40°、压平；沿飞行方向拉长、面朝镜头；不被 Boss 身体挡住
func _fan_particles(amount: int, life: float, size: Vector2, additive: bool, ramp: Gradient, gravity: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.spread = 40.0  # 扇形张角（±40°）
	pm.flatness = 0.85  # 几乎压成一个平面：扇面
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.scale_curve = _curve_tex(1.0, 0.3)  # 越飞越细
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var q := _quad_draw(size, _tex["glow"] if additive else _tex["puff"], BaseMaterial3D.BILLBOARD_DISABLED, additive)
	(q.material as StandardMaterial3D).no_depth_test = true  # 从 Boss 身体表面喷出，别被身体挡住
	p.draw_pass_1 = q
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY  # 面朝镜头、沿飞行方向拉长（材质上的 FIXED_Y 公告板会立成竖线）
	return p


## 血花：暗红的血滴甩出去、往下坠
func _gash_particles() -> GPUParticles3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.72, 0.07, 0.05, 1.0), Color(0.48, 0.03, 0.02, 0.95), Color(0.28, 0.0, 0.0, 0.0)])
	return _fan_particles(56, 0.65, Vector2(0.13, 0.65), false, g, -14.0)


## 余烬：少量橙红火星，飞得远一点
func _ember_spray_particles() -> GPUParticles3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.55, 0.2, 1.0), Color(0.95, 0.3, 0.08, 0.9), Color(0.5, 0.08, 0.02, 0.0)])
	return _fan_particles(18, 0.55, Vector2(0.05, 0.5), true, g, -6.0)


func _blood_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.6
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.spread = 40.0
	pm.initial_velocity_min = 1.5
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = _fade_ramp(Color(0.55, 0.03, 0.02, 0.95), Color(0.25, 0.0, 0.0, 0.0))
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 0.22, _tex["puff"], BaseMaterial3D.BILLBOARD_PARTICLES, false)
	return p


func _dust_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.4
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.1
	pm.emission_ring_radius = 1.0
	pm.emission_ring_inner_radius = 0.6
	pm.particle_flag_disable_z = false
	pm.direction = Vector3(0, 0.08, 0)
	pm.spread = 10.0
	pm.radial_velocity_min = 2.0  # 从中心往外推
	pm.radial_velocity_max = 5.0
	pm.gravity = Vector3(0, -0.4, 0)  # 贴地卷，不往天上飘
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.scale_curve = _curve_tex(0.6, 1.4)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.color_ramp = _fade_ramp(Color(0.32, 0.27, 0.22, 0.45), Color(0.32, 0.27, 0.22, 0.0))  # 深褐色：浅灰在雾里像水蒸气
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 0.7, _tex["k_smoke"], BaseMaterial3D.BILLBOARD_PARTICLES, false)
	return p


func _kick_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 8
	p.lifetime = 0.9
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -0.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _curve_tex(0.4, 1.5)
	pm.color_ramp = _fade_ramp(Color(0.42, 0.37, 0.31, 0.75), Color(0.42, 0.37, 0.31, 0.0))
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 0.85, _tex["k_smoke"], BaseMaterial3D.BILLBOARD_PARTICLES, false)
	return p


func _ember_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 220
	p.lifetime = 2.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1, 2, 1)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.8, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.75, 0.35, 0.0), Color(1.0, 0.45, 0.15, 1.0), Color(0.3, 0.3, 0.3, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 0.22, _tex["glow"], BaseMaterial3D.BILLBOARD_PARTICLES, true)
	return p


## 重劈的烟尘：Kenney 烟团贴图，随机旋转、边长大边贴地往外卷。深褐色、偏透明（浅灰色在雾里像水蒸气）
func _smoke_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 1.6
	p.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.1
	pm.direction = Vector3(0, 0.1, 0)
	pm.spread = 10.0
	pm.radial_velocity_min = 3.0
	pm.radial_velocity_max = 6.0
	pm.gravity = Vector3(0, -0.3, 0)
	pm.damping_min = 2.5
	pm.damping_max = 4.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = 0.8
	pm.scale_max = 1.5
	pm.scale_curve = _curve_tex(0.5, 1.4)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(0.3, 0.25, 0.2, 0.0), Color(0.3, 0.25, 0.2, 0.5), Color(0.3, 0.26, 0.22, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 1.6, _tex["k_smoke"], BaseMaterial3D.BILLBOARD_PARTICLES, false)
	return p


const PEBBLE_KINDS := 3  # 用几种石头形状（每种一个粒子节点）
const PEBBLE_SIZE := 0.2  # 石子最长边（米），粒子再随机缩放 0.5~1.6

## 小石子：拱门碎石用的那包卡通石头（70_stylized_rocks），缩小做成粒子网格；往外崩、落地弹一下、躺一会儿再缩没
func _pebble_particles(kind: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 2.6
	p.explosiveness = 1.0
	p.collision_base_size = PEBBLE_SIZE * 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.5
	pm.gravity = Vector3(0, -22, 0)
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -500.0
	pm.angular_velocity_max = 500.0
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var c := Curve.new()  # 前 85% 正常大小，最后缩没（代替淡出：实心石头没法半透明）
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.85, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.25
	pm.collision_friction = 0.7
	p.process_material = pm
	p.draw_pass_1 = _pebble_mesh(kind)
	return p


func _pebble_mesh(kind: int) -> Mesh:
	var pool: Array = Destructible._rock_pool()
	if pool.is_empty():
		var box := BoxMesh.new()
		box.size = Vector3.ONE * PEBBLE_SIZE
		return box
	var r: Array = pool[(kind * 5) % pool.size()]
	var dims: Vector3 = r[2]
	var k := PEBBLE_SIZE / maxf(dims[dims.max_axis_index()], 0.01)
	var xf := Transform3D(r[1].basis.scaled(Vector3.ONE * k), r[1].origin * k)
	var st := SurfaceTool.new()
	st.append_from(r[0], 0, xf)
	var mesh := st.commit()
	if r[3].size() > 0 and r[3][0]:
		mesh.surface_set_material(0, r[3][0])
	return mesh


## 飞溅的碎土：Kenney 碎土贴图，往上崩再落下
func _dirt_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 1.1
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3.UP
	pm.spread = 45.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, -20, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -200.0
	pm.angular_velocity_max = 200.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = _fade_ramp(Color(0.3, 0.25, 0.2, 1.0), Color(0.3, 0.25, 0.2, 0.0))
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 1.0, _tex["k_dirt"], BaseMaterial3D.BILLBOARD_PARTICLES, false)
	return p


func _wisp_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.25, 0.8, 0.25)
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color_ramp = _fade_ramp(Color(0.45, 0.75, 1.0, 0.7), Color(0.3, 0.5, 1.0, 0.0))
	p.process_material = pm
	p.draw_pass_1 = _quad_draw(Vector2.ONE * 0.5, _tex["puff"], BaseMaterial3D.BILLBOARD_PARTICLES, true)
	return p


func _curve_tex(a: float, b: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = maxf(a, b)
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


# ================= 材质 / 网格 / 贴图 =================

func _additive(color: Color, tex: Texture2D, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.albedo_color = color
	m.vertex_color_use_as_albedo = tex == null  # 弧形网格用顶点色做两头渐隐
	if tex:
		m.albedo_texture = tex
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	return m


var _arc: ArrayMesh
## 弯月：半径 1 的 150° 圆弧带，中间宽两头尖，外沿亮内沿暗
func _arc_mesh() -> ArrayMesh:
	if _arc:
		return _arc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	var span := deg_to_rad(150.0)
	var verts := []
	for i in n + 1:
		var u := float(i) / n
		var a := -span * 0.5 + span * u
		var w := sin(u * PI) * 0.28  # 宽度
		var dir := Vector3(sin(a), 0.0, -cos(a))
		var fade := sin(u * PI)
		verts.append([dir * 1.0, dir * (1.0 - w), fade])
	for i in n:
		var a0: Array = verts[i]
		var a1: Array = verts[i + 1]
		var quad := [[a0[0], a0[2]], [a1[0], a1[2]], [a1[1], 0.0], [a0[0], a0[2]], [a1[1], 0.0], [a0[1], 0.0]]
		for v in quad:
			st.set_color(Color(1, 1, 1, v[1]))
			st.add_vertex(v[0])
	_arc = st.commit()
	return _arc


## 普通混合的公告板材质（不发光的图形，比如五角星）
func _billboard_mat(color: Color, tex: Texture2D, _unused: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.disable_fog = true
	m.albedo_color = color
	m.albedo_texture = tex
	m.no_depth_test = true  # 星星永远画在最上层，不被角色模型挡住
	m.render_priority = 1
	return m


const KENNEY_VFX := "res://assets/vfx/kenney/"  # Kenney Particle Pack（CC0），黑底灰度原图已转成白色 + 透明度


func _make_textures() -> void:
	for pair in [["k_smoke", "smoke_07"], ["k_dirt", "dirt_03"], ["k_star", "symbol_02"], ["k_twirl", "twirl_01"], ["k_sparkle", "star_07"], ["k_flare", "star_06"]]:
		_tex[pair[0]] = load(KENNEY_VFX + pair[1] + ".png")
	var n := 64
	var glow := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var puff := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var g := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			glow.set_pixel(x, y, Color(1, 1, 1, g))
			puff.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.4)))
	_tex["glow"] = ImageTexture.create_from_image(glow)
	_tex["puff"] = ImageTexture.create_from_image(puff)
	# 冲击环：细细一圈亮边
	var s := 256  # 环细，贴图要大一点，不然边缘有锯齿
	var ring := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var ring_g := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - 127.5, y - 127.5).length() / 127.5
			var a := smoothstep(0.86, 0.955, d) * (1.0 - smoothstep(0.955, 1.0, d))
			ring.set_pixel(x, y, Color(1, 1, 1, a))
			ring_g.set_pixel(x, y, Color(a, a, a, 1))
	_tex["ring"] = ImageTexture.create_from_image(ring)
	_tex["ring_glow"] = ImageTexture.create_from_image(ring_g)
	_crack_tex("crack", 7, 9, 4.0, 0.0)
	_crack_tex("crack_big", 11, 13, 9.0, 0.09)  # 重劈：裂缝更宽更多，中间砸出一个坑


## 裂纹：从中心往外的几条折线，越往外越细；裂缝里透暗红余光。pit = 中间坑的半径（占贴图宽度的比例）
func _crack_tex(key: String, seed_: int, arms: int, w0: float, pit: float) -> void:
	var cs := 256
	var crack := Image.create(cs, cs, false, Image.FORMAT_RGBA8)
	var crack_g := Image.create(cs, cs, false, Image.FORMAT_RGBA8)
	crack.fill(Color(0, 0, 0, 0))
	crack_g.fill(Color(0, 0, 0, 1))
	var c := Vector2(cs * 0.5, cs * 0.5)
	if pit > 0.0:
		var pr := cs * pit
		for y in range(int(c.y - pr), int(c.y + pr) + 1):
			for x in range(int(c.x - pr), int(c.x + pr) + 1):
				var f := 1.0 - Vector2(x, y).distance_to(c) / pr
				if f > 0.0:
					crack.set_pixel(x, y, Color(0.06, 0.05, 0.04, minf(1.0, f * 2.5) * 0.9))
					crack_g.set_pixel(x, y, Color(0.9 * f, 0.3 * f, 0.08 * f, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for k in arms:
		var ang := TAU * k / arms + rng.randf_range(-0.25, 0.25)
		var p := c
		var steps := rng.randi_range(8, 12)
		for i in steps:
			ang += rng.randf_range(-0.5, 0.5)
			var q := p + Vector2(cos(ang), sin(ang)) * cs * 0.045
			var width := lerpf(w0, 1.0, float(i) / steps)
			_line(crack, crack_g, p, q, width)
			if rng.randf() < 0.3:  # 分叉
				var b := ang + rng.randf_range(0.6, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
				_line(crack, crack_g, q, q + Vector2(cos(b), sin(b)) * cs * 0.06, width * 0.6)
			p = q
	_tex[key] = ImageTexture.create_from_image(crack)
	_tex[key + "_glow"] = ImageTexture.create_from_image(crack_g)


func _line(img: Image, glow: Image, a: Vector2, b: Vector2, w: float) -> void:
	var len := a.distance_to(b)
	for i in int(len) + 1:
		var c := a.lerp(b, i / maxf(len, 1.0))
		for dy in range(-int(w), int(w) + 1):
			for dx in range(-int(w), int(w) + 1):
				var x := int(c.x) + dx
				var y := int(c.y) + dy
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var f := 1.0 - Vector2(dx, dy).length() / (w + 0.5)
				if f <= 0.0:
					continue
				if img.get_pixel(x, y).a < f * 0.85:
					img.set_pixel(x, y, Color(0.08, 0.06, 0.05, f * 0.85))
					glow.set_pixel(x, y, Color(0.9 * f, 0.25 * f, 0.08 * f, 1))
