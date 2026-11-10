extends RefCounted
## 中 / 英文切换。游戏里的文字都用中文写，显示前过一遍 Loc.t()；lang == "en" 时查下面的表。
## 按 G 切换（main.gd），lang 是静态变量，按 R 重开后仍保持。表里没有的字直接显示原文。

static var lang := "en"  # 默认英文

const EN := {
	# Boss 名字
	"犀渠 · 枯林之主": "Grendel · Lord of the Withered Wood",
	"犀渠": "GRENDEL",
	"— 枯林之主 —": "— Lord of the Withered Wood —",
	# Boss 招式
	"快速三连爪": "Triple Claw Flurry",
	"延迟重劈": "Delayed Cleave",
	"扑击": "Pounce",
	"低身横扫": "Low Sweep",
	"  · 可弹反": "  · Parryable",
	"  · 不可弹反": "  · Unparryable",
	"犀渠狂怒了！（二阶段：更快）": "Grendel is enraged! (Phase 2: faster)",
	# 主角反击 / 状态
	"左手剑 · 右手盾": "Sword left · Shield right",
	"右手剑 · 左手盾": "Sword right · Shield left",
	"瞬影斩！": "Shadowstep Slash!",
	"落雷斩！": "Thunderfall Slash!",
	"弹反 · 十字斩！": "Parry · Cross Slash!",
	"完美闪避！按攻击 → 瞬影斩": "Perfect dodge! Attack → Shadowstep Slash",
	"破防！": "Guard broken!",
	"震晕！": "Stunned!",
	"跳过了！空中按攻击 → 落雷斩": "Jumped it! Attack in mid-air → Thunderfall Slash",
	# 结算 / 杂项
	"犀渠倒下了": "Grendel has fallen",
	"你死了": "You died",
	"按 R 重开": "Press R to restart",
	"时间：%02d:00": "Time: %02d:00",
	"语言：中文": "Language: English",
	# 右下角操作说明
	"WASD 移动   空格 跳   Shift/L 翻滚\nJ/左键 攻击(三连)   K/右键 弹反(按住举盾)   H 换手\nT 时间+3h   R 重开   G 中/EN":
		"WASD Move   Space Jump   Shift/L Roll\nJ/LMB Attack (3-hit combo)   K/RMB Parry (hold to block)   H Swap hands\nT Time +3h   R Restart   G EN/中",
}


static func t(s: String) -> String:
	if lang == "en":
		return EN.get(s, s)
	return s


static func toggle() -> void:
	lang = "en" if lang == "zh" else "zh"
