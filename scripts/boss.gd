extends CharacterBody3D
## Boss「犀渠 · 枯林之主」（《山海经》异兽：状如牛，苍身，其音如婴儿，是食人）。
## 有骨骼模型时用 Mixamo 的 Maw J Laygo；没有就退回方块狼人占位。4 种节奏不同的攻击 + 50% 血进入二阶段（更快）。
##
##   claw   快速三连爪  —— 快、快、停顿、快（节奏型，可弹反）
##   slam   延迟重劈    —— 双爪高举憋很久才砸（反节奏骗翻滚，不可弹反，只能闪）
##   pounce 扑击       —— 远距离蹲伏后飞扑（拉近距离，可弹反 / 可完美闪避）
##   sweep  低身横扫    —— 360° 贴地横扫（不可弹反，跳起躲过 → 落雷斩）
##
## 招式全部是数据驱动（ATTACKS 字典）：改数字就能调节奏。
## 时间单位是“标准秒”，二阶段会整体乘 PHASE2_TIME_SCALE 加速。

signal died
signal hp_changed(hp: float, max_hp: float)
signal attack_started(label: String, parryable: bool)
signal phase_changed(phase: int)

enum S { IDLE, ATTACK, STAGGER, DEAD }

const MAX_HP := 320.0
const WALK_SPEED := 3.4
const CHARGE_SPEED := 10.0  # 开场从古树下冲过来的速度
const GRAVITY := 24.0
const POISE := 70.0                # 普通攻击累计多少伤害会让 Boss 小硬直
const PHASE2_TIME_SCALE := 0.8     # 二阶段招式时长 ×0.8

# hits: t 判定时刻 / kind 形状 / offset 判定中心在身前多远 / range|radius / angle / dmg / parry 可否弹反 / low 贴地(可跳过) / arm 哪只手
# steps: [开始, 结束, 前冲速度]
# tele: [显示地面预警的开始, 结束]
# track: 这个时刻之前 Boss 会转身追踪玩家
# quake: [半径, 秒] 砸地震波：没被砸中、但站在这个半径内的地上 → 震晕这么久（跳起来 / 翻滚无敌能躲）
const ATTACKS := {
	"claw": {
		"label": "快速三连爪", "dur": 1.9, "track": 1.05,
		"hits": [
			{"t": 0.45, "kind": "cone", "range": 3.2, "angle": 110.0, "dmg": 12.0, "parry": true, "arm": "r"},
			{"t": 0.75, "kind": "cone", "range": 3.2, "angle": 110.0, "dmg": 12.0, "parry": true, "arm": "l"},
			{"t": 1.3, "kind": "cone", "range": 3.5, "angle": 120.0, "dmg": 15.0, "parry": true, "arm": "r"},
		],
		"steps": [[0.3, 0.45, 6.0], [0.6, 0.75, 6.0], [1.1, 1.3, 8.0]],
	},
	"slam": {
		"label": "延迟重劈", "dur": 2.6, "track": 1.05,
		"hits": [
			{"t": 1.45, "kind": "circle", "offset": 2.3, "radius": 2.5, "dmg": 28.0, "parry": false, "arm": "both", "quake": [5.5, 0.7]},
		],
		"steps": [[1.25, 1.45, 9.0]],
		"tele": [0.55, 1.45],
	},
	"pounce": {
		"label": "扑击", "dur": 2.1, "track": 0.7,
		"leap": [0.7, 1.15],
		"hits": [
			{"t": 1.15, "kind": "circle", "offset": 0.9, "radius": 2.2, "dmg": 20.0, "parry": true, "arm": "both"},
		],
		"steps": [],
		"tele": [0.7, 1.15],
	},
	"sweep": {
		"label": "低身横扫", "dur": 1.7, "track": 0.4,
		"hits": [
			{"t": 0.65, "kind": "circle", "offset": 0.0, "radius": 4.3, "dmg": 16.0, "parry": false, "low": true, "arm": "r"},
		],
		"steps": [],
		"tele": [0.15, 0.65],
	},
}

var player
var arena_radius := 18.0
var body_radius := 0.9
var body_height := 3.2
var hp := MAX_HP
var state := S.IDLE
var charging := false  # 开场冲锋中
var _charge_fx_t := 0.0
var t := 0.0
var cooldown := 1.5
var atk_name := ""
var atk: Dictionary = {}
var hits_done := 0
var last_atk := ""
var forced_attack := ""            # 调试：数字键指定下一招
var stagger_time := 0.0
var recoil_t := 0.0                 # 被主角举盾挡住：手被弹开，动作停顿一下
var _recoil_seg := -2
var poise := 0.0
var phase := 1
var tm := 1.0
var strafe_sign := 1.0
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
var flash := 0.0
var anim_time := 0.0
var roaring := false               # 二阶段嚎叫硬直（播咆哮而不是受击）
var intro_hold := false            # 开场亮相：站着不动、盯着主角，不出招
var head_node: Node3D              # 头骨骨骼（开场亮相镜头对准它）
var model_root: Node3D
# 死亡：倒下 → 身体慢慢变暗成灰、裂缝透出余烬的橙光 → 像灰一样一粒粒散掉（按真实秒，从倒下那一刻算）
const ASH_DARK := [2.0, 4.6]   # 变暗变灰
const ASH_FADE := [4.6, 7.0]   # 散掉
var _death_t := 0.0
var _ash_mats: Array[BaseMaterial3D] = []
var _ash_colors: Array[Color] = []

