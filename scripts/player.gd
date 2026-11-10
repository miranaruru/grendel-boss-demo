extends CharacterBody3D
## 主人公：右手单手剑 + 左手盾。移动 / 跳 / 翻滚 / 三段连击 + 三种反击。
##
## 反击 1「弹反 · 十字斩」：Boss 可弹反招式命中前 0.2 秒内按弹反 → Boss 硬直 + 自动反斩
## 反击 2「瞬影斩」     ：翻滚开始 0.2 秒内被攻击（完美闪避）→ 慢动作，按攻击瞬移到 Boss 背后斩击
## 反击 3「落雷斩」     ：跳起躲过 Boss 的低扫 → 空中按攻击，下劈落地造成大伤害 + 硬直
##
## 原点在脚底。模型朝 -Z。
## 有 ANIM_SOURCE（Quaternius UAL2）时用骨骼动画，状态 → 动画见 ANIM。外形用 MODEL_PATH 的角色
## （现在是 Mixamo 的 Ganfaul），没有就用 UAL2 自带的人偶；
## 没有就退回代码旋转方块的占位动画。

signal died
signal hp_changed(hp: float, max_hp: float)
signal counter_triggered(text: String)

enum S { FREE, ROLL, ATTACK, PARRY, HURT, COUNTER, PLUNGE, DEAD, BLOCK }

const MAX_HP := 100.0
const SPEED := 6.5
const JUMP_VELOCITY := 8.0
const GRAVITY := 24.0
const ROLL_SPEED := 12.0
const ROLL_TIME := 0.5
const ROLL_IFRAMES := 0.38     # 翻滚无敌时间
const PERFECT_DODGE := 0.2     # 翻滚开始多少秒内被打 = 完美闪避
const PARRY_TIME := 0.42       # 弹反动作总时长（没弹到也要吃满硬直）
const PARRY_WINDOW := 0.2      # 弹反有效窗口
# 按住持续举盾：弹反动作结束时还按着 K / 右键，就进入举盾
const BLOCK_REDUCTION := 0.7   # 举盾挡住「可弹反」的招，伤害减 70%
const BLOCK_ANGLE := 120.0     # 只挡正面这个角度以内的攻击
const BLOCK_MOVE_MULT := 0.35  # 举盾时移动速度倍率
const GUARD_BREAK_TIME := 0.9  # 「不可弹反」的招打在盾上 = 破防：全额伤害 + 这么久的硬直
const DODGE_COUNTER_WINDOW := 0.8
const AERIAL_COUNTER_WINDOW := 0.9

# 三段连击：时长 / 判定时刻 / 伤害 / 距离 / 前冲速度
const COMBO := [
	{"dur": 0.36, "hit": 0.14, "dmg": 7.0, "range": 2.6, "lunge": 3.0},
	{"dur": 0.36, "hit": 0.14, "dmg": 7.0, "range": 2.6, "lunge": 3.0},
	{"dur": 0.62, "hit": 0.26, "dmg": 14.0, "range": 3.0, "lunge": 5.0},
]
# 反击动作
const COUNTERS := {
	"cross": {"dur": 0.7, "hit": 0.28, "dmg": 26.0, "range": 3.6, "stagger": 0.0},    # 弹反后 Boss 已经硬直
	"phantom": {"dur": 0.5, "hit": 0.14, "dmg": 22.0, "range": 3.2, "stagger": 0.8},
	"recover": {"dur": 0.3, "hit": -1.0, "dmg": 0.0, "range": 0.0, "stagger": 0.0},
}

var boss
var cinematic := false  # 开场亮相期间为 true
var arena_radius := 18.0
var hp := MAX_HP
var state := S.FREE
var t := 0.0
var combo_i := 0
var combo_queued := false
var hit_done := false
var roll_dir := Vector3.FORWARD
var dodge_counter_t := 0.0
var kick_t := 0.0  # 翻滚时脚下扬尘的间隔计时
var tip_hist: Array[Vector3] = []  # 剑尖最近几帧的位置（主角局部坐标，去掉身体本身的移动）：算砍中那一下剑往哪挥
var aerial_counter_t := 0.0
var counter_kind := ""
var plunge_is_counter := false
var air_attack_used := false
var flash := 0.0
var shield_kick := 0.0     # 盾挨了一下：往后一震，慢慢回位
var shield_glow := 0.0     # 盾边亮光（挡住时闪一下）
var shield_tilt := 0.0     # 破防：盾被打偏到一边
var shield_inner: Node3D
var shield_rim_mat: StandardMaterial3D
var hurt_time := 0.45
var floor_y := 0.0  # 最近一次站在地上时的高度（石台有高低差，判断「跳多高」要相对它）  # 普通受击 0.45s，破防时更长

