extends CanvasLayer
## 血条 / 招式名 / 反击提示 / 操作说明 / 结算。文字都过 Loc.t()，按 G 切中英文时 apply_lang() 刷新。

const Loc = preload("res://scripts/loc.gd")
const HINT := "WASD 移动   空格 跳   Shift/L 翻滚\nJ/左键 攻击(三连)   K/右键 弹反(按住举盾)   H 换手\nT 时间+3h   R 重开   G 中/EN"

var p_bar: ProgressBar
var b_bar: ProgressBar
var atk_label: Label
var msg_label: Label
var end_label: Label
var msg_t := 0.0
var atk_t := 0.0
# 开场亮相：上下黑边 + 大字 Boss 名，期间血条 / 操作提示隐藏
var _bars: Array[ColorRect] = []
var _title: Label
var _subtitle: Label
var _gameplay_ui: Array[Control] = []
var _b_name: Label
var _hint: Label
var _last_atk := ""
var _last_parryable := true
var _victory := false


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Hiragino Sans GB", "Noto Sans CJK SC", "Source Han Sans SC", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 20

	var root := Control.new()
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var b_name := _label(root, "", 24, Color(0.85, 0.82, 0.75))
	_place(b_name, 0.25, 0.75, 18, 48)
	_b_name = b_name
	b_bar = _bar(root, Color(0.65, 0.12, 0.10))
	_place(b_bar, 0.25, 0.75, 50, 66)

	atk_label = _label(root, "", 22, Color(1, 0.8, 0.4))
	atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(atk_label, 0.25, 0.75, 72, 102)

	p_bar = _bar(root, Color(0.75, 0.70, 0.55))
	p_bar.anchor_top = 1.0
	p_bar.anchor_bottom = 1.0
	p_bar.anchor_left = 0.0
	p_bar.anchor_right = 0.0
	p_bar.offset_left = 30
	p_bar.offset_right = 430
	p_bar.offset_top = -50
	p_bar.offset_bottom = -32

	msg_label = _label(root, "", 34, Color.WHITE)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(msg_label, 0.1, 0.9, 0, 0)
	msg_label.anchor_top = 0.62
	msg_label.anchor_bottom = 0.62
	msg_label.offset_bottom = 50

	end_label = _label(root, "", 56, Color.WHITE)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(end_label, 0.0, 1.0, 0, 0)
	end_label.anchor_top = 0.4
	end_label.anchor_bottom = 0.4
	end_label.offset_bottom = 160
	end_label.visible = false

	var hint := _label(root, "", 16, Color(0.8, 0.8, 0.8, 0.8))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -900
	hint.offset_right = -24
	hint.offset_top = -86
	hint.offset_bottom = -16
	_gameplay_ui = [b_name, b_bar, p_bar, hint]
	_hint = hint

	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = 0.0
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		root.add_child(bar)
		_bars.append(bar)
	_title = _label(root, "", 140, Color(0.92, 0.86, 0.7))
	_title.add_theme_constant_override("outline_size", 10)
	_place(_title, 0.0, 1.0, 0, 0)
	_title.anchor_top = 0.66
	_title.anchor_bottom = 0.66
	_title.offset_bottom = 170
	_subtitle = _label(root, "", 44, Color(0.75, 0.68, 0.55))
	_place(_subtitle, 0.0, 1.0, 0, 0)
	_subtitle.anchor_top = 0.66
	_subtitle.anchor_bottom = 0.66
	_subtitle.offset_top = 170
	_subtitle.offset_bottom = 230
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_set_bars(0.0)
	apply_lang()


## 按当前语言重写所有文字（开局一次，按 G 切换时再调）
func apply_lang() -> void:
	_b_name.text = Loc.t("犀渠 · 枯林之主")
	_hint.text = Loc.t(HINT)
	_title.text = Loc.t("犀渠")
	_subtitle.text = Loc.t("— 枯林之主 —")
	if _last_atk != "":
		_set_atk_text()
	if end_label.visible:
		_set_end_text()


## 黑边高度（占屏幕高的比例）
func _set_bars(h: float) -> void:
	_bars[0].anchor_bottom = h
	_bars[1].anchor_top = 1.0 - h


## 开场亮相：on = 黑边进来、血条隐藏；off = 反过来。都按真实时间
func cinematic(on: bool, dur: float = 0.5) -> void:
	var tw := create_tween().set_ignore_time_scale(true).set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_method(_set_bars, _bars[0].anchor_bottom, 0.11 if on else 0.0, dur)
	for c in _gameplay_ui:
		tw.tween_property(c, "modulate:a", 0.0 if on else 1.0, dur)
	if not on:
		tw.tween_property(_title, "modulate:a", 0.0, dur * 0.6)
		tw.tween_property(_subtitle, "modulate:a", 0.0, dur * 0.6)


## Boss 名字大字：先出名字，副标题晚一点淡入
func show_title() -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(1.15, 1.15)
	tw.tween_property(_title, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(_title, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.4)


func bind(player, boss) -> void:
	player.hp_changed.connect(func(hp, mx): p_bar.value = hp / mx * 100.0)
	boss.hp_changed.connect(func(hp, mx): b_bar.value = hp / mx * 100.0)
	player.counter_triggered.connect(func(text): show_msg(Loc.t(text), Color(0.6, 0.9, 1.0)))
	boss.attack_started.connect(_on_attack)
	boss.phase_changed.connect(func(_p): show_msg(Loc.t("犀渠狂怒了！（二阶段：更快）"), Color(1.0, 0.35, 0.25)))


func _on_attack(label: String, parryable: bool) -> void:
	_last_atk = label
	_last_parryable = parryable
	_set_atk_text()
	atk_label.modulate = Color(1.0, 0.85, 0.45) if parryable else Color(1.0, 0.35, 0.3)
	atk_t = 1.6


func _set_atk_text() -> void:
	atk_label.text = Loc.t(_last_atk) + Loc.t("  · 可弹反" if _last_parryable else "  · 不可弹反")


func show_msg(text: String, color: Color = Color.WHITE) -> void:
	msg_label.text = text
	msg_label.modulate = color
	msg_t = 1.4


func show_end(victory: bool) -> void:
	end_label.visible = true
	_victory = victory
	_set_end_text()
	end_label.modulate = Color(0.9, 0.85, 0.6) if victory else Color(0.8, 0.15, 0.1)


func _set_end_text() -> void:
	end_label.text = Loc.t("犀渠倒下了" if _victory else "你死了") + "\n" + Loc.t("按 R 重开")


func _process(delta: float) -> void:
	# 用真实时间淡出，不受顿帧 / 慢动作影响
	var real := delta / maxf(Engine.time_scale, 0.01)
	msg_t -= real
	atk_t -= real
	msg_label.modulate.a = clampf(msg_t / 0.4, 0.0, 1.0)
	atk_label.modulate.a = clampf(atk_t / 0.4, 0.0, 1.0)


func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = 100.0
	b.value = 100.0
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


func _place(c: Control, ax0: float, ax1: float, top: float, bottom: float) -> void:
	c.anchor_left = ax0
	c.anchor_right = ax1
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = top
	c.offset_bottom = bottom