# ================= 骨骼动画（Mixamo：模型 Maw J Laygo + Mutant 动作） =================
# 有 MODEL_PATH 就用骨骼模型，动作从 ANIM_DIR 里同名的 fbx（Without Skin，都是在 Mutant 上下载的）读；
# 没有就退回方块占位。Mixamo 的角色骨骼名都一样，换角色只改 MODEL_PATH / MODEL_SCALE。
const MODEL_PATH := "res://assets/mixamo/Maw J Laygo.fbx"
const ANIM_DIR := "res://assets/mixamo/"
const MODEL_SCALE := 2.7   # Maw 原高 2.4m → 约 6.4m（原来方块狼人的 2 倍，压迫感）
# 体型变大只影响外形和身体碰撞；ATTACKS 里的攻击范围 / 预警圈都没放大
const MODEL_BODY_RADIUS := 1.3
const MODEL_BODY_HEIGHT := 6.0
const EYE_OFFSET := Vector3(0.045, 0.09, 0.13)  # 眼睛相对头骨的位置（模型原始尺寸，单位米）
const EYE_SIZE := 0.018
const JUMP_LIFT := 0.6  # 两个跳劈的腾空高度打 6 折（放大 2 倍后跳得太高，会飞出镜头）
const ANIM_BLEND := 0.12
# 非攻击动作：[片段, 播放速度]
const MOVES := {
	"idle": ["Mutant Breathing Idle", 1.0],
	"run": ["Mutant Run", 0.5],       # 体型放大 2 倍后步子也大 2 倍，放慢播放免得脚底打滑
	"strafe": ["Mutant Walking", 0.7],
	"stagger": ["Hit Reaction", 1.6],
	"roar": ["Mutant Roaring", 1.8],
	"dead": ["Mutant Dying", 1.0],
}
# 招式动画分段：[招式内开始秒, 片段, 片段起点, 片段终点]，一段播到下一段开始（最后一段到 dur）。
# 段的终点 = 动画里出手最快的那一帧，并且刚好落在 ATTACKS 的 hits[].t 上 → 命中帧对齐。
# 时间轴跟着招式时间 t 走，所以二阶段加速时动画也一起加速。
const ATTACK_ANIMS := {
	"claw": [  # 右拳 → 左爪 → 停顿 → 右拳
		[0.0, "Mutant Punch", 0.0, 0.30], [0.45, "Mutant Punch", 0.30, 0.45],
		[0.6, "Mutant Swiping", 1.15, 1.30], [0.75, "Mutant Swiping", 1.30, 1.60],
		[1.05, "Mutant Punch", 0.0, 0.30], [1.3, "Mutant Punch", 0.30, 1.10],
	],
	"slam": [  # 蹲伏蓄力憋很久（慢放）→ 突然跳起砸地
		[0.0, "Jump Attack", 0.0, 0.40], [0.4, "Jump Attack", 0.40, 0.50],
		[1.05, "Jump Attack", 0.50, 1.60], [1.45, "Jump Attack", 1.60, 3.20],
	],
	"pounce": [  # 蹲伏 → 腾空（位移由代码按抛物线做）→ 落地砸
		[0.0, "Mutant Jump Attack", 0.0, 0.55], [0.7, "Mutant Jump Attack", 0.55, 1.60],
		[1.15, "Mutant Jump Attack", 1.60, 3.00],
	],
	"sweep": [
		[0.0, "Standing Melee Attack 360 Low", 0.2, 0.93], [0.65, "Standing Melee Attack 360 Low", 0.93, 2.40],
	],
}
var anim: AnimationPlayer
var flash_mat: StandardMaterial3D
var cur_move := ""
var cur_seg := -1
var trails := {}  # "l" / "r" → 爪光拖尾（fx_trail.gd）

var rig: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fur_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var telegraph: Decal  # 红色预警圈：投射到地面上（石台有高低差，平的圆片会浮空 / 陷进去）
const ArenaBuilder = preload("res://scripts/arena_builder.gd")


func _ready() -> void:
	_build_visual()  # 先建外形：骨骼模型会把 body_radius / body_height 改大
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = body_radius
	cap.height = body_height
	col.shape = cap
	col.position.y = body_height * 0.5
	add_child(col)
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.6  # 石台有坡，下坡时贴住地面
	_build_telegraph()


# ================= 外形（占位：方块 + 胶囊 + 一堆毛簇） =================