# 骨骼动画（UAL2 人偶）
# 三个文件在导入设置里都挂了 assets/retarget/ 下的 BoneMap（人形骨骼重定向），骨骼统一改名成
# Godot 标准人形骨骼（Hips / RightHand …），所以 UAL 的动作能直接播在 Mixamo 角色身上。
const MODEL_PATH := "res://assets/player/Ganfaul M Aure.fbx"
const MODEL_HEIGHT := 1.83  # 不同角色身高不一样，统一缩放到 UAL 人偶的身高
# 左手剑右手盾：把整个角色左右镜像，所有动作跟着镜像，判定 / 伤害 / 按键都不变
const LEFT_HANDED := false  # 开局默认；游戏里按 H 随时切换
const ANIM_SOURCE := "res://assets/ual2/UAL2_Standard.glb"
const EXTRA_ANIMS := "res://assets/ual2/UAL1_Standard.glb"  # UAL1 的动画并进来，前缀 ual1/
const ANIM_BLEND := 0.08
# 动作 → [动画名, 从第几秒开始, 播放速度]
# 起点 / 速度是按动画里挥刀最快的那一帧对齐上面 COMBO / COUNTERS 的 hit 时刻算的
const ANIM := {
	"idle": ["Idle_Shield", 0.0, 1.0],          # 举盾警戒

	"run": ["ual1/Sprint", 0.0, 1.0],
	"jump": ["NinjaJump_Start", 0.15, 1.2],
	"fall": ["NinjaJump_Idle", 0.0, 1.0],
	"roll": ["ual1/Roll", 0.0, 1.9],            # 前 0.95s 是翻滚本体，压进 ROLL_TIME
	"attack0": ["Sword_Regular_A", 0.05, 1.4],  # 挥刀峰值 0.25s → 0.14
	"attack1": ["Sword_Regular_B", 0.07, 1.4],  # 0.27s → 0.14
	"attack2": ["Sword_Regular_C", 0.35, 1.25], # 0.67s → 0.26
	"parry": ["Shield_OneShot", 0.0, 1.6],      # 左手举盾格挡
	"block": ["Shield_OneShot", 0.18, 0.0],     # 按住举盾：定格在盾举到正前方的那一帧
	"hurt": ["ual1/Hit_Chest", 0.0, 0.75],
	"cross": ["Sword_Heavy_Combo", 0.12, 1.0],  # 双手峰值 0.40s → 0.28
	"phantom": ["Sword_Dash", 0.12, 1.5],       # 0.33s → 0.14
	"plunge": ["Sword_Regular_C", 0.4, 0.4],
	"recover": ["Sword_Regular_C", 0.7, 1.0],
	"dead": ["ual1/Death01", 0.0, 1.0],
}
# 没有 UAL1 时用 UAL2 里的动作顶上
const ANIM_FALLBACK := {
	"idle": ["Idle_Shield", 0.0, 1.0],
	"run": ["Idle_Shield", 0.0, 1.0],
	"roll": ["NinjaJump_Start", 0.4, 0.0],      # 定格在抱膝姿势，配合 rig 前翻 = 翻滚
	"hurt": ["Hit_Knockback", 0.0, 0.4],        # 只播开头踉跄那一段
	"dead": ["Hit_Knockback", 0.0, 1.0],
}
var anim: AnimationPlayer
var cur_anim := ""
var model_node: Node3D
var left_handed := LEFT_HANDED

var rig: Node3D
var blade_l: Node3D
var blade_r: Node3D
var body_mat: StandardMaterial3D
var trail  # 刀光拖尾（fx_trail.gd）


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)
	# 只和地面碰撞，与 Boss 用代码做软推开（这样可以翻滚穿过 Boss）
	collision_layer = 2
	collision_mask = 1 | Destructible.RUBBLE_LAYER  # 拱门碎石只挡主角
	floor_snap_length = 0.5  # 石台有坡，下坡时贴住地面
	_build_visual()


func _build_visual() -> void:
	if ResourceLoader.exists(ANIM_SOURCE):
		_build_model()
		return
	rig = Node3D.new()
	rig.position.y = 0.85
	add_child(rig)
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.55, 0.50, 0.42)
	body_mat.emission_enabled = true
	body_mat.emission = Color.BLACK

	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.32
	cm.height = 1.3
	body.mesh = cm
	body.position.y = -0.1
	body.material_override = body_mat
	rig.add_child(body)

	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	head.mesh = sm
	head.position.y = 0.72
	head.material_override = body_mat
	rig.add_child(head)

	# 围巾 / 披风：一个朝后的薄片，方便看清朝向
	var cape := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.9, 0.05)
	cape.mesh = bm
	cape.position = Vector3(0, 0.1, 0.32)
	cape.rotation.x = 0.15
	var cape_mat := StandardMaterial3D.new()
	cape_mat.albedo_color = Color(0.45, 0.12, 0.10)
	cape.material_override = cape_mat
	rig.add_child(cape)

	blade_r = _make_blade(rig, Vector3(0.42, 0.1, -0.15))
	blade_l = _make_blade(rig, Vector3(-0.42, 0.1, -0.15))


## 骨骼人偶：rig 仍在腰部高度（翻滚 / 瞬影斩的整体旋转还靠它），人偶往下挪回脚底。
## 双刀挂在两只手的骨骼上。
func _build_model() -> void:
	rig = Node3D.new()
	rig.position.y = 0.85
	add_child(rig)
	var model_path := MODEL_PATH if ResourceLoader.exists(MODEL_PATH) else ANIM_SOURCE
	var model: Node3D = load(model_path).instantiate()
	model.position.y = -0.85
	model.rotation.y = PI  # 模型朝 +Z，主角朝 -Z
	rig.add_child(model)
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	model.scale = Vector3.ONE * (MODEL_HEIGHT / mesh.get_aabb().size.y)
	model_node = model
	set_left_handed(left_handed)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	if model_path != ANIM_SOURCE:
		# 换皮：角色自带的动画（Mixamo 的 T-Pose）换成 UAL2 的动作库
		var src: Node = load(ANIM_SOURCE).instantiate()
		var src_lib: AnimationLibrary = src.find_children("*", "AnimationPlayer", true, false)[0].get_animation_library("")
		src.free()
		if anim.has_animation_library(""):
			anim.remove_animation_library("")
		anim.add_animation_library("", src_lib)
	if ResourceLoader.exists(EXTRA_ANIMS):
		var extra: Node = load(EXTRA_ANIMS).instantiate()
		var lib: AnimationLibrary = extra.find_children("*", "AnimationPlayer", true, false)[0].get_animation_library("")
		if lib.has_animation("Sword_Idle"):
			lib.get_animation("Sword_Idle").loop_mode = Animation.LOOP_LINEAR
		anim.add_animation_library("ual1", lib)
		extra.free()
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	# 受击闪红 / 弹反窗口闪白：叠一层加法发光材质（Mixamo 角色上半透明叠加的 alpha 不生效，会整个变成纯色）
	body_mat = StandardMaterial3D.new()
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	body_mat.disable_fog = true  # 不关雾的话雾色会叠到角色身上
	body_mat.albedo_color = Color.BLACK
	for m in sk.find_children("*", "MeshInstance3D", true, false):
		m.material_overlay = body_mat
	# 右手单手剑、左手盾（UAL 的剑招和盾动作本来就是按右手剑左手盾做的）
	blade_r = _make_sword(_hand(sk, "RightHand"))
	_fit_grip(sk, blade_r, "Right", model.scale.y)
	trail = preload("res://scripts/fx_trail.gd").new()
	trail.base_node = blade_r
	trail.base_offset = Vector3(0, 0, 0.2)
	trail.tip_offset = Vector3(0, 0, 1.0)
	add_child(trail)
	blade_l = _make_shield(_hand(sk, "LeftHand"))
	_fit_shield(sk, blade_l, "Left", model.scale.y)


