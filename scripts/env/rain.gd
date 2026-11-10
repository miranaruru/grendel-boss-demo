extends Node3D
## 阴雨：雨丝 + 地上溅起的小水花，都跟着镜头走（只在镜头周围下，省性能）。
## intensity 改雨的大小（0 = 停，1 = 正常）。

@export var intensity := 1.0:
	set(v):
		intensity = v
		if _rain:
			_rain.amount_ratio = clampf(v, 0.0, 1.0)
			_splash.amount_ratio = clampf(v, 0.0, 1.0)

const AREA := 26.0       # 雨丝盖住镜头周围多大一块（米）
const TOP := 14.0        # 从镜头上方多高开始下
const WIND := Vector3(0.9, 0.0, 0.4)

var _rain: GPUParticles3D
var _splash: GPUParticles3D


func _ready() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "RainStreaks"
	_rain.amount = 7000
	_rain.lifetime = 1.4
	_rain.preprocess = 1.4
	_rain.fixed_fps = 0
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-AREA, -TOP - 6.0, -AREA), Vector3(AREA * 2.0, TOP + 12.0, AREA * 2.0))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA, 0.5, AREA)
	pm.direction = (Vector3.DOWN * 14.0 + WIND).normalized()
	pm.spread = 2.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true  # 雨丝顺着速度方向拉长
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.72, 0.76, 0.82, 0.22)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.emission_enabled = true  # 一点点自发光：暗处也隐约看得见，光束里更亮
	m.emission = Color(0.35, 0.38, 0.42)
	m.emission_energy_multiplier = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 贴着镜头的雨丝会变成一条很粗的竖条：离镜头 0.8 米以内看不见，到 4 米渐显
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.8
	m.distance_fade_max_distance = 4.0
	q.material = m
	_rain.draw_pass_1 = q
	add_child(_rain)
	_rain.position.y = TOP

	_splash = GPUParticles3D.new()
	_splash.name = "RainSplash"
	_splash.amount = 600
	_splash.lifetime = 0.28
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-14, -2, -14), Vector3(28, 4, 28))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(13.0, 0.0, 13.0)
	sp.direction = Vector3.UP
	sp.spread = 35.0
	sp.initial_velocity_min = 0.8
	sp.initial_velocity_max = 1.6
	sp.gravity = Vector3(0, -9.8, 0)
	sp.scale_min = 0.5
	sp.scale_max = 1.0
	_splash.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.02, 0.035)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.6, 0.63, 0.68, 0.16)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sq.material = sm
	_splash.draw_pass_1 = sq
	add_child(_splash)
	_splash.position.y = 0.03


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	# 雨丝发射盒稍微往镜头前方挪，前景 / Boss 那边雨更密
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		fwd = fwd.normalized() * 6.0
	global_position = Vector3(c.x + fwd.x, 0.0, c.z + fwd.z)
	_rain.global_position = Vector3(c.x + fwd.x - WIND.x, c.y + TOP, c.z + fwd.z - WIND.z)