func _build_visual() -> void:
	eye_mat = StandardMaterial3D.new()  # 二阶段会改它的颜色，骨骼模型下不显示
	if ResourceLoader.exists(MODEL_PATH):
		_build_model()
		return
	fur_mat = StandardMaterial3D.new()
	fur_mat.albedo_color = Color(0.32, 0.29, 0.26)
	fur_mat.roughness = 1.0
	fur_mat.rim_enabled = true      # 边缘光，假装有毛的感觉
	fur_mat.rim = 0.6
	fur_mat.rim_tint = 0.3
	fur_mat.emission_enabled = true
	fur_mat.emission = Color.BLACK
	var fur_light := StandardMaterial3D.new()
	fur_light.albedo_color = Color(0.45, 0.42, 0.38)
	fur_light.roughness = 1.0
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.85, 0.3)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.8, 0.2)
	eye_mat.emission_energy_multiplier = 2.0
	var claw_mat := StandardMaterial3D.new()
	claw_mat.albedo_color = Color(0.85, 0.82, 0.75)

	rig = Node3D.new()
	add_child(rig)

	# 腿（逆关节狼腿，用两段斜胶囊凑）
	for side in [-1.0, 1.0]:
		var thigh := _mesh(_capsule(0.26, 1.2), fur_mat, Vector3(0.38 * side, 1.2, 0.1), Vector3(-0.5, 0, 0))
		rig.add_child(thigh)
		var shin := _mesh(_capsule(0.18, 1.0), fur_mat, Vector3(0.38 * side, 0.5, 0.25), Vector3(0.35, 0, 0))
		rig.add_child(shin)

	# 上半身：驼背
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 1.75, 0)
	torso.rotation.x = -0.35
	rig.add_child(torso)
	torso.add_child(_mesh(_capsule(0.7, 1.8), fur_mat, Vector3(0, 0.3, 0)))
	torso.add_child(_mesh(_sphere(0.85), fur_mat, Vector3(0, 0.75, -0.1), Vector3.ZERO, Vector3(1.15, 0.9, 1.0)))  # 胸 / 肩
	torso.add_child(_mesh(_sphere(0.5), fur_light, Vector3(0, 0.55, -0.55), Vector3.ZERO, Vector3(1.0, 1.2, 0.5)))  # 胸前浅色毛

	# 头
	var head := Node3D.new()
	head.position = Vector3(0, 1.35, -0.45)
	head.rotation.x = 0.35
	torso.add_child(head)
	head.add_child(_mesh(_box(Vector3(0.55, 0.5, 0.6)), fur_mat, Vector3.ZERO))
	head.add_child(_mesh(_box(Vector3(0.3, 0.25, 0.55)), fur_mat, Vector3(0, -0.08, -0.5)))  # 吻部
	head.add_child(_mesh(_box(Vector3(0.12, 0.1, 0.1)), claw_mat, Vector3(0, -0.02, -0.8)))  # 鼻子
	for side in [-1.0, 1.0]:
		var ear := _mesh(_prism(Vector3(0.18, 0.35, 0.1)), fur_mat, Vector3(0.18 * side, 0.4, 0.05), Vector3(0, 0, -0.2 * side))
		head.add_child(ear)
		head.add_child(_mesh(_sphere(0.05), eye_mat, Vector3(0.14 * side, 0.08, -0.3)))

	# 手臂：肩部枢轴（rotation.x 正 = 往前 / 往上抬）
	arm_l = _make_arm(torso, -1.0, fur_mat, claw_mat)
	arm_r = _make_arm(torso, 1.0, fur_mat, claw_mat)

	# 毛簇：在背部 / 肩膀上随机撒小三棱锥
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 46:
		var a := rng.randf_range(-PI * 0.9, PI * 0.9)
		var y := rng.randf_range(-0.3, 1.1)
		var r := 0.72 + rng.randf() * 0.12
		var tuft := _mesh(_prism(Vector3(0.22, 0.4, 0.08)), fur_mat if rng.randf() < 0.7 else fur_light,
			Vector3(sin(a) * r, y, cos(a) * r * 0.9),
			Vector3(rng.randf_range(0.6, 1.2), a, rng.randf_range(-0.3, 0.3)))
		torso.add_child(tuft)
	# 尾巴
	var tail := _mesh(_capsule(0.2, 1.3), fur_mat, Vector3(0, 1.0, 0.9), Vector3(1.1, 0, 0))
	rig.add_child(tail)


func _build_model() -> void:
	var model: Node3D = load(MODEL_PATH).instantiate()
	model_root = model
	model.rotation.y = PI  # Mixamo 朝 +Z，Boss 朝 -Z
	model.scale = Vector3.ONE * MODEL_SCALE
	add_child(model)
	body_radius = MODEL_BODY_RADIUS
	body_height = MODEL_BODY_HEIGHT
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var hips_y: float = sk.get_bone_rest(sk.find_bone("mixamorig_Hips")).origin.y
	# 每个动作是一个单独的 fbx，合进同一个 AnimationLibrary
	var lib := AnimationLibrary.new()
	var clips := {}
	for m in MOVES.values():
		clips[m[0]] = true
	for segs in ATTACK_ANIMS.values():
		for s in segs:
			clips[s[1]] = true
	for clip in clips:
		var path: String = ANIM_DIR + clip + ".fbx"
		if not ResourceLoader.exists(path):
			push_warning("缺少动作文件：" + path)
			continue
		var src: Node = load(path).instantiate()
		var src_ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
		var src_sk: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
		var src_hips_y: float = src_sk.get_bone_rest(src_sk.find_bone("mixamorig_Hips")).origin.y
		var a: Animation = src_ap.get_animation(src_ap.get_animation_list()[0]).duplicate()
		src.free()
		_strip_root_motion(a, hips_y / src_hips_y, JUMP_LIFT if clip in ["Jump Attack", "Mutant Jump Attack"] else 1.0)
		a.loop_mode = Animation.LOOP_LINEAR if clip in ["Mutant Breathing Idle", "Mutant Run", "Mutant Walking"] else Animation.LOOP_NONE
		lib.add_animation(clip, a)
	if anim.has_animation_library("boss"):
		anim.remove_animation_library("boss")
	anim.add_animation_library("boss", lib)
	# 受击闪白 / 二阶段泛红：叠一层加法发光材质。一定要关雾，否则雾色会叠到整个模型上，Boss 看起来像半透明的鬼影
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.disable_fog = true
	flash_mat.albedo_color = Color.BLACK
	for m in model.find_children("*", "MeshInstance3D", true, false):
		m.material_overlay = flash_mat
	_add_eyes(sk)
	for side in ["l", "r"]:
		var hand := BoneAttachment3D.new()
		hand.bone_name = "mixamorig_LeftHand" if side == "l" else "mixamorig_RightHand"
		sk.add_child(hand)
		var tr = preload("res://scripts/fx_trail.gd").new()
		tr.base_node = hand
		tr.base_offset = Vector3(0, 0.03, 0)
		tr.tip_offset = Vector3(0, 0.22, 0)  # 沿手指方向（模型原始尺寸，放大后约 0.6 米）
		tr.color = Color(1.0, 0.35, 0.15, 0.7)
		add_child(tr)
		trails[side] = tr


## 头部骨骼挂点（开场镜头用）。眼睛光球已去掉；eye_mat 仍保留，二阶段变色的代码不用改
func _add_eyes(sk: Skeleton3D) -> void:
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.75, 0.3)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.65, 0.2)
	eye_mat.emission_energy_multiplier = 4.0
	var head := BoneAttachment3D.new()
	head.bone_name = "mixamorig_Head"
	sk.add_child(head)
	head_node = head
	# 眼睛光球和头部补光按需求去掉了（2026-11-10）；head_node 仍给开场镜头用