## 盾：盾面朝手背方向（像绑在小臂上那样），中心在拳头稍靠手背一侧
func _fit_shield(sk: Skeleton3D, pivot: Node3D, side: String, model_scale: float) -> void:
	var hand := sk.get_bone_global_rest(sk.find_bone(side + "Hand"))
	var inv := hand.affine_inverse()
	var index: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "IndexProximal")).origin
	var little: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "LittleProximal")).origin
	var middle: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "MiddleProximal")).origin
	var thumb: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "ThumbProximal")).origin
	var across := (index - little).normalized()
	var fingers := middle.normalized()
	var back := fingers.cross(across).normalized()
	if back.dot(thumb - middle * 0.5) > 0.0:  # 拇指在掌心一侧，手背朝反方向
		back = -back
	pivot.basis = Basis.looking_at(-back, fingers) * Basis.from_scale(Vector3.ONE / model_scale)  # 盾面法线沿 +Z
	pivot.position = middle * 0.4 + back * 0.06


func _metal(c: Color, rough: float = 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.8
	m.roughness = rough
	return m


## 单手剑：原点在握把中间，剑身沿 +Z
func _make_sword(parent: Node3D) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	var steel := _metal(Color(0.78, 0.8, 0.84), 0.25)
	var dark := _metal(Color(0.22, 0.2, 0.18), 0.6)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.25, 0.15, 0.1)
	leather.roughness = 0.9
	var parts := [
		[_box(Vector3(0.055, 0.014, 0.82)), steel, Vector3(0, 0, 0.53)],   # 剑身
		[_box(Vector3(0.022, 0.016, 0.06)), steel, Vector3(0, 0, 0.97)],   # 剑尖（收窄）
		[_box(Vector3(0.24, 0.035, 0.035)), dark, Vector3(0, 0, 0.11)],    # 护手
		[_box(Vector3(0.03, 0.03, 0.18)), leather, Vector3(0, 0, 0.0)],    # 握把
		[_box(Vector3(0.05, 0.05, 0.05)), dark, Vector3(0, 0, -0.11)],     # 剑首
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		mi.material_override = p[1]
		mi.position = p[2]
		pivot.add_child(mi)
	return pivot


## 圆盾：原点在盾背中心，盾面朝 +Z
func _make_shield(parent: Node3D) -> Node3D:
	var outer := Node3D.new()
	parent.add_child(outer)
	var pivot := Node3D.new()  # 实际的盾都挂在这层下面：挨打时只动这层（往后震 / 被打偏），外层的贴手位置不变
	outer.add_child(pivot)
	shield_inner = pivot
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.22, 0.15)
	wood.roughness = 0.95
	var iron := _metal(Color(0.3, 0.29, 0.28), 0.55)
	var face := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.36
	cyl.bottom_radius = 0.36
	cyl.height = 0.04
	cyl.radial_segments = 24
	face.mesh = cyl
	face.material_override = wood
	face.rotation.x = PI * 0.5  # 圆柱轴从 Y 转到 Z
	pivot.add_child(face)
	var rim := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.34
	tor.outer_radius = 0.385
	tor.rings = 24
	rim.mesh = tor
	shield_rim_mat = iron.duplicate() as StandardMaterial3D
	shield_rim_mat.emission_enabled = true
	shield_rim_mat.emission = Color(1.0, 0.85, 0.55)
	shield_rim_mat.emission_energy_multiplier = 0.0
	rim.material_override = shield_rim_mat
	rim.rotation.x = PI * 0.5
	pivot.add_child(rim)
	var boss := MeshInstance3D.new()  # 盾心铁包
	var sph := SphereMesh.new()
	sph.radius = 0.09
	sph.height = 0.1
	boss.mesh = sph
	boss.material_override = iron
	boss.position.z = 0.03
	pivot.add_child(boss)
	return outer


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## 按手的骨骼算握刀方向：刀身沿「小指根 → 食指根」穿过拳心，从虎口那一侧伸出。
## 不依赖某个模型的骨骼轴向，换角色也不用重新调。
func _fit_grip(sk: Skeleton3D, pivot: Node3D, side: String, model_scale: float) -> void:
	var hand := sk.get_bone_global_rest(sk.find_bone(side + "Hand"))
	var inv := hand.affine_inverse()
	var index: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "IndexProximal")).origin
	var little: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "LittleProximal")).origin
	var middle: Vector3 = inv * sk.get_bone_global_rest(sk.find_bone(side + "MiddleProximal")).origin
	var dir := (index - little).normalized()
	var fingers := middle.normalized()
	pivot.basis = Basis.looking_at(-dir, fingers) * Basis.from_scale(Vector3.ONE / model_scale)  # 刀身沿 +Z；抵消模型缩放，刀长保持 1 米
	pivot.position = middle * 0.6  # 握在拳心


func set_left_handed(on: bool) -> void:
	left_handed = on
	if model_node:
		model_node.scale.x = -absf(model_node.scale.x) if on else absf(model_node.scale.x)


func _hand(sk: Skeleton3D, bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	return ba


func _make_blade(parent: Node3D, pos: Vector3, dir: float = -1.0) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.12, 1.0)
	blade.mesh = bm
	blade.position.z = 0.55 * dir
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.85, 0.9)
	m.metallic = 0.8
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(0.3, 0.45, 0.6)
	m.emission_energy_multiplier = 0.4
	blade.material_override = m
	pivot.add_child(blade)
	return pivot


