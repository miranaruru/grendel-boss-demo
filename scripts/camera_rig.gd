extends Camera3D
## 锁定镜头：始终在玩家身后、看向玩家与 Boss 之间。没有鼠标视角，专注打斗。
## 镜头全部按真实时间走：慢动作 / 顿帧时镜头照常跟，不会拖。

var player
var boss
var shake := 0.0
var dir := Vector3(0, 0, 1)  # 从 Boss 指向玩家的水平方向
const BASE_FOV := 62.0
const DISTANCE := 3.8  # 贴近主角（参考魂类 Boss 战：人物占画面很大）
const HEIGHT := 1.3  # 主角背部高度，往上仰看 Boss（更有压迫感）
const LOOK_HEIGHT := 1.9
const LOOK_TO_BOSS := 0.35  # 看向点在玩家→Boss 连线上的位置
# 弹性构图：主角默认在画面左侧（镜头往主角右边挪），左右跑时主角在画面里自由移动，停下后慢慢回到左边
const FRAME_X := -1.3  # 主角默认的横向位置（米，负 = 左）
const FRAME_MIN := -1.9  # 最左
const FRAME_MAX := 1.2  # 最右（往右跑会跑到画面右侧）
const FRAME_RETURN := 0.7  # 停下后每秒回位多少米
# 近身压迫镜头：离 Boss 越近，镜头越贴近、越低、越往上仰，Boss 压满画面上方
const CLOSE_FAR := 10.0  # 离 Boss 这么远开始过渡
const CLOSE_NEAR := 4.0  # 这么近时完全是近身镜头
const CLOSE_DISTANCE := 3.4
const CLOSE_HEIGHT := 1.1
const CLOSE_LOOK_HEIGHT := 2.4
const CLOSE_LOOK_TO_BOSS := 0.25  # 看向点在玩家→Boss 连线上的位置（平时 LOOK_TO_BOSS）
const CLOSE_FOV := 64.0  # 近身时广角一点，透视更强，Boss 更显得压过来
# 二阶段嚎叫：拉远抬高，把整只犀渠框进来
const WIDE_DISTANCE := 12.0
const WIDE_HEIGHT := 3.0  # 放低仰拍，显得 Boss 更高大
const PULL_HOLD := 0.3  # 被挡住拉近以后，至少停 0.3 秒再慢慢退回去（不然擦着障碍物边缘时一拉一放来回抖）
var _hold := 0.0
var arena_limit := 0.0  # > 0：镜头水平方向不出这个半径（方案 B 的坑：再往外就是根墙，镜头会钻进树根里）
var _swing_side := 0.0  # 贴墙时镜头绕主角转向哪一侧；转开以后一直守着这一侧，回到坑里才重新选（不然贴墙横跑时镜头左右翻）
var _close := 0.0  # 近身程度 0~1（平滑过）
var _punch := 0.0  # 弹反 / 反击打中时往里冲一下
var _turn_t := 0.0  # 瞬影斩以后快速转身的剩余时间
var _wide_t := 0.0
var _wide := 0.0
var _death := false
var _death_side := Vector3.ZERO
var _death_t := 0.0
var _last_us := 0
var _frame_x := FRAME_X
var _last_pp := Vector3.ZERO
# 开场亮相：从主角肩后低机位推到 Boss 脸前仰拍、定格，再飞回主角身后
const INTRO_PUSH := 2.8  # 推近用时
const INTRO_HOLD := 3.9  # 定格到这一刻
const INTRO_LEN := 5.0  # 飞回主角身后，到这一刻结束
var _intro_t := -1.0  # < 0 = 没在播


func intro() -> void:
	_intro_t = 0.0


## 跳过：直接进入「飞回主角身后」那一段
func intro_skip() -> void:
	if _intro_t >= 0.0 and _intro_t < INTRO_HOLD:
		_intro_t = INTRO_HOLD


func punch(amount: float) -> void:
	_punch = maxf(_punch, amount)


func quick_turn(dur: float) -> void:
	_turn_t = dur


func frame_boss(dur: float) -> void:
	_wide_t = dur