## 去掉 Hips 的水平位移（走路 / 跳劈自带往前走），位移全部交给代码，保留上下起伏。
## 动作是按 Mutant 的腿长做的，换模型时按两者胯高的比例缩放上下位移，免得脚陷地 / 浮空。
func _strip_root_motion(a: Animation, y_ratio: float, lift: float = 1.0) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D or not str(a.track_get_path(i)).ends_with("Hips"):
			continue
		var p0: Vector3 = a.track_get_key_value(i, 0)
		for k in a.track_get_key_count(i):
			var p: Vector3 = a.track_get_key_value(i, k)
			var y := p0.y + maxf(0.0, p.y - p0.y) * lift + minf(0.0, p.y - p0.y)  # 只压低腾空，下蹲不变
			a.track_set_key_value(i, k, Vector3(p0.x, y * y_ratio, p0.z))


func _make_arm(torso: Node3D, side: float, mat: Material, claw_mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.95 * side, 0.85, -0.1)
	torso.add_child(pivot)
	pivot.add_child(_mesh(_capsule(0.22, 1.3), mat, Vector3(0, -0.6, 0)))
	pivot.add_child(_mesh(_capsule(0.18, 1.1), mat, Vector3(0, -1.4, -0.1)))
	for i in 3:
		var x: float = (i - 1) * 0.08
		pivot.add_child(_mesh(_box(Vector3(0.04, 0.35, 0.04)), claw_mat, Vector3(x, -2.05, -0.15), Vector3(-0.4, 0, 0)))
	return pivot


func _build_telegraph() -> void:
	# 一张圆形渐变贴图：中间淡、边缘一圈亮
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var glow := Image.create(256, 256, false, Image.FORMAT_RGBA8)  # 发光贴图不看 alpha，圈外要是黑的
	for y in 256:
		for x in 256:
			var d := Vector2(x - 127.5, y - 127.5).length() / 127.5
			var a := 0.0
			if d <= 1.0:
				a = lerpf(0.55, 1.0, smoothstep(0.75, 0.97, d)) * (1.0 - smoothstep(0.97, 1.0, d))
			img.set_pixel(x, y, Color(1, 1, 1, a))
			glow.set_pixel(x, y, Color(a, a, a, 1))
	telegraph = Decal.new()
	telegraph.texture_albedo = ImageTexture.create_from_image(img)
	telegraph.texture_emission = ImageTexture.create_from_image(glow)  # 发光：夜里也看得清
	telegraph.emission_energy = 1.5
	telegraph.modulate = Color(0.95, 0.12, 0.05, 0.4)
	telegraph.cull_mask = ArenaBuilder.GROUND_LAYER  # 只投到地面 / 石台上，不投到角色身上
	telegraph.upper_fade = 0.2
	telegraph.lower_fade = 0.2
	telegraph.top_level = true
	telegraph.visible = false
	add_child(telegraph)


# ================= 主循环 =================

func _physics_process(delta: float) -> void:
	anim_time += delta
	flash = maxf(0.0, flash - delta * 5.0)
	if recoil_t > 0.0:
		recoil_t -= delta
		if recoil_t <= 0.0 and anim and cur_seg == _recoil_seg:
			anim.speed_scale /= 0.15
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	match state:
		S.IDLE: _st_intro_hold(delta) if intro_hold else _st_idle(delta)
		S.ATTACK: _st_attack(delta)
		S.STAGGER: _st_stagger(delta)
		S.DEAD:
			_stop()
			_crumble(delta)

	var want := Vector3(velocity.x, 0.0, velocity.z)
	var before := global_position
	move_and_slide()
	_step_up(want, before, delta)
	# 身体挤进树冠：树抖、掉雪（小树撞断）——看起来是故意的，而不是模型互相穿过去
	for d in get_tree().get_nodes_in_group("destructible"):
		if d.kind == Destructible.Kind.TREE and not d.is_broken:
			var dd := Vector2(d.global_position.x - global_position.x, d.global_position.z - global_position.z).length()
			if dd < body_radius + d.canopy * 0.5:
				d.brush(global_position)
			d.push(global_position, body_radius, 0.3)  # 树往外弯，最多约 17°
	# 走路 / 冲刺撞上小树、灯：直接撞断
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c and c.get_parent() is Destructible:
			c.get_parent().hit(999.0, global_position, "contact")
	_clamp_to_arena()
	_animate(delta)
	_update_trails()


## 出手前 0.25 秒到命中后一点点，对应的手拖出爪光。双手砸地的招不拖（手是上下砸的，拖出来像两根光柱）
func _update_trails() -> void:
	if trails.is_empty():
		return
	var on := {"l": false, "r": false}
	if state == S.ATTACK:
		for h in atk["hits"]:
			if t >= h["t"] - 0.25 and t <= h["t"] + 0.08:
				var arm: String = h.get("arm", "r")
				if arm != "both":
					on[arm] = true
	for side in trails:
		if on[side] and not trails[side].active:  # 刚抬手：破风声
			_sfx("sweep" if atk_name == "sweep" else "claw")
		trails[side].active = on[side]
	if phase == 2:
		for side in trails:
			trails[side].color = Color(1.0, 0.15, 0.08, 0.85)


func _st_idle(delta: float) -> void:
	if player == null:
		return
	var to := _flat_to_player()
	var d := to.length()
	if charging:
		_st_charge(to, d, delta)
		return
	_face(to, delta * 6.0)
	var spd := WALK_SPEED * (1.2 if phase == 2 else 1.0)
	var move := Vector3.ZERO
	if d > 3.2:
		var dir := to.normalized()
		move = (dir + _steer_around(dir) * 1.5).normalized() * spd
	elif d > 0.1:
		# 近身时绕着玩家踱步
		move = to.normalized().cross(Vector3.UP) * strafe_sign * spd * 0.45
	velocity.x = move.x
	velocity.z = move.z

	if player.is_dead():
		return
	cooldown -= delta
	if cooldown <= 0.0:
		_start_attack(_choose_attack(d))