# ================= 主循环 =================

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("swap_hands"):
		set_left_handed(not left_handed)
		counter_triggered.emit("左手剑 · 右手盾" if left_handed else "右手剑 · 左手盾")
	t += delta
	dodge_counter_t = maxf(0.0, dodge_counter_t - delta)
	aerial_counter_t = maxf(0.0, aerial_counter_t - delta)
	flash = maxf(0.0, flash - delta * 4.0)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		air_attack_used = false
		floor_y = global_position.y

	if cinematic:  # 开场亮相：不吃输入，原地站着
		_stop(delta, 30.0)
	else:
		_state_step(delta)
	_after_step(delta)


func _state_step(delta: float) -> void:
	match state:
		S.FREE: _st_free(delta)
		S.ROLL: _st_roll(delta)
		S.ATTACK: _st_attack(delta)
		S.PARRY: _st_parry(delta)
		S.BLOCK: _st_block(delta)
		S.HURT: _st_hurt(delta)
		S.COUNTER: _st_counter(delta)
		S.PLUNGE: _st_plunge(delta)
		S.DEAD: _stop(delta, 10.0)


func _after_step(delta: float) -> void:
	var want := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	_step_up(want)
	for d in get_tree().get_nodes_in_group("destructible"):  # 主角穿过树冠：树轻轻弯一下（约 3°）
		if d.kind == Destructible.Kind.TREE:
			d.push(global_position, 0.35, 0.06)
	# 翻滚撞上 / 被挡住时，能被主角打碎的东西（陶罐）直接撞碎
	if state == S.ROLL:
		_hit_props(0.6, 360.0)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if state == S.ROLL and c and c.get_parent() is Destructible:
			c.get_parent().hit(999.0, global_position, "player")
	_separate_from_boss()
	_clamp_to_arena()
	_animate(delta)
	_animate_shield(delta)
	if blade_r and model_node:
		tip_hist.append(to_local(blade_r.to_global(Vector3(0, 0, 0.9))))
		if tip_hist.size() > 5:
			tip_hist.pop_front()
	if trail:
		var countering := state == S.COUNTER and counter_kind != "recover"
		trail.active = state == S.ATTACK or countering or state == S.PLUNGE
		trail.color = Color(1.0, 0.82, 0.4, 0.9) if countering or (state == S.PLUNGE and plunge_is_counter) else Color(0.8, 0.9, 1.0, 0.75)


func _st_free(delta: float) -> void:
	var dir := _input_dir()
	var target := dir * SPEED
	velocity.x = move_toward(velocity.x, target.x, 60.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 60.0 * delta)
	if dir.length() > 0.1:
		_face(dir, delta * 14.0)

	if Input.is_action_just_pressed("roll") and is_on_floor():
		_start_roll(dir)
	elif Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_sfx("cloth")
	elif Input.is_action_just_pressed("attack"):
		if dodge_counter_t > 0.0:
			_start_counter("phantom")
		elif not is_on_floor():
			if aerial_counter_t > 0.0:
				_start_plunge(true)
			elif not air_attack_used:
				_start_plunge(false)
		else:
			_start_attack(0)
	elif Input.is_action_just_pressed("parry") and is_on_floor():
		_set_state(S.PARRY)
		_sfx("shield_up")


func _st_roll(delta: float) -> void:
	var k := 1.0 - (t / ROLL_TIME) * 0.6
	velocity.x = roll_dir.x * ROLL_SPEED * k
	velocity.z = roll_dir.z * ROLL_SPEED * k
	# 一路在脚下扬起小团尘土，往身后飘
	kick_t -= delta
	if kick_t <= 0.0 and is_on_floor():
		kick_t = 0.07
		_fx("kick", [global_position, -roll_dir, 0.6])
	if dodge_counter_t > 0.0 and Input.is_action_just_pressed("attack"):
		_start_counter("phantom")
		return
	if t >= ROLL_TIME:
		_fx("kick", [global_position + roll_dir * 0.3, roll_dir, 1.0])  # 收势时往前扑一团
		_set_state(S.FREE)


func _st_attack(delta: float) -> void:
	var c: Dictionary = COMBO[combo_i]
	var hit_t: float = c["hit"]
	var dur: float = c["dur"]
	if t < hit_t:
		var fwd := _fwd()
		var lunge: float = c["lunge"]
		velocity.x = fwd.x * lunge
		velocity.z = fwd.z * lunge
	else:
		_stop(delta, 30.0)
	if not hit_done and t >= hit_t:
		hit_done = true
		_melee(c["range"], 130.0, c["dmg"], 0.0, 0.05)
		_hit_props(c["range"] + 0.4, 150.0)
	if Input.is_action_just_pressed("attack"):
		combo_queued = true
	# 出刀后可以用翻滚取消
	if hit_done and Input.is_action_just_pressed("roll"):
		_start_roll(_input_dir())
		return
	if combo_queued and combo_i < COMBO.size() - 1 and t >= dur * 0.7:
		_start_attack(combo_i + 1)
	elif t >= dur:
		_set_state(S.FREE)


func _st_parry(delta: float) -> void:
	_stop(delta, 40.0)
	if t >= PARRY_TIME:
		_set_state(S.BLOCK if Input.is_action_pressed("parry") else S.FREE)


## 举盾：慢慢移动、转向 Boss；不能攻击 / 翻滚，松开才能行动
func _st_block(delta: float) -> void:
	var target := _input_dir() * SPEED * BLOCK_MOVE_MULT
	velocity.x = move_toward(velocity.x, target.x, 40.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 40.0 * delta)
	_face(_flat_to_boss(), delta * 8.0)
	if not Input.is_action_pressed("parry"):
		_set_state(S.FREE)


func _st_hurt(delta: float) -> void:
	_stop(delta, 14.0)
	if t >= hurt_time:
		_set_state(S.FREE)


