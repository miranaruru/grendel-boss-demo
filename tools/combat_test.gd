extends Node
# 全套战斗测试：三连、弹反、完美闪避 + 瞬影斩、跳 + 落雷斩、扑击、调试键、二阶段、Boss 死、玩家死、重开。用法见 Obsidian「项目路径与环境」
var main
var p
var b

func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	main.play_intro = false
	add_child(main)
	p = main.player
	b = main.boss
	_run()

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)

func wait_boss_t(x: float) -> void:
	while not (b.state == b.S.ATTACK and b.t >= x):
		await get_tree().physics_frame

func wait_idle() -> void:
	while b.state != b.S.IDLE:
		await get_tree().physics_frame
	await frames(5)

func setup(atk: String) -> void:
	p.global_position = b.global_position + Vector3(0, 0, 2.5)
	b.forced_attack = atk
	b.cooldown = 0.0
	await get_tree().physics_frame

func _run() -> void:
	await frames(20)
	print("T: combo")
	b.cooldown = 99.0
	p.global_position = b.global_position + Vector3(0, 0, 2.0)
	for i in 3:
		await tap("attack")
		await frames(14)
	await frames(30)
	print("T: combo done boss hp=", b.hp)

	print("T: claw + parry")
	await setup("claw")
	await wait_boss_t(0.35)
	await tap("parry")
	await frames(90)
	print("T: claw result boss state=", b.state, " hp=", b.hp, " player hp=", p.hp)
	await wait_idle()

	print("T: slam + perfect dodge + phantom")
	await setup("slam")
	await wait_boss_t(1.38)
	await tap("roll")
	await frames(4)
	print("T: dodge_counter_t=", p.dodge_counter_t)
	await tap("attack")
	await frames(60)
	print("T: slam result boss hp=", b.hp, " player hp=", p.hp)
	await wait_idle()

	print("T: sweep + jump + plunge")
	await setup("sweep")
	await wait_boss_t(0.45)
	await tap("jump")
	while p.aerial_counter_t <= 0.0 and b.state == b.S.ATTACK:
		await get_tree().physics_frame
	print("T: aerial_counter_t=", p.aerial_counter_t, " y=", p.global_position.y)
	await tap("attack")
	await frames(90)
	print("T: sweep result boss hp=", b.hp, " state=", b.state, " player hp=", p.hp)
	await wait_idle()

	print("T: pounce (take hit) from range")
	p.global_position = b.global_position + Vector3(0, 0, 7.0)
	b.forced_attack = "pounce"
	b.cooldown = 0.0
	await frames(5)
	await wait_idle()
	print("T: pounce result player hp=", p.hp)

	print("T: debug keys")
	for i in range(1, 5):
		await tap("debug_%d" % i)
	print("T: forced=", b.forced_attack)

	print("T: phase 2")
	b.take_damage(b.hp - b.MAX_HP * 0.5 + 1.0)
	await frames(80)
	print("T: phase=", b.phase)
	await setup("claw")
	await frames(150)

	print("T: boss death")
	b.take_damage(9999.0)
	await frames(30)
	print("T: death slowmo time_scale=", Engine.time_scale, " cam fov=", main.cam.fov)
	for i in 2000:  # 死亡慢放 + 镜头，约 2 秒后才弹结算
		if main.hud.end_label.visible:
			break
		await frames(1)
	print("T: boss dead=", b.is_dead(), " hud end visible=", main.hud.end_label.visible)

	print("T: player death")
	for i in 20:
		p.receive_attack(20.0, false, b.global_position)
		await frames(2)
	print("T: player dead=", p.is_dead())
	await frames(30)
	print("T: restart")
	main.get_tree().paused = false
	# main's reload would reload this driver scene; test main reinstance instead
	main.queue_free()
	await frames(2)
	main = load("res://main.tscn").instantiate()
	main.play_intro = false
	add_child(main)
	await frames(60)
	print("T: ALL DONE")
	get_tree().quit()