func _st_attack(delta: float) -> void:
	t += delta / tm * (0.15 if recoil_t > 0.0 else 1.0)
	var to := _flat_to_player()
	var track: float = atk["track"]
	if t < track:
		_face(to, delta * 8.0)

	# 前冲
	var fwd := _fwd()
	var step_speed := 0.0
	for s in atk["steps"]:
		if t >= s[0] and t < s[1]:
			step_speed = s[2]
	velocity.x = fwd.x * step_speed
	velocity.z = fwd.z * step_speed
	if recoil_t > 0.0:  # 挡住后往后一顿（每帧都会被上面重设，所以在这里加）
		velocity -= fwd * 2.5 * recoil_t / 0.22

	# 扑击：锁定落点，按抛物线飞过去
	if atk.has("leap"):
		var l0: float = atk["leap"][0]
		var l1: float = atk["leap"][1]
		if t < l0:
			leap_from = global_position
			leap_to = _compute_leap_target()
		elif t < l1:
			var p := (t - l0) / (l1 - l0)
			var pos := leap_from.lerp(leap_to, p)  # leap_to.y = 落点的地面高度
			global_position = pos
			velocity.x = 0.0
			velocity.z = 0.0

	_update_telegraph()

	# 判定
	var hits: Array = atk["hits"]
	while hits_done < hits.size() and t >= hits[hits_done]["t"]:
		_resolve_hit(hits[hits_done])
		hits_done += 1

	if t >= atk["dur"]:
		_end_attack()


## 开场亮相后：从古树下全速冲到玩家跟前，每一步震地扬尘，冲到 6 米内马上出手
func charge_in() -> void:
	charging = true
	_charge_fx_t = 0.0


func _st_charge(to: Vector3, d: float, delta: float) -> void:
	_face(to, delta * 8.0)
	var dir := to.normalized()
	velocity.x = dir.x * CHARGE_SPEED
	velocity.z = dir.z * CHARGE_SPEED
	if cur_move == "run":
		anim.speed_scale = 0.5 * CHARGE_SPEED / (WALK_SPEED * 1.6)  # 跑步动画跟上冲刺速度，脚不打滑
	_charge_fx_t -= delta
	if _charge_fx_t <= 0.0:
		_charge_fx_t = 0.4
		_fx("dust", [global_position, 2.2, 0.6])
		_game_call("shake", [0.3])
	if d < 6.0 or player.is_dead():
		charging = false
		cur_move = ""
		cooldown = 0.0


func _st_intro_hold(delta: float) -> void:
	_stop()
	_face(_flat_to_player(), delta * 6.0)


## 开场亮相：仰头咆哮（借二阶段嚎叫的动作和声音）
func intro_roar(dur: float) -> void:
	state = S.STAGGER
	t = 0.0
	stagger_time = dur
	roaring = true
	cur_move = ""
	_stop()
	_sfx("roar")
	_fx("dust", [global_position, 3.0, 0.8])


## 头的位置（没有骨骼模型时按身高估）
func head_pos() -> Vector3:
	if head_node:
		return head_node.global_position
	return global_position + Vector3.UP * body_height * 0.9


## 死亡化灰：把模型的材质各复制一份，改成抖动透明（ALPHA_HASH：透明度降下去时一粒粒消失，像灰散掉）
func _prepare_crumble() -> void:
	if model_root == null:
		return
	for m in model_root.find_children("*", "MeshInstance3D", true, false):
		if m.material_override != null:
			continue  # 眼睛（单独淡出）
		for i in m.get_surface_override_material_count():
			var mat: Material = m.get_active_material(i)
			if not mat is BaseMaterial3D:
				continue
			var d: BaseMaterial3D = mat.duplicate()
			d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			m.set_surface_override_material(i, d)
			_ash_mats.append(d)
			_ash_colors.append(d.albedo_color)


func _crumble(delta: float) -> void:
	_death_t += delta / maxf(Engine.time_scale, 0.01)
	if _ash_mats.is_empty():
		return
	var dk := smoothstep(ASH_DARK[0], ASH_DARK[1], _death_t)
	var fade := smoothstep(ASH_FADE[0], ASH_FADE[1], _death_t)
	for i in _ash_mats.size():
		var c: Color = _ash_colors[i].lerp(Color(0.16, 0.15, 0.14), dk * 0.9)
		c.a = _ash_colors[i].a * (1.0 - fade)
		_ash_mats[i].albedo_color = c
	eye_mat.emission_energy_multiplier = 4.0 * (1.0 - dk)
	if fade >= 1.0 and model_root.visible:
		model_root.visible = false


func _st_stagger(delta: float) -> void:
	t += delta
	_stop()
	if t >= stagger_time:
		state = S.IDLE
		cooldown = randf_range(0.2, 0.5)


# ================= 招式 =================

func _choose_attack(d: float) -> String:
	if forced_attack != "":
		var f := forced_attack
		forced_attack = ""
		return f
	var opts: Array
	if d < 4.0:
		opts = [["claw", 3.0], ["sweep", 2.0], ["slam", 2.0]]
	elif d < 9.0:
		opts = [["pounce", 3.0], ["slam", 1.0], ["claw", 1.0]]
	else:
		opts = [["pounce", 1.0]]
	if opts.size() > 1:
		opts = opts.filter(func(o): return o[0] != last_atk)
	var total := 0.0
	for o in opts:
		total += o[1]
	var r := randf() * total
	for o in opts:
		r -= o[1]
		if r <= 0.0:
			return o[0]
	return opts[0][0]


func _start_attack(name_: String) -> void:
	atk_name = name_
	atk = ATTACKS[name_]
	last_atk = name_
	hits_done = 0
	t = 0.0
	state = S.ATTACK
	cur_seg = -1
	var parryable: bool = atk["hits"][0]["parry"]
	attack_started.emit(atk["label"], parryable)
	match name_:
		"slam", "pounce": _sfx("growl")
		"claw": _sfx("growl_short")
		"sweep": _sfx("snarl")


func _end_attack() -> void:
	state = S.IDLE
	telegraph.visible = false
	strafe_sign = -1.0 if randf() < 0.5 else 1.0
	cooldown = randf_range(0.3, 0.9) if phase == 2 else randf_range(0.6, 1.4)


