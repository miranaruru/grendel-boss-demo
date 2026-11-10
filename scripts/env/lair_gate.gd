extends StaticBody3D
## 南口沟的隐形墙：主角跑进坑里（离坑中心 < close_r）之后才关上，之后回不到出生的沟里。
## 只挡主角（碰撞层 = 只给主角的那一层），Boss 和镜头都不受影响。按 R 重开场景时会重新打开。

var close_r := 14.0
var player_r := 0.0   # 关上以后：主角的活动半径收到坑里（> 0 才改）
var cam_r := 0.0      # 关上以后：镜头不出这个半径
var _closed := false
var _shape: CollisionShape3D


func _ready() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			_shape = c
	if _shape:
		_shape.disabled = true


func _physics_process(_delta: float) -> void:
	if _closed:
		return
	var main := get_tree().current_scene
	var p = main.get("player") if main else null
	if p == null or not is_instance_valid(p):
		return
	var pos: Vector3 = p.global_position
	if Vector2(pos.x, pos.z).length() < close_r:
		_closed = true
		if _shape:
			_shape.disabled = false
		if player_r > 0.0:
			p.set("arena_radius", player_r)
		var cam = main.get("cam")
		if cam_r > 0.0 and cam:
			cam.set("arena_limit", cam_r)
		set_physics_process(false)
