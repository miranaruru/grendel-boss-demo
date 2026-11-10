extends Node3D
## 入口：搭场景、生成玩家 / Boss / 镜头 / HUD，管理顿帧、慢动作、重开。

const ARENA_RADIUS := 12.0   # 石台（主战场）半径
const PLAY_RADIUS_OLD := 26.0   # 原来的石台方案：能跑到树林里
const PLAY_RADIUS := 22.0 if ArenaBuilder.USE_LAIR else PLAY_RADIUS_OLD   # 方案 B：泥坑 + 坑沿的坡（lair_builder.gd 的 PLAY_R）

const ArenaBuilder = preload("res://scripts/arena_builder.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BossScript = preload("res://scripts/boss.gd")
const CameraScript = preload("res://scripts/camera_rig.gd")
const HudScript = preload("res://scripts/hud.gd")
const Loc = preload("res://scripts/loc.gd")
const FxScript = preload("res://scripts/fx.gd")
const SfxScript = preload("res://scripts/sfx.gd")

var player
var boss
var cam
var hud
var fx
var slowmo_active := false
var game_over := false
var play_intro := true  # 开场 Boss 亮相；测试脚本在 add_child 之前设成 false 跳过
var intro_active := false


func _ready() -> void:
	add_to_group("game")
	Engine.time_scale = 1.0
	_setup_input()
	ArenaBuilder.build(self, ARENA_RADIUS)
	fx = FxScript.new()
	fx.name = "Fx"
	add_child(fx)
	var sfx := SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)

	player = PlayerScript.new()
	player.name = "Player"
	player.arena_radius = PLAY_RADIUS
	add_child(player)
	var ps := Vector3(0, 0, 7)
	if ArenaBuilder.USE_LAIR:
		ps = ArenaBuilder.LairBuilder.PLAYER_SPAWN  # 南口外，跑进坑
	player.global_position = Vector3(ps.x, ArenaBuilder.ground_height(ps.x, ps.z) + 0.05, ps.z)

	boss = BossScript.new()
	boss.name = "Werewolf"
	# 方案 B：Boss 只在坑里活动（扑击落点、被推开都不会越过根墙）
	boss.arena_radius = ArenaBuilder.LairBuilder.PIT_R + 0.5 if ArenaBuilder.USE_LAIR else PLAY_RADIUS
	add_child(boss)
	var bs := Vector3(0, 0, -4)
	if ArenaBuilder.USE_LAIR and play_intro:
		bs = ArenaBuilder.LairBuilder.BOSS_SPAWN  # 古树树干前：亮相后冲过来
	boss.global_position = Vector3(bs.x, ArenaBuilder.ground_height(bs.x, bs.z) + 0.05, bs.z)

	player.boss = boss
	boss.player = player

	cam = CameraScript.new()
	cam.player = player
	cam.boss = boss
	add_child(cam)

	hud = HudScript.new()
	add_child(hud)
	hud.bind(player, boss)

	player.died.connect(_on_end.bind(false))
	boss.died.connect(_on_end.bind(true))
	boss.phase_changed.connect(_on_phase)
	if play_intro:
		_intro()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
		return
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
	if Input.is_action_just_pressed("toggle_lang"):  # G：中 / 英文切换
		Loc.toggle()
		hud.apply_lang()
		hud.show_msg(Loc.t("语言：中文"), Color(0.8, 0.85, 1.0))
	if intro_active and (Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("roll") or Input.is_action_just_pressed("jump")):
		_skip_intro()
	# 调试：数字键 1-4 指定 Boss 下一招，方便练反击 / 调手感（不显示提示）
	var keys := ["claw", "slam", "pounce", "sweep"]
	for i in keys.size():
		if Input.is_action_just_pressed("debug_%d" % (i + 1)):
			boss.forced_attack = keys[i]


# ---------------- 打击感 ----------------

## 时间控制：慢动作定一个「底速」，顿帧临时冻住再回到底速。
## 新的顿帧会顶掉旧的；慢动作按优先级，低的不打断高的（完美闪避 1 < 二阶段 2 < Boss 死亡 9）。
var _base_scale := 1.0
var _slow_prio := 0
var _slow_id := 0
var _stop_id := 0
var _stopping := false
var _slow_tinted := false


func _apply_time() -> void:
	Engine.time_scale = 0.05 if _stopping else _base_scale


## 顿帧：命中时把时间几乎冻住一瞬；给了 then_dur 就接着慢放（弹反 / 反击打中）
func hitstop(duration: float = 0.06, then_scale: float = 1.0, then_dur: float = 0.0) -> void:
	if game_over:
		return
	await _freeze(duration)
	if then_dur > 0.0 and not game_over:
		slowmo(then_scale, then_dur, 1, Color(0, 0, 0, 0))


## 冻住 duration 秒（真实时间）；被新的顿帧顶掉时返回 false
func _freeze(duration: float) -> bool:
	_stop_id += 1
	var id := _stop_id
	_stopping = true
	_apply_time()
	await get_tree().create_timer(duration, true, false, true).timeout
	if id != _stop_id:
		return false
	_stopping = false
	_apply_time()
	return true


