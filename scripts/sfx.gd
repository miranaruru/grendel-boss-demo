extends Node3D
## 音效：按名字播放，每个名字可以有几个变体随机挑、音高随机抖一点（不然连砍听着像复读机）。
## 有位置的用 AudioStreamPlayer3D（镜头就是听者），没位置的（风声、主角自己的声音）用 AudioStreamPlayer。
## 音效出处见 assets/audio/CREDITS.md。其它脚本通过 get_tree().get_first_node_in_group("sfx") 调用。

const DIR := "res://assets/audio/"
const VOICES := 16  # 同时最多响几个
# 名字 → [文件们, 音量 dB, 最低音高, 最高音高, (可选) 结尾淡出秒数, (可选) 从第几秒开始播]
# 音量按每个文件「最响的 0.1 秒」量过一遍再定的（原始素材响度差了 20 多 dB），挥刀最轻，砸地 / 咆哮 / 落雷最响
const BANK := {
	"swing": [["sfx/swing_1"], -3.0, 0.9, 1.15],
	"swing_heavy": [["sfx/swing_1"], -1.0, 0.68, 0.75],
	"hit": [["sfx/hit_1", "sfx/hit_2", "sfx/hit_3"], 0.0, 0.9, 1.1],
	"hit_heavy": [["sfx/hit_heavy"], 8.0, 0.85, 1.0],
	"parry": [["sfx/parry_1"], -2.5, 0.95, 1.08],
	"block": [["sfx/block"], 4.0, 0.85, 1.0],
	"shield_up": [["sfx/block"], -12.0, 1.35, 1.5, 0.12],  # 举盾：同一个金属声，调高、很轻、很短
	"guard_break": [["sfx/guard_break"], 0.0, 0.8, 0.9],
	"hurt": [["sfx/hurt_1"], 0.0, 0.9, 1.05],
	"body_hit": [["sfx/body_hit"], -1.0, 0.85, 1.0],
	"player_death": [["sfx/player_death"], 2.0, 0.95, 1.0],
	"cloth": [["kenney/cloth1", "kenney/cloth3"], -6.0, 0.9, 1.1],
	"step": [["kenney/footstep04", "kenney/footstep06"], -6.0, 0.9, 1.1],
	"dodge": [["sfx/swing_1"], 0.0, 0.48, 0.52],
	"thunder": [["sfx/thunder"], 6.0, 0.95, 1.05],
	"claw": [["sfx/claw_whoosh"], 2.0, 0.75, 0.9],
	"sweep": [["sfx/claw_whoosh"], 3.0, 0.55, 0.6],
	"slam": [["sfx/slam_1"], 8.0, 0.7, 0.8, 0.0, 0.35],  # 原声前 0.4 秒几乎没声，跳过，不然砸地声比画面慢
	"growl": [["sfx/growl"], 12.0, 0.75, 0.85, 1.2],  # 原声很轻（最响处 -27 dB），拉到 3D 播放器的上限；原声结尾是硬切的，淡出
	"growl_short": [["sfx/growl_short"], 6.0, 0.55, 0.62, 0.25],  # 三连爪起手
	"snarl": [["sfx/snarl"], 5.0, 0.7, 0.78, 0.5, 0.4],  # 横扫起手
	"roar": [["sfx/roar"], 8.0, 0.7, 0.75],
	"roar_cry": [["sfx/roar_cry"], 8.0, 0.8, 0.85],  # 和咆哮叠在一起：婴儿哭声压低，枯林里更瘆人
	"boss_death": [["sfx/boss_death"], -4.0, 0.8, 0.85],
}
const WIND := "sfx/wind_loop"
const WIND_DB := -18.0
# 背景音乐：循环（循环在 .import 里开），开场淡入，打完淡出，压低垫在音效下面
const MUSIC := "music/the_final_battle.ogg"
const MUSIC_DB := -4.0  # 先估 -10 dB，Xiaoting 试听说太小，调高 6 dB
const MUSIC_FADE_IN := 3.0

var music: AudioStreamPlayer

var _streams := {}
var _p3d: Array[AudioStreamPlayer3D] = []
var _p2d: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _fades := {}  # 播放器 → 淡出用的 Tween


func _ready() -> void:
	add_to_group("sfx")
	for key in BANK:
		var arr: Array = []
		for f in BANK[key][0]:
			var path: String = DIR + f + ".ogg"
			if ResourceLoader.exists(path):
				arr.append(load(path))
		_streams[key] = arr
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0  # Boss 体型大，离远一点也要听得清
		p.max_db = 12.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_p3d.append(p)
	for i in VOICES / 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2d.append(p)
	if ResourceLoader.exists(DIR + WIND + ".ogg"):
		var wind := AudioStreamPlayer.new()
		wind.stream = load(DIR + WIND + ".ogg")  # 循环在导入设置里开（wind_loop.ogg.import 的 loop=true）
		wind.volume_db = WIND_DB
		wind.autoplay = true
		add_child(wind)
	if ResourceLoader.exists(DIR + MUSIC):
		music = AudioStreamPlayer.new()
		music.stream = load(DIR + MUSIC)
		music.volume_db = -60.0
		add_child(music)
		music.play()
		create_tween().set_ignore_time_scale(true).tween_property(music, "volume_db", MUSIC_DB, MUSIC_FADE_IN).set_trans(Tween.TRANS_SINE)


## 打完（赢 / 输）：音乐慢慢淡掉
func music_fade_out(seconds: float = 2.5) -> void:
	if music and music.playing:
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(music, "volume_db", -60.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(music.stop)


## 在 pos 处放一个音效；pos 为 null = 不分方向（主角自己的声音）
func play(key: String, pos = null, volume_add: float = 0.0) -> void:
	var arr: Array = _streams.get(key, [])
	if arr.is_empty():
		return
	var cfg: Array = BANK[key]
	var stream: AudioStream = arr[randi() % arr.size()]
	var db: float = cfg[1] + volume_add
	var pitch := randf_range(cfg[2], cfg[3])
	var fade: float = cfg[4] if cfg.size() > 4 else 0.0
	var start: float = cfg[5] if cfg.size() > 5 else 0.0
	var p: Node
	if pos == null:
		p = _p2d[_i2]
		_i2 = (_i2 + 1) % _p2d.size()
	else:
		p = _p3d[_i3]
		_i3 = (_i3 + 1) % _p3d.size()
		p.global_position = pos
	if _fades.has(p) and _fades[p].is_valid():
		_fades[p].kill()  # 播放器轮回来了，上一次的淡出别再压这一次的音量
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play(start)
	if fade > 0.0:
		# 按真实时间淡出（顿帧 / 慢动作时声音照常播，淡出也要跟着真实时间走）
		var left := (stream.get_length() - start) / pitch
		var tw := p.create_tween().set_ignore_time_scale(true)
		tw.tween_interval(maxf(0.0, left - fade))
		tw.tween_property(p, "volume_db", -60.0, fade)
		_fades[p] = tw


## 退出 / 重开时先停掉所有声音：正在播的 Ogg 不停就释放，Godot 退出时会报资源泄漏
func _exit_tree() -> void:
	for c in get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