## Boss 倒下：退到它侧面（离现在镜头近的那一侧）看它倒下
func death_cam() -> void:
	_death = true
	var side := dir.cross(Vector3.UP).normalized()
	if (global_position - boss.global_position).dot(side) < 0.0:
		side = -side
	_death_side = (side * 0.85 + dir * 0.5).normalized()


func _ready() -> void:
	fov = BASE_FOV
	current = true
	if player:
		var pp: Vector3 = player.global_position
		global_position = pp + dir * DISTANCE + Vector3.UP * HEIGHT


## 开场亮相的镜头：target / look 是平时镜头该在的位置，最后一段往那里飞
func _intro_shot(target: Vector3, look: Vector3, rd: float) -> void:
	var head: Vector3 = boss.head_pos()
	var fwd: Vector3 = boss.global_position.direction_to(player.global_position)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var k := smoothstep(0.0, 1.0, minf(_intro_t / INTRO_PUSH, 1.0))
	k = 1.0 - pow(1.0 - k, 2.0)  # 前快后慢，最后慢慢贴上去
	var drift := maxf(0.0, _intro_t - INTRO_PUSH) * 0.12  # 定格时还在极慢地往前蹭
	var pos := head + fwd * (lerpf(12.0, 3.4, k) - drift) + side * lerpf(2.6, 0.7, k) + Vector3.UP * lerpf(-3.0, -1.7, k)
	var aim := head + Vector3.UP * lerpf(-1.2, -0.15, k)
	var f := lerpf(52.0, 36.0, k)
	if _intro_t > INTRO_HOLD:
		var b := smoothstep(INTRO_HOLD, INTRO_LEN, _intro_t)
		pos = pos.lerp(target, b)
		aim = aim.lerp(look, b)
		f = lerpf(f, BASE_FOV, b)
	global_position = pos
	fov = f
	look_at(aim, Vector3.UP)
	shake = maxf(0.0, shake - rd * 2.5)
	h_offset = randf_range(-1.0, 1.0) * shake * 0.12
	v_offset = randf_range(-1.0, 1.0) * shake * 0.12


## 挡在玩家和镜头之间（或者镜头就在树冠里）的树、石灯变半透明
func _boss_blocks(cam_pos: Vector3, pp: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam_pos, pp + Vector3.UP * 1.0, 4)  # 第 3 层：Boss
	if space.intersect_ray(q).is_empty():
		return false
	q.to = pp + Vector3.UP * 1.7
	return not space.intersect_ray(q).is_empty()


## 俯视看：镜头位置 c 到主角这条线有没有穿过 Boss 的身体（贴墙转镜头时不选被 Boss 挡住的位置）
func _boss_between(c: Vector3, pp: Vector3, bp: Vector3) -> bool:
	var a := Vector2(c.x, c.z)
	var ab := Vector2(pp.x, pp.z) - a
	var q := Vector2(bp.x, bp.z)
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return q.distance_to(a + ab * t) < boss.body_radius


func _fade_trees(from: Vector3, cam_pos: Vector3) -> void:
	var a := Vector2(from.x, from.z)
	var b := Vector2(cam_pos.x, cam_pos.z)
	var ab := b - a
	for d in get_tree().get_nodes_in_group("destructible"):
		if d.kind == Destructible.Kind.ARCH or d.is_broken:
			continue
		var lamp: bool = d.kind == Destructible.Kind.LAMP
		var q := Vector2(d.global_position.x, d.global_position.z)
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var blocking: bool = t > 0.05 and q.distance_to(a + ab * t) < d.radius + (0.6 if lamp else 1.8)
		var cam_inside: bool = not lamp and q.distance_to(b) < d.canopy * 0.8 and cam_pos.y < d.global_position.y + d.height + 1.0  # 镜头在树冠里
		if blocking or cam_inside:
			d.fade_target = 0.75


