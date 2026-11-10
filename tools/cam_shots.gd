extends Node
# 镜头截图 + 帧时间：开窗口跑，远 / 近身 / 弹反 / 瞬影斩 / 二阶段 / Boss 死亡各存图到 user://cam_shots/<tag>/，最后打印平均 / 最差帧时间
# 用法：Godot --path <项目> res://tools/cam_shots.tscn --resolution 2560x1440 -- tag=after
var main
var p
var b
var dir := "user://cam_shots/"
var ft: Array[float] = []

func _ready() -> void:
	var intro := false  # 加参数 intro：只拍开场亮相（每 0.5 秒一张）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			dir += a.substr(4) + "/"
		if a == "intro":
			intro = true
	DirAccess.make_dir_recursive_absolute(dir)
	main = load("res://main.tscn").instantiate()
	main.play_intro = intro
	add_child(main)
	p = main.player
	b = main.boss
	if intro:
		_run_intro()
	else:
		_run()

func _run_intro() -> void:
	for i in 12:
		await real(0.5)
		await shot("intro_%02d" % (i + 1))
	_done()

var last_shot := "start"

var last_us := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var r := (now - last_us) / 1000000.0
	last_us = now
	ft.append(r)
	if r > 0.1:
		print("F: slow frame ", int(r * 1000.0), " ms after ", last_shot)

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)

func shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + name_ + ".png")
	last_shot = name_
	print("S: ", name_, " fov=", main.cam.fov, " time=", Engine.time_scale)

func wait_boss_t(x: float) -> void:
	while not (b.state == b.S.ATTACK and b.t >= x):
		await get_tree().physics_frame

func wait_idle() -> void:
	while b.state != b.S.IDLE:
		await get_tree().physics_frame
	await frames(5)

func setup(atk: String, dist: float = 2.5) -> void:
	p.global_position = b.global_position + Vector3(0, 0, dist)
	b.forced_attack = atk
	b.cooldown = 0.0
	await get_tree().physics_frame

func _run() -> void:
	await frames(60)
	ft.clear()
	b.cooldown = 99.0
	p.global_position = b.global_position + Vector3(0, 0, 11.0)
	await real(2.0)
	await shot("01_far")
	p.global_position = b.global_position + Vector3(0, 0, 3.0)
	await real(2.0)
	await shot("02_close")
	var new_cam: bool = main.cam.has_method("punch")  # 旧版镜头只拍远 / 近 / 二阶段（对比用）
	# 横着跑：主角在画面里往右偏，停下后慢慢回到左边
	b.cooldown = 99.0
	p.global_position = b.global_position + Vector3(0, 0, 7.0)
	await real(1.5)
	await shot("02b_idle_left")
	Input.action_press("move_right")
	await real(0.9)
	await shot("02c_run_right")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await real(1.4)
	await shot("02d_run_left")
	Input.action_release("move_left")
	await real(2.5)
	await shot("02e_settled")
	if new_cam:
		await _counters()
	b.cooldown = 99.0
	p.global_position = b.global_position + Vector3(0, 0, 4.0)
	await real(1.0)
	b.take_damage(b.hp - b.MAX_HP * 0.5 + 1.0)
	await real(0.8)
	await shot("05_phase2_wide")
	await real(2.0)
	if not new_cam:
		_done()
		return

	p.global_position = b.global_position + Vector3(0, 0, 3.0)
	await real(1.5)
	b.take_damage(9999.0)
	for i in 9:  # 倒下 → 推近 → 化成灰，约每秒一张
		await real(0.75)
		await shot("06_death_%d" % (i + 1))
	_done()

func _counters() -> void:
	await setup("claw")
	await wait_boss_t(0.35)
	await tap("parry")
	while main.slowmo_active == false:
		await get_tree().physics_frame
	await real(0.1)
	await shot("03_parry_slowmo")
	await wait_idle()

	await setup("slam")
	await wait_boss_t(1.38)
	await tap("roll")
	await frames(4)
	await tap("attack")
	await real(0.12)
	await shot("04a_phantom_turning")
	await real(0.35)
	await shot("04b_phantom_after")
	await wait_idle()

func _done() -> void:
	ft.sort()
	var sum := 0.0
	for x in ft:
		sum += x
	print("F: frames=", ft.size(), " avg ms=", 1000.0 * sum / ft.size(), " p99 ms=", 1000.0 * ft[int(ft.size() * 0.99)], " worst ms=", 1000.0 * ft[-1])
	get_tree().quit()