func _resolve_hit(h: Dictionary) -> void:
	if player == null:
		return
	var offset: float = h.get("offset", 0.0)
	var center := global_position + _fwd() * offset
	var pp: Vector3 = player.global_position
	var to := pp - center
	to.y = 0.0
	var hit := false
	var pr := 0.35  # 玩家半径
	if h["kind"] == "cone":
		var reach: float = h["range"]
		var angle: float = h["angle"]
		hit = to.length() <= reach + pr and (to.length() < 0.8 or _fwd().angle_to(to.normalized()) <= deg_to_rad(angle * 0.5))
	else:
		var radius: float = h["radius"]
		hit = to.length() <= radius + pr
	_game_call("shake", [0.2])
	_hit_fx(h, center)
	var shield: Node = _hit_destructibles(h, center)
	if not hit:
		if h.has("quake") and to.length() <= h["quake"][0]:
			player.receive_quake(h["quake"][1])
		return
	if shield and h["kind"] == "cone" or shield and h.get("low", false):
		return  # 爪击 / 低扫被挡在玩家和 Boss 之间的树 / 灯 / 拱门挡住了（它替玩家挨了这一下）
	if player.air_height() > 2.2:
		return  # 跳太高
	if h.get("low", false) and player.air_height() > 0.5:  # 跳离脚下地面 0.5 米以上 = 跳过了低扫
		player.notify_jumped_over()
		return
	var result: String = player.receive_attack(h["dmg"], h["parry"], global_position)
	if result == "parried":
		stagger(1.5)  # 顿帧 / 慢放由主角那边的弹反负责
	elif result == "blocked":
		block_recoil()


## 打在盾上：动作卡住一下（0.22 秒，动画几乎停住），身体往后一顿，像爪子被盾弹开
func block_recoil() -> void:
	if recoil_t > 0.0 or state != S.ATTACK:
		return
	recoil_t = 0.22
	_recoil_seg = cur_seg
	if anim:
		anim.speed_scale *= 0.15
	flash = maxf(flash, 0.4)


## 出手特效（不管打没打中）：爪击一道爪痕，砸地冲击环 + 裂地 + 尘土，低扫贴地一圈风尘
func _hit_fx(h: Dictionary, center: Vector3) -> void:
	var col := Color(1.0, 0.15, 0.08, 1.0) if phase == 2 else Color(1.0, 0.4, 0.15, 1.0)
	if h["kind"] == "cone":
		var tilt := 0.6 if h.get("arm", "r") == "r" else -0.6
		_fx("slash_arc", [global_position + _fwd() * 1.2 + Vector3.UP * 1.4, _fwd(), h["range"], col, tilt])
	elif h.get("low", false):
		_fx("ring", [center, h["radius"] + 0.5, Color(1.0, 0.85, 0.7, 0.8), 0.35])
		_fx("dust", [center, h["radius"], 0.8])
	elif h.has("quake"):
		# 重劈：大裂坑 + 两道震波 + 碎石崩飞 + 大尘圈
		var qr: float = h["quake"][0]
		_game_call("shake", [0.9])
		_sfx("slam", center)
		_sfx("slam", center, -4.0)
		_fx("cracks", [center, h["radius"] * 1.7, true])
		_fx("ring", [center, qr * 2.0, Color(1.0, 0.5, 0.2, 1.0), 0.45])
		_fx("slam_burst", [center, h["radius"]])
		get_tree().create_timer(0.15).timeout.connect(_fx.bind("ring", [center, qr * 2.4, Color(1.0, 0.75, 0.5, 0.7), 0.6]))
	else:
		var r: float = h["radius"]
		_game_call("shake", [0.5])
		_sfx("slam", center)
		_fx("ring", [center, r * 2.2, Color(1.0, 0.55, 0.25, 1.0), 0.5])
		_fx("cracks", [center, r * 0.9])
		_fx("dust", [center, r, 1.0])


func _sfx(key: String, pos = null, volume_add: float = 0.0) -> void:
	var s := get_tree().get_first_node_in_group("sfx")
	if s:
		s.play(key, pos if pos != null else global_position + Vector3.UP * 3.0, volume_add)


func _fx(method: String, args: Array) -> void:
	var f := get_tree().get_first_node_in_group("fx")
	if f:
		f.callv(method, args)


## 打到攻击范围里的树 / 灯 / 拱门；返回挡在 Boss 和玩家之间、还没碎的那一个（没有就是 null）
func _hit_destructibles(h: Dictionary, center: Vector3) -> Node:
	var reach: float = h.get("range", h.get("radius", 0.0))
	var shield: Node = null
	var pp: Vector3 = player.global_position if player else global_position
	var a := Vector2(global_position.x, global_position.z)
	var b := Vector2(pp.x, pp.z)
	for d in get_tree().get_nodes_in_group("destructible"):
		if d.is_broken:
			continue
		var to: Vector3 = d.global_position - center
		to.y = 0.0
		var inside := false
		if h["kind"] == "cone":
			inside = to.length() <= reach + d.radius and (to.length() < 0.8 + d.radius or _fwd().angle_to(to.normalized()) <= deg_to_rad(h["angle"] * 0.5))
		else:
			inside = to.length() <= reach + d.radius
		if not inside:
			continue
		# 先判断它是不是挡在 Boss 和玩家中间（树干和线段的距离 < 树干半径 + 0.3）
		var q := Vector2(d.global_position.x, d.global_position.z)
		var ab := b - a
		var tt := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if tt > 0.05 and tt < 0.95 and q.distance_to(a + ab * tt) < d.radius + 0.3:
			shield = d
		d.hit(h["dmg"], global_position, atk_name)
	return shield


