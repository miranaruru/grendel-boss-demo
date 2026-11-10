extends Node
## 方案 B 的昼夜：开场是阴雨的白天（亮一些），CYCLE 秒内慢慢暗成夜里。
## 天越暗，暖光（石灯笼、残烛、崖顶山神庙）越亮、越显眼。T 键：往后跳 1/4。
## 二阶段 rage 0 → 1：主光束变暗变红，雾带一点血色（lair_builder.phase2 里 tween）。

const CYCLE := 300.0  # 从白天到夜里用几秒（一场战斗大概 3~5 分钟）

var t := 0.0
var rage := 0.0
var env: Environment
var sky_mat: ProceduralSkyMaterial
var overcast: DirectionalLight3D
var shaft: SpotLight3D
var gap_lights: Array = []
var warm: Array = []  # [灯, 白天的亮度]
var lanterns: Array = []  # [灯, 夜里的亮度, 火苗材质, 光晕材质, Destructible, 火苗节点]：白天灭，天黑时一盏盏点起来
var _t_down := false


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	t = minf(t + delta / CYCLE, 1.0)
	var down := Input.is_key_pressed(KEY_T)
	if down and not _t_down:
		t = minf(t + 0.25, 1.0)
	_t_down = down
	_apply()


func _apply() -> void:
	var k := smoothstep(0.0, 1.0, t)
	if overcast:
		overcast.light_energy = lerpf(0.95, 0.1, k)
		overcast.light_color = Color(0.86, 0.88, 0.92).lerp(Color(0.48, 0.56, 0.78), k)
	if env:
		env.ambient_light_energy = lerpf(0.6, 0.16, k)
		env.ambient_light_color = Color(0.52, 0.55, 0.6).lerp(Color(0.28, 0.33, 0.45), k)
		var fog := Color(0.40, 0.42, 0.45).lerp(Color(0.06, 0.07, 0.095), k)
		env.fog_light_color = fog.lerp(Color(0.22, 0.08, 0.07), rage * 0.5)
		env.volumetric_fog_albedo = Color(0.85, 0.86, 0.9).lerp(Color(0.6, 0.65, 0.75), k)
		env.tonemap_exposure = lerpf(1.0, 1.2, k)
	if sky_mat:
		sky_mat.sky_top_color = Color(0.36, 0.38, 0.41).lerp(Color(0.03, 0.035, 0.05), k)
		var hz := Color(0.5, 0.52, 0.55).lerp(Color(0.07, 0.08, 0.1), k)
		sky_mat.sky_horizon_color = hz
		sky_mat.ground_horizon_color = hz
	if shaft:
		var sc := Color(0.86, 0.9, 0.98).lerp(Color(0.55, 0.66, 0.95), k)  # 白天的天光 → 夜里的月光
		shaft.light_color = sc.lerp(Color(0.95, 0.4, 0.3), rage * 0.8)
		shaft.light_energy = lerpf(9.0, 6.0, k) * lerpf(1.0, 0.6, rage)
	for g in gap_lights:
		if is_instance_valid(g):
			g.light_energy = lerpf(3.5, 1.8, k)
	for w in warm:
		if is_instance_valid(w[0]):
			w[0].light_energy = w[1] * lerpf(0.55, 1.5, k)
	for i in lanterns.size():
		var l: Array = lanterns[i]
		# 傍晚（t≈0.45）开始，每盏错开一点点亮
		var on := smoothstep(0.45 + i * 0.03, 0.53 + i * 0.03, t)
		if not is_instance_valid(l[0]):
			continue
		if not is_instance_valid(l[4]) or l[4].is_broken:
			on = 0.0  # 灯笼被打碎了：不再点亮
		var ms := Time.get_ticks_msec() * 0.001
		var n1 := sin(ms * 11.0 + i * 2.1) * 0.5 + sin(ms * 17.3 + i * 0.7) * 0.3 + sin(ms * 29.0 + i) * 0.2
		var flick := 1.0 + 0.1 * n1 * on
		l[0].light_energy = l[1] * on * flick
		l[2].albedo_color.a = on
		l[3].albedo_color.a = on * 0.35 * flick
		if l.size() > 5 and is_instance_valid(l[5]):
			# 火苗跳动：忽高忽矮、轻轻左右晃
			l[5].scale = Vector3(1.0 - n1 * 0.06, 1.0 + n1 * 0.18, 1.0)
			l[5].rotation.z = sin(ms * 7.0 + i * 1.3) * 0.08