func _st_counter(delta: float) -> void:
	var c: Dictionary = COUNTERS[counter_kind]
	var hit_t: float = c["hit"]
	if counter_kind == "cross" and t < hit_t:
		var to_boss := _flat_to_boss()
		if to_boss.length() > 2.0:
			var d := to_boss.normalized() * 8.0
			velocity.x = d.x
			velocity.z = d.z
		else:
			_stop(delta, 40.0)
	else:
		_stop(delta, 30.0)
	if not hit_done and hit_t >= 0.0 and t >= hit_t:
		hit_done = true
		if _melee(c["range"], 360.0, c["dmg"], c["stagger"], 0.12):
			_game_call("hitstop", [0.14, 0.2, 0.45])  # 反击打中：顿一下接慢放
			_game_call("cam_punch", [1.0])
		_game_call("shake", [0.35])
	if t >= c["dur"]:
		_set_state(S.FREE)


func _st_plunge(delta: float) -> void:
	velocity.y -= GRAVITY * 1.5 * delta  # 下劈下落更快
	if is_on_floor() and t > 0.05:
		var dmg := 30.0 if plunge_is_counter else 9.0
		var stagger := 1.2 if plunge_is_counter else 0.0
		var r := 3.4 if plunge_is_counter else 2.4
		var landed := _melee(r, 360.0, dmg, stagger, 0.1 if plunge_is_counter else 0.05)
		if landed and plunge_is_counter:
			_game_call("hitstop", [0.14, 0.2, 0.45])
			_game_call("cam_punch", [1.0])
		var gp := global_position + _fwd() * 0.8
		if plunge_is_counter:
			_game_call("shake", [0.6])
			_fx("lightning", [gp])
			_fx("ring", [gp, 6.0, Color(0.6, 0.85, 1.0, 1.0), 0.5])
			_fx("cracks", [gp, 2.6])
			_fx("dust", [gp, 3.0, 1.0])
			_fx("sparks", [gp + Vector3.UP * 0.3, Vector3.UP, Color(0.7, 0.9, 1.0), 2.5])
			_sfx("thunder", gp)
			_sfx("slam", gp)
		else:
			_fx("dust", [gp, 1.5, 0.4])
			_sfx("step")
		counter_kind = "recover"
		hit_done = true
		state = S.COUNTER
		t = 0.0
		cur_anim = ""


# ================= 动作开始 =================

func _set_state(s: S) -> void:
	state = s
	t = 0.0
	cur_anim = ""  # 同一个动作再次进入也要从头播
	hit_done = false
	if s == S.FREE:
		combo_i = 0


func _start_roll(dir: Vector3) -> void:
	roll_dir = dir if dir.length() > 0.1 else _fwd()
	roll_dir = roll_dir.normalized()
	_fx("kick", [global_position, -roll_dir, 1.0])  # 起滚蹬地一团
	kick_t = 0.07
	_sfx("cloth")
	_face(roll_dir, 1.0)
	_set_state(S.ROLL)


func _start_attack(i: int) -> void:
	_set_state(S.ATTACK)
	combo_i = i
	combo_queued = false
	_soft_lock()
	_sfx("swing_heavy" if i == COMBO.size() - 1 else "swing")


func _start_counter(kind: String) -> void:
	counter_kind = kind
	_set_state(S.COUNTER)
	dodge_counter_t = 0.0
	if kind != "recover":
		_sfx("swing_heavy")
	if kind == "phantom" and boss:
		_fx("wisp", [global_position])
		# 瞬移到 Boss 背后
		var bpos: Vector3 = boss.global_position
		var back: Vector3 = boss.global_basis.z
		back.y = 0.0
		back = back.normalized()
		# Boss 背后贴着根墙时，背后的点在墙里 / 墙外（主角会被闪进树根里、跑出画面）：
		# 绕着 Boss 往两侧找第一个还在场地里的点
		var lim := arena_radius - 1.0
		var p := bpos + back * 2.2
		for deg in [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0, 160.0, -160.0]:
			var c := bpos + back.rotated(Vector3.UP, deg_to_rad(deg)) * 2.2
			if Vector2(c.x, c.z).length() <= lim:
				p = c
				break
		global_position = Vector3(p.x, global_position.y, p.z)
		_clamp_to_arena()
		_fx("wisp", [global_position])
		_game_call("cam_quick_turn", [])
		counter_triggered.emit("瞬影斩！")
	_soft_lock(99.0)


func _start_plunge(is_counter: bool) -> void:
	plunge_is_counter = is_counter
	air_attack_used = true
	_sfx("swing_heavy" if is_counter else "swing")
	aerial_counter_t = 0.0
	_set_state(S.PLUNGE)
	if is_counter:
		counter_triggered.emit("落雷斩！")
		velocity.y = maxf(velocity.y, 3.0)
		var to_boss := _flat_to_boss()
		# 朝 Boss 方向飞，大致落在 Boss 身前
		var d := to_boss.normalized() * clampf((to_boss.length() - 1.2) / 0.55, 0.0, 14.0)
		velocity.x = d.x
		velocity.z = d.z
		_soft_lock(99.0)
	else:
		velocity.y = minf(velocity.y, 1.0)
		var f := _fwd() * 3.0
		velocity.x = f.x
		velocity.z = f.z


# ================= 受击（由 Boss 调用） =================