## 往前走时会撞到的大障碍（撞不断的树 / 拱门）：返回绕开的侧向，没有就是 0
## 顶到石台边的石头小台子（组 ledge）时直接迈上去：往前方身体边缘外一点向下打射线，台阶 ≤ STEP_MAX 就抬高
const STEP_MAX := 1.3  # 石台边的台阶最高 ~1 米
func _step_up(want: Vector3, before: Vector3, delta: float) -> void:
	if want.length() < 0.5:
		return
	# 顶住了：撞墙，或者这一帧几乎没往前走（卡在石块的棱上时不一定算「撞墙」）
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if not is_on_wall() and moved > want.length() * delta * 0.3:
		return
	var ahead := global_position + want.normalized() * (body_radius + 0.25)
	var q := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * (STEP_MAX + 0.2), ahead + Vector3.DOWN * 0.2, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit.collider as Node).is_in_group("ledge"):
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.05 and rise <= STEP_MAX:
		global_position.y += rise + 0.02
		global_position += want.normalized() * 0.15


func _steer_around(dir: Vector3) -> Vector3:
	var push := Vector3.ZERO
	for d in get_tree().get_nodes_in_group("destructible"):
		if d.is_broken or d.contact_breakable or d.kind == Destructible.Kind.ARCH:
			continue  # 拱门中间是空的（约 6 米宽），不用整体绕开
		var to: Vector3 = d.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var clear: float = body_radius + d.radius + 1.0
		if dist > clear + 3.0 or to.dot(dir) <= 0.0:
			continue
		var side := dir.cross(Vector3.UP)
		if side.dot(to) > 0.0:
			side = -side  # 往障碍物的另一侧绕
		push += side * clampf((clear + 3.0 - dist) / 3.0, 0.0, 1.0)
	return push


func _compute_leap_target() -> Vector3:
	var pp: Vector3 = player.global_position
	var to := pp - global_position
	to.y = 0.0
	var dist := clampf(to.length() - (body_radius + 0.3), 0.0, 12.0)  # 落在玩家身前，不压到玩家身上
	var target := global_position + to.normalized() * dist
	var flat := Vector2(target.x, target.z)
	if flat.length() > arena_radius - 1.0:
		flat = flat.normalized() * (arena_radius - 1.0)
	return Vector3(flat.x, ArenaBuilder.ground_height(flat.x, flat.y), flat.y)


func _update_telegraph() -> void:
	if not atk.has("tele"):
		telegraph.visible = false
		return
	var t0: float = atk["tele"][0]
	var t1: float = atk["tele"][1]
	if t < t0 or t > t1:
		telegraph.visible = false
		return
	var h: Dictionary = atk["hits"][0]
	var offset: float = h.get("offset", 0.0)
	var radius: float = h["radius"]
	var base := global_position
	if atk.has("leap"):
		base = leap_to
	# 预测前冲后的位置
	var remaining := 0.0
	for s in atk["steps"]:
		var a: float = maxf(t, s[0])
		var b: float = s[1]
		if b > a:
			remaining += (b - a) * s[2]
	var c := base + _fwd() * (offset + remaining)
	telegraph.visible = true
	telegraph.global_position = Vector3(c.x, ArenaBuilder.ground_height(c.x, c.z), c.z)
	telegraph.size = Vector3(radius * 2.0, 6.0, radius * 2.0)  # 上下各 3 米的投射范围，盖住石台的高低差
	var p := (t - t0) / maxf(0.01, t1 - t0)
	telegraph.modulate = Color(0.95, 0.12, 0.05, lerpf(0.3, 0.85, p))


# ================= 受击 =================

func take_damage(dmg: float, stagger_dur: float = 0.0) -> void:
	if state == S.DEAD:
		return
	hp = maxf(0.0, hp - dmg)
	flash = 1.0
	hp_changed.emit(hp, MAX_HP)
	if hp <= 0.0:
		_die()
		return
	if phase == 1 and hp <= MAX_HP * 0.5:
		phase = 2
		tm = PHASE2_TIME_SCALE
		eye_mat.emission = Color(1.0, 0.1, 0.05)
		eye_mat.albedo_color = Color(1.0, 0.2, 0.1)
		phase_changed.emit(2)
		stagger(1.0)  # 嚎叫硬直
		roaring = true
		_game_call("shake", [0.7])
		_fx("ring", [global_position, 12.0, Color(1.0, 0.1, 0.05, 1.0), 0.9])
		_fx("dust", [global_position, 4.0, 1.0])
		_fx("vignette", [Color(0.6, 0.0, 0.0, 0.55), 1.0])
		_sfx("roar")
		_sfx("roar_cry")
		return
	if stagger_dur > 0.0:
		stagger(stagger_dur)
	else:
		poise += dmg
		if poise >= POISE and state != S.STAGGER:
			poise = 0.0
			stagger(0.8)


func stagger(duration: float) -> void:
	if state == S.DEAD:
		return
	state = S.STAGGER
	t = 0.0
	stagger_time = duration
	roaring = false
	cur_move = ""  # 连续硬直也从头播受击
	telegraph.visible = false
	_stop()


func is_dead() -> bool:
	return state == S.DEAD


func _die() -> void:
	state = S.DEAD
	t = 0.0
	telegraph.visible = false
	for side in trails:
		trails[side].active = false
	_fx("ashes", [global_position, body_height, ASH_FADE[1]])
	_prepare_crumble()
	_sfx("boss_death")
	died.emit()


# ================= 工具 =================

func _flat_to_player() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var pp: Vector3 = player.global_position
	var to := pp - global_position
	to.y = 0.0
	return to