## 慢动作：tint 是期间屏幕四周的颜色（a = 0 不加），默认完美闪避的暗蓝
func slowmo(scale: float, duration: float, prio: int = 1, tint := Color(0.05, 0.1, 0.25, 0.6)) -> void:
	if prio < _slow_prio or (game_over and prio < 9):
		return
	_slow_id += 1
	var id := _slow_id
	_slow_prio = prio
	_base_scale = scale
	slowmo_active = true
	if tint.a > 0.0 or _slow_tinted:
		fx.vignette_hold(tint)
	_slow_tinted = tint.a > 0.0
	_apply_time()
	await get_tree().create_timer(duration, true, false, true).timeout
	if id != _slow_id:
		return
	if _slow_tinted:
		fx.vignette_hold(Color(0, 0, 0, 0))
	_slow_tinted = false
	_slow_prio = 0
	_base_scale = 1.0
	slowmo_active = false
	_apply_time()


## 镜头往里冲一下（弹反 / 反击打中）
func cam_punch(amount: float) -> void:
	if cam:
		cam.punch(amount)


## 瞬影斩瞬移以后，镜头快速转到主角身后
func cam_quick_turn() -> void:
	if cam:
		cam.quick_turn(0.35)


func shake(amount: float) -> void:
	if cam:
		cam.shake = maxf(cam.shake, amount)


func _on_end(victory: bool) -> void:
	if game_over:
		return
	game_over = true
	var sfx := get_tree().get_first_node_in_group("sfx")
	if victory:
		# 最后一刀：顿一下 → 0.15 倍慢放，镜头从侧面推近看它倒下、化成灰，约 7.5 秒后再弹结算
		cam.death_cam()
		slowmo(0.15, 1.6, 9, Color(0, 0, 0, 0))
		await _freeze(0.2)
		await get_tree().create_timer(7.3, true, false, true).timeout  # 等它倒下、化成灰（boss.gd 的 ASH_FADE）
	if sfx:
		sfx.music_fade_out()
	Engine.time_scale = 1.0
	hud.show_end(victory)


## 开场 Boss 亮相（约 5 秒，攻击 / 翻滚 / 跳跳过）：镜头从主角肩后推到 Boss 脸前仰拍，
## 它仰头咆哮、屏幕震、出大字名字，然后镜头飞回主角身后交还操作
func _intro() -> void:
	intro_active = true
	player.cinematic = true
	boss.intro_hold = true
	boss._face(boss._flat_to_player(), 1.0)  # 一开场就正对主角 / 镜头
	cam.intro()
	hud.cinematic(true, 0.01)
	await _real(1.3)
	if not intro_active:
		return
	boss.intro_roar(2.4)
	await _real(0.35)
	if not intro_active:
		return
	shake(0.9)
	fx.vignette(Color(0.35, 0.0, 0.0, 0.4), 1.2)
	await _real(0.45)
	if not intro_active:
		return
	hud.show_title()
	await _real(1.8)  # 到 3.9 秒：镜头开始飞回
	if not intro_active:
		return
	hud.cinematic(false, 0.8)
	await _real(0.9)
	if intro_active:
		_end_intro()


func _skip_intro() -> void:
	cam.intro_skip()
	hud.cinematic(false, 0.5)
	_end_intro()


func _end_intro() -> void:
	intro_active = false
	player.cinematic = false
	boss.intro_hold = false
	boss.cooldown = maxf(boss.cooldown, 1.2)  # 交还操作后给一点反应时间
	if ArenaBuilder.USE_LAIR:
		boss.charge_in()  # 从古树下直接冲到玩家跟前


func _real(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


## 二阶段嚎叫：慢放 0.3 倍 0.9 秒，镜头拉远抬高把整只犀渠框进来
func _on_phase(_p: int) -> void:
	slowmo(0.3, 0.9, 2, Color(0, 0, 0, 0))
	if ArenaBuilder.USE_LAIR:
		ArenaBuilder.LairBuilder.phase2(self)
	cam.frame_boss(2.0)


# ---------------- 输入（运行时注册，免去手写 project.godot 的 InputMap） ----------------

func _setup_input() -> void:
	_action("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_action("roll", [KEY_SHIFT, KEY_L], [JOY_BUTTON_B])
	_action("attack", [KEY_J], [JOY_BUTTON_X], [], MOUSE_BUTTON_LEFT)
	_action("parry", [KEY_K], [JOY_BUTTON_RIGHT_SHOULDER], [], MOUSE_BUTTON_RIGHT)
	_action("restart", [KEY_R], [JOY_BUTTON_START])
	_action("swap_hands", [KEY_H])
	_action("time_jump", [KEY_T])
	_action("toggle_lang", [KEY_G])
	for i in range(1, 5):
		_action("debug_%d" % i, [KEY_0 + i])


func _action(action: String, keys: Array = [], pads: Array = [], axes: Array = [], mouse: int = -1) -> void:
	if InputMap.has_action(action):
		return  # 重开场景时不重复注册
	InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in pads:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		InputMap.action_add_event(action, m)
	if mouse != -1:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse
		InputMap.action_add_event(action, mb)