## 返回 "parried" / "blocked" / "dodged" / "hit" / "miss"
func receive_attack(dmg: float, parryable: bool, from_pos: Vector3) -> String:
	if state == S.DEAD:
		return "miss"
	if state == S.PARRY and t <= PARRY_WINDOW and parryable:
		_face(from_pos - global_position, 1.0)
		counter_kind = "cross"
		_set_state(S.COUNTER)
		counter_triggered.emit("弹反 · 十字斩！")
		_game_call("hitstop", [0.12, 0.35, 0.35])  # 弹反：顿一下接 0.35 倍慢放
		_game_call("cam_punch", [0.7])
		_game_call("shake", [0.3])
		var pp := _guard_point(from_pos)
		_fx("sparks", [pp, pp - global_position, Color(1.0, 0.85, 0.35), 2.2])
		_fx("ring", [global_position, 3.5, Color(1.0, 0.8, 0.3, 1.0), 0.4])
		_fx("vignette", [Color(1.0, 0.85, 0.4, 0.35), 0.35])
		_sfx("parry", pp)
		_sfx("swing_heavy")  # 弹反直接接十字斩
		return "parried"
	if state == S.ROLL and t <= ROLL_IFRAMES:
		if t <= PERFECT_DODGE:
			dodge_counter_t = DODGE_COUNTER_WINDOW
			counter_triggered.emit("完美闪避！按攻击 → 瞬影斩")
			_fx("wisp", [global_position])
			_sfx("dodge")
			_game_call("slowmo", [0.25, 0.55])
		return "dodged"
	if state == S.COUNTER or (state == S.PLUNGE and plunge_is_counter):
		return "miss"  # 反击动作中无敌

	var guard_broken := false
	if _is_guarding(from_pos):
		if parryable:
			hp = maxf(0.0, hp - dmg * (1.0 - BLOCK_REDUCTION))
			hp_changed.emit(hp, MAX_HP)
			flash = 0.2
			_game_call("hitstop", [0.1])
			_game_call("shake", [0.28])
			_game_call("cam_punch", [0.35])
			var bp := _guard_point(from_pos)
			_fx("sparks", [bp, bp - global_position, Color(1.0, 0.65, 0.3), 1.7])
			_fx("flash", [bp, Color(1.0, 0.85, 0.6, 0.9), 0.9])
			_sfx("block", bp)
			var push := global_position - from_pos
			push.y = 0.0
			velocity = push.normalized() * 6.5  # 被推开一段，脚下拖出两道土
			_fx("kick", [global_position + push.normalized() * 0.1, -push.normalized(), 1.0])
			_fx("dust", [global_position, 0.8, 0.5])
			shield_kick = 1.0
			shield_glow = 1.0
			if hp <= 0.0:
				_set_state(S.DEAD)
				died.emit()
				return "hit"
			if state == S.PARRY:  # 弹反窗口已过但还按着：直接进入举盾
				_set_state(S.BLOCK)
			cur_anim = ""  # 盾挨一下：举盾动作从头抖一下
			return "blocked"
		guard_broken = true
		shield_tilt = 1.0
		shield_kick = 1.0
		counter_triggered.emit("破防！")
		var gb := _guard_point(from_pos)
		_fx("sparks", [gb, Vector3.UP, Color(0.85, 0.9, 1.0), 2.0])
		_fx("flash", [gb, Color(1.0, 1.0, 1.0, 0.9), 2.0])
		_sfx("guard_break", gb)

	hp = maxf(0.0, hp - dmg)
	hp_changed.emit(hp, MAX_HP)
	flash = 1.0
	_game_call("shake", [0.25 + dmg * 0.01])
	_fx("blood", [global_position + Vector3.UP * 1.1, global_position - from_pos, 0.6 + dmg * 0.04])
	_fx("vignette", [Color(0.7, 0.0, 0.0, clampf(0.2 + dmg * 0.01, 0.0, 0.5)), 0.5])
	_sfx("body_hit")
	_sfx("player_death" if hp <= 0.0 else "hurt")
	var kb := global_position - from_pos
	kb.y = 0.0
	kb = kb.normalized() * 7.0
	velocity = Vector3(kb.x, 2.0, kb.z)
	if hp <= 0.0:
		_set_state(S.DEAD)
		died.emit()
	else:
		_set_state(S.HURT)
		hurt_time = GUARD_BREAK_TIME if guard_broken else 0.45
	return "hit"


## 重劈的地面震波：站在地上就被震晕一下（不掉血）。跳起来、翻滚无敌、反击动作中、已经在硬直里都不受影响
func receive_quake(dur: float) -> bool:
	if state in [S.DEAD, S.COUNTER, S.PLUNGE, S.HURT] or air_height() > 0.3 or not is_on_floor():
		return false
	if state == S.ROLL and t <= ROLL_IFRAMES:
		return false
	_set_state(S.HURT)
	hurt_time = dur
	velocity = Vector3.ZERO
	counter_triggered.emit("震晕！")
	_fx("dizzy", [self, dur, 2.05])
	_fx("vignette", [Color(0.35, 0.3, 0.25, 0.45), dur])
	_sfx("body_hit")
	return true


## 正在举盾（或弹反窗口过后还按着）且攻击来自正面
func _is_guarding(from_pos: Vector3) -> bool:
	var holding := state == S.BLOCK or (state == S.PARRY and t > PARRY_WINDOW and Input.is_action_pressed("parry"))
	if not holding:
		return false
	var to := from_pos - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return true
	return _fwd().angle_to(to.normalized()) <= deg_to_rad(BLOCK_ANGLE * 0.5)


## Boss 的低扫被跳过时调用
func notify_jumped_over() -> void:
	if state == S.DEAD or aerial_counter_t > 0.0:
		return
	aerial_counter_t = AERIAL_COUNTER_WINDOW
	counter_triggered.emit("跳过了！空中按攻击 → 落雷斩")


# ================= 工具函数 =================

func _melee(reach: float, angle_deg: float, dmg: float, stagger: float, stop: float) -> bool:
	if boss == null or boss.is_dead():
		return false
	var to := _flat_to_boss()
	var dist: float = to.length() - boss.body_radius
	if dist > reach:
		return false
	if angle_deg < 360.0 and to.length() > 0.5:
		if _fwd().angle_to(to.normalized()) > deg_to_rad(angle_deg * 0.5):
			return false
	boss.take_damage(dmg, stagger)
	_game_call("hitstop", [stop])
	# 火花打在 Boss 身体表面朝主角的一侧
	var back := -to.normalized()
	var hp_pos: Vector3 = boss.global_position + back * boss.body_radius * 0.8 + Vector3.UP * 1.3
	var big := dmg >= 20.0
	# 火花顺着挥剑方向、在挥剑平面里扇形喷出（剑尖最近一帧的位移 = 挥剑方向，剑身方向 × 挥剑方向 = 平面法线）
	# 用最近 5 帧的位移（顿帧时剑几乎不动，只看一帧会是 0）
	var swing := Vector3.ZERO
	if tip_hist.size() >= 2:
		swing = global_basis * (tip_hist[-1] - tip_hist[0])
	var spark_dir := back + Vector3.UP * 0.5
	var plane_n := Vector3.ZERO
	if swing.length() > 0.001 and blade_r:
		var blade_axis: Vector3 = blade_r.to_global(Vector3(0, 0, 0.9)) - blade_r.to_global(Vector3(0, 0, 0.2))
		spark_dir = swing.normalized() + back * 0.5  # 顺着挥剑方向，再往外偏（不然一半扎进 Boss 身体里看不见）
		plane_n = swing.cross(blade_axis)
	_fx("slash_spray", [hp_pos, spark_dir, 0.8 + dmg * 0.045, plane_n])
	_fx("blood", [hp_pos, back, 0.5 + dmg * 0.03])
	_sfx("hit", hp_pos)
	if big:
		_fx("slash_arc", [hp_pos, -back, 2.2, Color(1.0, 0.85, 0.5, 1.0), randf_range(-0.9, 0.9)])
		_sfx("hit_heavy", hp_pos)
	return true