func _fwd() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func _face(dir: Vector3, weight: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _clamp_to_arena() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	var lim := arena_radius - 1.0
	if flat.length() > lim:
		flat = flat.normalized() * lim
		global_position = Vector3(flat.x, global_position.y, flat.y)


func _game_call(method: String, args: Array) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g:
		g.callv(method, args)


func _mesh(m: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


# ================= 占位动画（换骨骼动画时替换这里） =================

func _animate(delta: float) -> void:
	if anim:
		_animate_model()
		return
	fur_mat.emission = Color(1, 1, 1) * flash * 0.4
	var w := clampf(delta * 14.0, 0.0, 1.0)
	var al := 0.35     # 左臂抬起角度
	var ar := 0.35     # 右臂
	var lean := 0.0    # 整体前倾(负) / 后仰(正)
	var crouch := 0.0  # 下蹲
	var spin := 0.0    # 绕 Y 自转（横扫）
	var lift := 0.0    # 扑击腾空高度
	var fast := false

	match state:
		S.IDLE:
			crouch = sin(anim_time * 3.0) * 0.04  # 呼吸
			var v := Vector2(velocity.x, velocity.z).length()
			if v > 0.5:
				crouch += absf(sin(anim_time * 9.0)) * 0.08
				al = 0.35 + sin(anim_time * 9.0) * 0.4
				ar = 0.35 - sin(anim_time * 9.0) * 0.4
		S.ATTACK:
			fast = true
			match atk_name:
				"claw":
					var hits: Array = atk["hits"]
					for i in hits.size():
						var ht: float = hits[i]["t"]
						var target := 0.35
						if t >= ht - 0.28 and t < ht:
							target = 2.7   # 抬手
						elif t >= ht and t < ht + 0.18:
							target = -0.4  # 挥下
						if hits[i]["arm"] == "r":
							ar = target if target != 0.35 else ar
						else:
							al = target if target != 0.35 else al
					lean = -0.15
				"slam":
					var ht: float = atk["hits"][0]["t"]
					if t < ht:
						var p := clampf(t / 0.6, 0.0, 1.0)
						al = lerpf(0.35, 3.0, p)
						ar = al
						lean = 0.25 * p           # 后仰蓄力
						crouch = -0.05 * sin(t * 30.0) if t > 0.9 else 0.0  # 憋力颤抖
					else:
						al = -0.3
						ar = -0.3
						lean = -0.6
						crouch = -0.4
				"pounce":
					var l0: float = atk["leap"][0]
					var l1: float = atk["leap"][1]
					if t < l0:
						crouch = -0.6
						lean = -0.6
						al = -0.4
						ar = -0.4
					elif t < l1:
						var p := (t - l0) / (l1 - l0)
						lift = sin(p * PI) * 2.6
						al = 1.7
						ar = 1.7
						lean = -0.4
					else:
						crouch = -0.35
						al = 0.9
						ar = 0.9
				"sweep":
					var ht: float = atk["hits"][0]["t"]
					crouch = -0.7
					lean = -0.4
					if t < ht - 0.1:
						spin = 0.9
						ar = 1.2
					elif t < ht + 0.15:
						spin = 0.9 - TAU * clampf((t - (ht - 0.1)) / 0.25, 0.0, 1.0)
						ar = 1.5
						al = 1.0
					else:
						crouch = -0.3
		S.STAGGER:
			lean = 0.45
			crouch = -0.2
			al = -0.1
			ar = -0.1
		S.DEAD:
			lean = 1.5
			crouch = -0.9

	var sw := clampf(delta * 22.0, 0.0, 1.0) if fast else w
	arm_l.rotation.x = lerpf(arm_l.rotation.x, al, sw)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, sw)
	rig.rotation.x = lerpf(rig.rotation.x, lean, w)
	rig.rotation.y = spin if state == S.ATTACK and atk_name == "sweep" else lerpf(rig.rotation.y, 0.0, w)
	rig.position.y = lerpf(rig.position.y, crouch + lift, clampf(delta * 20.0, 0.0, 1.0))


func _animate_model() -> void:
	var c := Color(1, 1, 1) * flash * 0.35
	if phase == 2:
		c += Color(0.12, 0.01, 0.0)  # 二阶段身上一层淡淡的红
	if state == S.DEAD:
		# 变灰时身上透出一明一暗的余烬橙光
		var dk := smoothstep(ASH_DARK[0], ASH_DARK[1], _death_t)
		var fade := smoothstep(ASH_FADE[0], ASH_FADE[1], _death_t)
		c = Color(0.22, 0.05, 0.0) * dk * (0.6 + 0.4 * sin(_death_t * 5.0)) + Color(1, 1, 1) * flash * 0.35
		# 叠加层也跟着一粒粒消失，不然身体散掉后还剩一个发光的影子
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		flash_mat.albedo_color = Color(c.r, c.g, c.b, 1.0 - fade)
	else:
		flash_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
	if state == S.ATTACK and ATTACK_ANIMS.has(atk_name):
		_play_segment()
		return
	var key := "idle"
	match state:
		S.IDLE:
			var v := Vector2(velocity.x, velocity.z).length()
			if v > 0.5:
				key = "run" if v > WALK_SPEED * 0.8 else "strafe"
		S.STAGGER:
			key = "roar" if roaring else "stagger"
		S.DEAD:
			key = "dead"
	_play_move(key)


func _play_move(key: String) -> void:
	if key == cur_move:
		return
	cur_move = key
	cur_seg = -1
	var m: Array = MOVES[key]
	var clip: String = "boss/" + m[0]
	if not anim.has_animation(clip):
		return
	anim.speed_scale = m[1]
	anim.play(clip, ANIM_BLEND)


## 招式动画：按招式时间 t 找到当前段，段内播放速度 = 片段长度 / 段时长
func _play_segment() -> void:
	var segs: Array = ATTACK_ANIMS[atk_name]
	var i := 0
	while i + 1 < segs.size() and t >= segs[i + 1][0]:
		i += 1
	if i == cur_seg:
		return
	var s: Array = segs[i]
	var end_t: float = segs[i + 1][0] if i + 1 < segs.size() else atk["dur"]
	var clip: String = "boss/" + s[1]
	if not anim.has_animation(clip):
		return
	# 和上一段首尾相接就接着播，否则切过去（带混合）
	var continues: bool = cur_seg >= 0 and segs[cur_seg][1] == s[1] and is_equal_approx(segs[cur_seg][3], s[2])
	if not continues:
		anim.play(clip, ANIM_BLEND)
		anim.seek(s[2], true)
	anim.speed_scale = (s[3] - s[2]) / maxf(0.01, end_t - s[0]) / tm
	if recoil_t > 0.0:  # 挡住的那一下常常正好落在段的分界上：新段也要慢下来
		anim.speed_scale *= 0.15
		_recoil_seg = i
	cur_seg = i
	cur_move = ""