func _process(delta: float) -> void:
	if player == null or boss == null:
		return
	# 真实时间：用系统时钟算（顿帧在同一帧里改 time_scale 时，delta / time_scale 会算出一个假的大值，镜头会跳一下）
	var now := Time.get_ticks_usec()
	var raw := (now - _last_us) / 1000000.0 if _last_us > 0 else delta
	var rd := clampf(raw, 0.0, 0.1)
	_last_us = now
	var pp: Vector3 = player.global_position
	var bp: Vector3 = boss.global_position
	var to_p := pp - bp
	to_p.y = 0.0
	_turn_t -= rd
	# Boss 挡住了主角（翻滚穿过 Boss 腿下、被 Boss 贴身绕到背后）：像瞬影斩后那样快速转到主角身后
	if to_p.length() > boss.body_radius + 0.2 and _boss_blocks(global_position, pp):
		_turn_t = maxf(_turn_t, 0.12)
	if to_p.length() > 1.0:
		# 按角度转（瞬影斩后要转 180°，直接插值向量会穿过零点）
		var a := lerp_angle(atan2(dir.x, dir.z), atan2(to_p.x, to_p.z), clampf(rd * (14.0 if _turn_t > 0.0 else 3.0), 0.0, 1.0))
		dir = Vector3(sin(a), 0.0, cos(a))
	_close = lerpf(_close, smoothstep(CLOSE_FAR, CLOSE_NEAR, to_p.length()), clampf(rd * 2.5, 0.0, 1.0))
	_wide_t -= rd
	_wide = move_toward(_wide, 1.0 if _wide_t > 0.0 else 0.0, rd * 1.8)
	var w := smoothstep(0.0, 1.0, _wide)
	var dist := lerpf(lerpf(DISTANCE, CLOSE_DISTANCE, _close), WIDE_DISTANCE, w)
	var height := lerpf(lerpf(HEIGHT, CLOSE_HEIGHT, _close), WIDE_HEIGHT, w)
	var look_k := lerpf(lerpf(LOOK_TO_BOSS, CLOSE_LOOK_TO_BOSS, _close), 0.5, w)
	var look_h := lerpf(lerpf(LOOK_HEIGHT, CLOSE_LOOK_HEIGHT, _close), 2.6, w)
	_punch = maxf(0.0, _punch - rd * 1.3)  # 约 0.8 秒退回，盖住整段慢放
	dist *= 1.0 - 0.25 * _punch
	fov = lerpf(BASE_FOV, CLOSE_FOV, _close * (1.0 - w)) - 12.0 * _punch
	# 弹性构图：主角横着走多少，在画面里就先偏多少（镜头不马上跟），超出范围才推着镜头走；不动时慢慢回到左边
	var right := Vector3.UP.cross(dir)  # 画面的右方向
	var dl := (pp - _last_pp).dot(right) if _last_pp != Vector3.ZERO else 0.0
	_last_pp = pp
	if absf(dl) > 1.5:  # 瞬移（瞬影斩）：直接回到默认构图
		_frame_x = FRAME_X
	else:
		_frame_x = clampf(_frame_x + dl, FRAME_MIN, FRAME_MAX)
		if absf(dl) < rd * 1.0:  # 基本没横着走
			_frame_x = move_toward(_frame_x, FRAME_X, rd * FRAME_RETURN)
	# 镜头和看向点一起平移到主角右边（朝向不变）→ 近处的主角偏到画面左边，远处的 Boss 只偏一点、基本在中间；二阶段拉远时回到居中
	var shift := right * (-_frame_x * (1.0 - w))
	var target := pp + dir * dist + Vector3.UP * height + shift
	var look := pp.lerp(bp, look_k) + Vector3.UP * look_h + shift
	var from := pp + Vector3.UP * 1.6
	var follow := 16.0 if _turn_t > 0.0 else 7.0
	if _intro_t >= 0.0:
		_intro_t += raw  # 不截断：要和 main.gd 里开场的计时器对齐
		if _intro_t < INTRO_LEN:
			_intro_shot(target, look, rd)
			return
		_intro_t = -1.0
	if _death:
		# 先在侧面 11 米看它倒下，再慢慢推近、略往下看倒在地上的身体（身体中间到头之间），看它化成灰
		_death_t += raw
		var z := smoothstep(0.6, 4.5, _death_t)
		var head: Vector3 = boss.head_pos()
		look = (bp + Vector3.UP * 2.4).lerp(bp.lerp(head, 0.6) + Vector3.UP * 0.4, z)
		target = look + _death_side * lerpf(11.0, 6.5, z) + Vector3.UP * lerpf(1.1, 2.8, z)
		target.y = maxf(target.y, bp.y + 1.2)
		from = look
		follow = 2.5
		fov = lerpf(BASE_FOV, 44.0, z)
	# 贴着坑边打时，镜头本该在根墙里：把它收回坑里、同时抬高往下看，主角始终在画面里
	if arena_limit > 0.0 and not _death:
		var hf := Vector2(target.x, target.z)
		if hf.length() > arena_limit:
			# 先试着绕主角往侧面转（先转向镜头现在所在的那一侧，不左右跳）：侧面看主角和 Boss，比从头顶往下看好
			# 绕主角转的起点：不带弹性构图的横移（它随主角左右跑变号，两侧能不能转开就跟着变），方向用 Boss→主角的实际方向（dir 转得慢，贴墙横跑时落后好几度，墙边只差这几度就转不开）
			var off := (to_p.normalized() if to_p.length() > 1.0 else dir) * dist + Vector3.UP * height
			var sides := [_swing_side]
			if _swing_side == 0.0:
				var side := signf((global_position - pp).dot(Vector3.UP.cross(dir)))
				if side == 0.0:
					side = 1.0
				sides = [side, -side]
			var found := false
			for sg in sides:
				for k in [1.0, 0.8]:  # 转不开就再贴近一点
					for deg in [20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 140.0]:
						var c: Vector3 = pp + (off * k).rotated(Vector3.UP, deg_to_rad(deg) * sg)
						if not found and Vector2(c.x, c.z).length() <= arena_limit and not _boss_between(c, pp, bp):
							target = c
							found = true
							_swing_side = sg
							# 转到侧面时镜头还朝着 Boss，主角会滑出画面左右边：转得越多，看向点越往主角身上拉
							look = look.lerp(pp + Vector3.UP * 1.0, deg / 100.0 * 0.5)
			if not found:
				# 实在转不开（主角被逼在死角里）：收回坑里、抬高往下看
				var over := hf.length() - arena_limit
				hf = hf.normalized() * arena_limit
				target = Vector3(hf.x, target.y + minf(over * 0.9, 4.5), hf.y)
				# 镜头被收到主角头顶附近时，看向点往主角和 Boss 之间拉（偏主角这边）：主角不掉出画面下沿，Boss 也还在画面里
				look = look.lerp(pp.lerp(bp, 0.35) + Vector3.UP * 1.2, clampf(over / 3.0, 0.0, 0.75))
		else:
			_swing_side = 0.0
	# 防穿模：从玩家头顶往镜头位置打一条射线，碰到拱门 / 地面 / 台阶就把镜头拉到它前面
	_fade_trees(from, target)
	var q := PhysicsRayQueryParameters3D.create(from, target, 1)  # 只看第 1 层（场景：地面、石台、树、拱门）
	var hit := {}
	for i in 6:  # 树和石灯只是变透明，不拉镜头：碰到就把它排除再打一次（石灯细，主角贴着它翻滚时镜头会一拉一放）
		hit = get_world_3d().direct_space_state.intersect_ray(q)
		if hit and hit.collider.get_parent() is Destructible and hit.collider.get_parent().kind != Destructible.Kind.ARCH:
			q.exclude = q.exclude + [hit.rid]
			continue
		break
	if hit:
		target = hit.position + (from - target).normalized() * 0.4
		global_position = global_position.lerp(target, clampf(rd * 20.0, 0.0, 1.0))  # 被挡住时快速拉近
		_hold = PULL_HOLD
	elif _hold > 0.0:
		_hold -= rd
		# 刚被挡过：镜头跟着走，但离玩家的距离先不放长
		var keep := global_position.distance_to(from)
		var want := from + (target - from).normalized() * minf(keep, from.distance_to(target))
		global_position = global_position.lerp(want, clampf(rd * follow, 0.0, 1.0))
	else:
		global_position = global_position.lerp(target, clampf(rd * follow, 0.0, 1.0))
	if global_position.distance_to(look) > 0.1:
		look_at(look, Vector3.UP)
	# 屏幕震动
	shake = maxf(0.0, shake - rd * 2.5)
	h_offset = randf_range(-1.0, 1.0) * shake * 0.25
	v_offset = randf_range(-1.0, 1.0) * shake * 0.25
