extends Node
# 特效截图 + 帧时间：开窗口跑，几个关键时刻存图到 user://fx_shots/，最后打印平均 / 最差帧时间
var main
var p
var b
var dir := "user://fx_shots/"
var ft: Array[float] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	main = load("res://main.tscn").instantiate()
	main.play_intro = false
	add_child(main)
	p = main.player
	b = main.boss
	_run()

func _process(delta: float) -> void:
	ft.append(delta / maxf(Engine.time_scale, 0.01))

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)

func shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + name_ + ".png")
	print("S: ", name_)

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
	p.global_position = b.global_position + Vector3(0, 0, 2.0)
	await tap("attack")
	await frames(8)
	await tap("attack")
	await frames(9)
	await shot("01_combo_hit")
	await frames(5)
	await shot("01c_sparks_fly")
	await frames(30)

	p.global_position = b.global_position + Vector3(4, 0, 4)
	Input.action_press("move_left")
	await frames(3)
	await tap("roll")
	Input.action_release("move_left")
	await frames(12)
	await shot("01b_roll_dust")
	await frames(30)

	await setup("claw")
	await wait_boss_t(0.42)
	await shot("02_claw_trail")
	await frames(2)
	await shot("03_claw_arc")
	await wait_idle()
	await setup("claw")
	await wait_boss_t(0.35)
	await tap("parry")
	while Engine.time_scale > 0.5:
		await get_tree().process_frame
	await get_tree().process_frame
	await shot("04_parry")
	await frames(14)
	await shot("05_cross_slash")
	await wait_idle()

	await setup("slam", 3.0)
	await wait_boss_t(1.47)
	await frames(2)
	await shot("06_slam_impact")
	await frames(40)
	await shot("07_slam_cracks")
	await wait_idle()

	await setup("slam", 9.0)  # 站在砸击范围外、震波范围内 → 被震晕（Boss 会往前冲 ~1.8 米）
	var hp0: float = p.hp
	await wait_boss_t(1.47)
	await frames(3)
	await shot("13_quake")
	await frames(14)
	main.hud.msg_label.visible = false  # 提示字正好压在主角头顶，截图时先藏起来看星星
	await shot("14_dizzy")
	main.hud.msg_label.visible = true
	print("S: player state after quake=", p.state, " hp=", p.hp, " hurt_time=", p.hurt_time, " hp_lost=", hp0 - p.hp)
	await wait_idle()

	await setup("sweep")
	await wait_boss_t(0.45)
	await tap("jump")
	while p.aerial_counter_t <= 0.0 and b.state == b.S.ATTACK:
		await get_tree().physics_frame
	await shot("08_sweep_dust")
	await tap("attack")
	while p.state != p.S.COUNTER:
		await get_tree().physics_frame
	await frames(2)
	await shot("09_plunge_lightning")
	await wait_idle()

	p.global_position = b.global_position + Vector3(0, 0, 3.0)
	b.cooldown = 99.0
	p.receive_attack(20.0, false, b.global_position)
	await frames(2)
	await shot("10_player_hit")
	await frames(40)

	b.take_damage(b.hp - b.MAX_HP * 0.5 + 1.0)
	await frames(12)
	await shot("11_phase2_roar")
	await frames(80)
	b.take_damage(9999.0)
	await frames(90)
	await shot("12_death_ashes")
	var s := 0.0
	var worst := 0.0
	for f in ft:
		s += f
		worst = maxf(worst, f)
	var sorted := ft.duplicate()
	sorted.sort()
	print("F: frames=", ft.size(), " avg_ms=", s / ft.size() * 1000.0, " p99_ms=", sorted[int(sorted.size() * 0.99)] * 1000.0, " worst_ms=", worst * 1000.0)
	get_tree().quit()
