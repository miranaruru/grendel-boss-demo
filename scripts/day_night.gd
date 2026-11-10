extends Node
## 昼夜：一天 = DAY_LENGTH_SEC 秒。时间 t ∈ [0, 1)：0 午夜、0.25 日出、0.5 正午、0.75 日落。
## 太阳和月亮是两盏 DirectionalLight，天空 / 雾 / 环境光颜色按时间从下面几组关键帧插值。
## 调试：按 T 把时间往后跳 3 小时。

const DAY_LENGTH_SEC := 240.0   # 一整天多少秒
const START_TIME := 0.35        # 开局时间（0.35 ≈ 上午 8 点）
const JUMP_HOURS := 3.0         # 按 T 跳多少小时

# 关键帧：时间 → 雾 / 背景色、环境光色、环境光强度
const KEYS := [
	[0.00, Color(0.05, 0.07, 0.11), Color(0.32, 0.38, 0.55), 0.45],  # 午夜：蓝黑，环境光偏蓝、不太暗（保证能看清打斗）
	[0.20, Color(0.07, 0.08, 0.12), Color(0.32, 0.38, 0.55), 0.45],
	[0.27, Color(0.42, 0.34, 0.32), Color(0.62, 0.52, 0.50), 0.50],  # 日出：灰粉
	[0.35, Color(0.36, 0.38, 0.41), Color(0.50, 0.53, 0.58), 0.55],  # 白天：灰
	[0.65, Color(0.36, 0.38, 0.41), Color(0.50, 0.53, 0.58), 0.55],
	[0.74, Color(0.45, 0.33, 0.28), Color(0.66, 0.50, 0.44), 0.50],  # 日落：昏黄
	[0.80, Color(0.07, 0.08, 0.12), Color(0.32, 0.38, 0.55), 0.45],
	[1.00, Color(0.05, 0.07, 0.11), Color(0.32, 0.38, 0.55), 0.45],
]

var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var time := START_TIME


func setup(environment: Environment, sun_light: DirectionalLight3D, moon_light: DirectionalLight3D) -> void:
	env = environment
	sun = sun_light
	moon = moon_light
	_apply()


func _process(delta: float) -> void:
	if env == null:
		return
	# 用真实时间走（不受顿帧 / 慢动作影响）
	time = fposmod(time + delta / maxf(Engine.time_scale, 0.01) / DAY_LENGTH_SEC, 1.0)
	if Input.is_action_just_pressed("time_jump"):
		time = fposmod(time + JUMP_HOURS / 24.0, 1.0)
		var g := get_tree().get_first_node_in_group("game")
		if g and g.hud:
			g.hud.show_msg(preload("res://scripts/loc.gd").t("时间：%02d:00") % int(time * 24.0), Color(0.8, 0.85, 1.0))
	_apply()


func is_night() -> bool:
	return sun.light_energy < 0.05


func _apply() -> void:
	# 太阳：从东边升起，正午最高 60°，西边落下；月亮在对面
	var h := sin((time - 0.25) * TAU)            # 太阳高度：-1 ~ 1
	var az := lerpf(-100.0, 100.0, fposmod(time - 0.25, 1.0))
	sun.rotation_degrees = Vector3(-maxf(h, 0.02) * 60.0, az, 0.0)
	moon.rotation_degrees = Vector3(-maxf(-h, 0.02) * 55.0, az + 180.0, 0.0)
	sun.light_energy = clampf(h * 3.0, 0.0, 1.0) * 0.8
	moon.light_energy = clampf(-h * 3.0, 0.0, 1.0) * 0.45
	sun.light_color = Color(1.0, 0.72, 0.55).lerp(Color(0.85, 0.87, 0.92), clampf(h * 2.5, 0.0, 1.0))  # 低角度偏暖
	sun.visible = sun.light_energy > 0.0
	moon.visible = moon.light_energy > 0.0

	var i := 0
	while i < KEYS.size() - 2 and time >= KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var f := clampf((time - a[0]) / maxf(0.0001, b[0] - a[0]), 0.0, 1.0)
	var sky: Color = a[1].lerp(b[1], f)
	env.background_color = sky
	env.fog_light_color = sky.lerp(Color(0.5, 0.52, 0.56), 0.15)
	env.ambient_light_color = a[2].lerp(b[2], f)
	env.ambient_light_energy = lerpf(a[3], b[3], f)
	# 灯：夜里亮、白天暗（碎掉的灯已经从组里拿掉了）
	var night := 1.0 - clampf(h * 3.0 + 0.3, 0.0, 1.0)
	if is_inside_tree():
		for l in get_tree().get_nodes_in_group("lamp_light"):
			l.light_energy = lerpf(0.35, 1.8, night)