## 盾的反馈：挨打往后一震再弹回、破防时被打偏到一边；弹反有效窗口里盾边亮一圈暖光，挡住时闪一下
func _animate_shield(delta: float) -> void:
	shield_kick = maxf(0.0, shield_kick - delta * 5.0)
	shield_glow = maxf(0.0, shield_glow - delta * 4.0)
	shield_tilt = maxf(0.0, shield_tilt - delta * 1.3)
	if shield_inner:
		var k := shield_kick * shield_kick
		var tl := sin(clampf(shield_tilt, 0.0, 1.0) * PI * 0.5)
		shield_inner.position = Vector3(tl * 0.12, 0.0, -k * 0.09)
		shield_inner.rotation = Vector3(-k * 0.35, tl * 1.1, tl * 0.4)
	if shield_rim_mat:
		var g := shield_glow * 3.0
		if state == S.PARRY and t <= PARRY_WINDOW:
			g = maxf(g, 2.2 * (1.0 - t / PARRY_WINDOW * 0.5))  # 弹反窗口：盾边亮着，窗口快结束时变暗
		shield_rim_mat.emission_energy_multiplier = g


## 砍到身边能被主角打碎的东西（陶罐）：reach = 距离（米），angle_deg = 身前扇形角度
func _hit_props(reach: float, angle_deg: float) -> void:
	for d in get_tree().get_nodes_in_group("destructible"):
		if d.is_broken or not d.player_breakable:
			continue
		var to: Vector3 = d.global_position - global_position
		to.y = 0.0
		if to.length() > reach + d.radius:
			continue
		if angle_deg < 360.0 and to.length() > 0.4 and _fwd().angle_to(to.normalized()) > deg_to_rad(angle_deg * 0.5):
			continue
		d.hit(999.0, global_position, "player")
		_sfx("hit", d.global_position + Vector3.UP * 0.3)


## 盾 / 弹反火花的位置：主角身前朝攻击来的方向
func _guard_point(from_pos: Vector3) -> Vector3:
	var d := from_pos - global_position
	d.y = 0.0
	return global_position + d.normalized() * 0.55 + Vector3.UP * 1.2


## pos 为 null = 主角自己的声音，不分方向
func _sfx(key: String, pos = null) -> void:
	var s := get_tree().get_first_node_in_group("sfx")
	if s:
		s.play(key, pos)


func _fx(method: String, args: Array) -> void:
	var f := get_tree().get_first_node_in_group("fx")
	if f:
		f.callv(method, args)


func _input_dir() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v.length() < 0.1:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(v.x, 0, v.y)
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var r := cam.global_basis.x
	r.y = 0.0
	r = r.normalized()
	return (r * v.x - f * v.y).limit_length(1.0)


func _fwd() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func _face(dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var target := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target, clampf(weight, 0.0, 1.0))


## 出招时如果 Boss 在附近就自动转向 Boss
func _soft_lock(max_dist: float = 7.0) -> void:
	var to := _flat_to_boss()
	if to.length() < max_dist:
		_face(to, 1.0)


func _flat_to_boss() -> Vector3:
	if boss == null:
		return Vector3.ZERO
	var bpos: Vector3 = boss.global_position
	var to := bpos - global_position
	to.y = 0.0
	return to


