extends Node
# 方案 B「枯林巢穴」截图 + 帧时间：出生点 → 开场亮相 → Boss 从古树下冲过来（每 0.6 秒一张），
# 然后坡上 / 树后 / 南口前景，最后快进到黄昏、夜里各拍一张。图存到 user://lair_shots/<tag>/
# 用法：Godot --path <项目> res://tools/lair_shots.tscn --resolution 2560x1440 -- tag=v2
const AB = preload("res://scripts/arena_builder.gd")
var main
var dir := "user://lair_shots/"
var ft: Array[float] = []
var last_us := 0
var last_shot := "start"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			dir += a.substr(4) + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	_run()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if last_us > 0:
		var r := (now - last_us) / 1000000.0
		ft.append(r)
		if r > 0.1:
			print("F: slow frame ", int(r * 1000.0), " ms after ", last_shot)
	last_us = now


func real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + name_ + ".png")
	last_shot = name_


func _put_player(x: float, z: float) -> void:
	var p = main.player
	p.global_position = Vector3(x, AB.ground_height(x, z) + 0.1, z)


func _run() -> void:
	await real(0.2)
	await shot("00_spawn")
	for i in 18:  # 开场约 5 秒 + 冲锋
		await real(0.6)
		await shot("intro_%02d" % i)
		print("boss at ", main.boss.global_position, " charging=", main.boss.charging)
	await real(2.0)
	await shot("20_after_charge")
	# 坑里几个位置：倒木、瓦罐堆、茜草（Boss 会跟过来）
	for spot in [[11.0, 6.0, "21_pit_east"], [-12.0, 2.0, "22_pit_west"], [2.0, -6.0, "23_pit_center"]]:
		_put_player(spot[0], spot[1])
		await real(1.2)
		await shot(spot[2])
	# 俯瞰整个坑
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.set_process(false)  # camera_rig.gd 挂在 Camera3D 本身上，停掉它的 _process 才不会被拉回跟随
		cam.global_position = Vector3(0, 30, 22)
		cam.look_at(Vector3(0, 0, -1))
		await real(0.6)
		await shot("24_overview")
		cam.set_process(true)
	var dn = main.get_node_or_null("LairDayNight")
	if dn:
		dn.t = 0.55
		await real(1.0)
		await shot("30_dusk")
		dn.t = 1.0
		await real(1.0)
		await shot("31_night")
		_put_player(0.0, 18.0)
		await real(1.2)
		await shot("32_night_south")
		# 夜里石灯笼的特写（看蜡烛火苗）
		var cam2 := get_viewport().get_camera_3d()
		if cam2:
			cam2.set_process(false)
			cam2.global_position = Vector3(-2.7, 1.32, 16.85)
			cam2.look_at(Vector3(-3.0, 1.2, 16.0))
			await real(0.4)
			await shot("33_lantern_close")
			cam2.set_process(true)
	_done()


func _done() -> void:
	ft.sort()
	var sum := 0.0
	for x in ft:
		sum += x
	print("F: frames=", ft.size(), " avg ms=", 1000.0 * sum / ft.size(), " p99 ms=", 1000.0 * ft[int(ft.size() * 0.99)], " worst ms=", 1000.0 * ft[-1])
	get_tree().quit()