func _stop(delta: float, accel: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	velocity.z = move_toward(velocity.z, 0.0, accel * delta)


func _separate_from_boss() -> void:
	# 翻滚可以从 Boss 腿下穿过去；反击时主角站着不动，Boss 出招冲过来会压到主角身上（主角被 Boss 身体整个挡住），所以反击也要推开
	if boss == null or state == S.ROLL or state == S.PLUNGE:
		return
	if global_position.y - boss.global_position.y > 1.5:
		return
	var to := -_flat_to_boss()
	var min_d: float = boss.body_radius + 0.35
	if to.length() < min_d and to.length() > 0.001:
		var p := global_position + to.normalized() * (min_d - to.length())
		global_position = Vector3(p.x, global_position.y, p.z)


## 软边界：离边界 1.5 米内，往外走的速度逐渐被抵消；到了边界硬挡住
func _clamp_to_arena() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	var lim := arena_radius - 0.5
	var r := flat.length()
	if r > lim - 1.5 and r > 0.01:
		var out := flat / r
		var v := Vector2(velocity.x, velocity.z)
		var outward := v.dot(out)
		if outward > 0.0:
			v -= out * outward * clampf((r - (lim - 1.5)) / 1.5, 0.0, 1.0)
			velocity.x = v.x
			velocity.z = v.y
	if flat.length() > lim:
		flat = flat.normalized() * lim
		global_position = Vector3(flat.x, global_position.y, flat.y)


func _game_call(method: String, args: Array) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g:
		g.callv(method, args)


# ================= 占位动画（换骨骼动画时替换这里） =================

func _animate(delta: float) -> void:
	if anim:
		_animate_model(delta)
		return
	body_mat.emission = Color(1.0, 0.15, 0.1) * flash
	var w := clampf(delta * 18.0, 0.0, 1.0)
	var rr := Vector3(0.35, 0.25, 0.0)  # 右刀目标旋转
	var rl := Vector3(0.35, -0.25, 0.0)  # 左刀目标旋转
	var rig_rot := Vector3.ZERO
	var rig_y := 0.85
	var snap := false

	match state:
		S.FREE:
			if not is_on_floor():
				rr = Vector3(0.9, 0.6, 0.0)
				rl = Vector3(0.9, -0.6, 0.0)
		S.ROLL:
			rig_rot.x = -TAU * clampf(t / (ROLL_TIME * 0.8), 0.0, 1.0)
			rig_y = 0.55
			rr = Vector3(-0.6, 0.2, 0.0)
			rl = Vector3(-0.6, -0.2, 0.0)
		S.ATTACK:
			var c: Dictionary = COMBO[combo_i]
			var hit_t: float = c["hit"]
			var p := clampf((t - (hit_t - 0.1)) / 0.18, 0.0, 1.0)
			snap = true
			match combo_i:
				0:
					rr = Vector3(0.1, lerpf(1.7, -1.3, p), 0.0)
				1:
					rl = Vector3(0.1, lerpf(-1.7, 1.3, p), 0.0)
					rig_rot.y = -0.3
				2:
					rr = Vector3(lerpf(2.0, -0.5, p), 0.15, 0.0)
					rl = Vector3(lerpf(2.0, -0.5, p), -0.15, 0.0)
		S.PARRY, S.BLOCK:
			rr = Vector3(0.9, 0.75, 0.0)
			rl = Vector3(0.9, -0.75, 0.0)
			if state == S.PARRY and t <= PARRY_WINDOW:
				body_mat.emission = Color(0.9, 0.9, 1.0) * 0.5
		S.HURT:
			rig_rot.x = 0.35
		S.COUNTER:
			snap = true
			if counter_kind == "cross":
				var p := clampf((t - 0.18) / 0.15, 0.0, 1.0)
				rr = Vector3(0.6, lerpf(1.6, -1.6, p), 0.0)
				rl = Vector3(0.6, lerpf(-1.6, 1.6, p), 0.0)
			elif counter_kind == "phantom":
				rig_rot.y = -TAU * clampf(t / 0.25, 0.0, 1.0)
				rr = Vector3(0.0, -1.5, 0.0)
				rl = Vector3(0.0, 1.5, 0.0)
			else:
				rig_y = 0.6
				rr = Vector3(-1.3, 0.1, 0.0)
				rl = Vector3(-1.3, -0.1, 0.0)
		S.PLUNGE:
			rr = Vector3(-1.3, 0.1, 0.0)
			rl = Vector3(-1.3, -0.1, 0.0)
			rig_rot.x = -0.3
		S.DEAD:
			rig_rot.x = 1.45
			rig_y = 0.3

	if snap:
		blade_r.rotation = rr
		blade_l.rotation = rl
	else:
		blade_r.rotation = blade_r.rotation.lerp(rr, w)
		blade_l.rotation = blade_l.rotation.lerp(rl, w)
	if state == S.ROLL or (state == S.COUNTER and counter_kind == "phantom"):
		rig.rotation = rig_rot
	else:
		rig.rotation = rig.rotation.lerp(rig_rot, w)
	rig.position.y = lerpf(rig.position.y, rig_y, w)


func _animate_model(delta: float) -> void:
	var key := "idle"
	var rig_rot := Vector3.ZERO
	var rig_y := 0.85
	match state:
		S.FREE:
			if not is_on_floor():
				key = "jump" if velocity.y > 0.0 else "fall"
			elif Vector2(velocity.x, velocity.z).length() > 0.5:
				key = "run"
		S.ROLL:
			key = "roll"
			if not anim.has_animation(ANIM["roll"][0]):  # 替补的抱膝定格要靠整体前翻
				rig_rot.x = -TAU * clampf(t / (ROLL_TIME * 0.8), 0.0, 1.0)
				rig_y = 0.45
		S.ATTACK:
			key = "attack%d" % combo_i
		S.PARRY:
			key = "parry"
		S.BLOCK:
			key = "block"
		S.HURT:
			key = "hurt"
		S.COUNTER:
			key = counter_kind
			if counter_kind == "phantom":
				rig_rot.y = -TAU * clampf(t / 0.25, 0.0, 1.0)
		S.PLUNGE:
			key = "plunge"
		S.DEAD:
			key = "dead"
	_play(key)
	rig.rotation = rig_rot
	rig.position.y = lerpf(rig.position.y, rig_y, clampf(delta * 18.0, 0.0, 1.0))
	var c := Color(1.0, 0.15, 0.1) * flash * 0.6
	if state == S.PARRY and t <= PARRY_WINDOW:
		c = Color(0.9, 0.9, 1.0) * 0.15  # 弹反有效窗口：淡淡泛白
	body_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)


func _play(key: String) -> void:
	if key == cur_anim:
		return
	cur_anim = key
	var a: Array = ANIM[key]
	if not anim.has_animation(a[0]):
		a = ANIM_FALLBACK.get(key, a)
		if not anim.has_animation(a[0]):
			return
	anim.play(a[0], ANIM_BLEND, a[2])
	anim.seek(a[1], true)


## 离起跳 / 脚下地面多高（站着 = 0）
func air_height() -> float:
	return 0.0 if is_on_floor() else global_position.y - floor_y


func is_dead() -> bool:
	return state == S.DEAD


## 石台边的石头台阶一级级迈上去：顶到东西时往前方身体外一点向下打射线，一级 ≤ STEP_MAX 就抬上去。
## 不只认台阶本身——台阶和石台边缘的缓坡交在一起的地方，挡住人的常常是石台的面
const STEP_MAX := 0.35
func _step_up(want: Vector3) -> void:
	if want.length() < 0.5 or not is_on_wall() or not is_on_floor():
		return
	var ahead := global_position + want.normalized() * 0.5
	var q := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * (STEP_MAX + 0.1), ahead + Vector3.DOWN * 0.1, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y < 0.7:  # 落脚点要是平的（不是树干、拱门的侧面）
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.02 and rise <= STEP_MAX:
		global_position.y += rise + 0.02
		global_position += want.normalized() * 0.08
