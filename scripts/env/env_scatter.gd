@tool
class_name EnvScatter
extends Node3D
## 环境物件摆放器：按 rules 里的规则，在竞技场周围摆石头、倒木、枯树……
## 同一个 layout_seed 永远摆出同一个结果。打开 scenes/env_layout.tscn，在检查器里改参数，点「重新生成」就能预览。
## 密度 = 噪声 ×（可选）密度图：密度高的地方扎堆，低的地方留空地；每条规则的 clustering 决定它跟不跟密度走。

const ArenaBuilder = preload("res://scripts/arena_builder.gd")

@export var layout_seed := 20261101:
	set(v):
		layout_seed = v
		if Engine.is_editor_hint() and is_inside_tree():
			regenerate()
@export var avoid_radius := 18.0              ## 战斗区域半径：规则没允许的话不往里放
@export var density_noise: FastNoiseLite      ## 大块的密 / 稀分布；frequency 越小，林子和空地越大
@export var density_map: Texture2D            ## 可选：俯视密度图，白 = 密，黑 = 稀（随便用画图软件画）
@export var density_map_size := 120.0         ## 密度图覆盖多少米见方（中心 = 竞技场中心）
@export var rules: Array[ScatterRule] = []
@export_tool_button("重新生成", "Reload") var regenerate_button := regenerate

var _scenes := {}
var _map_img: Image


func _ready() -> void:
	regenerate()


func regenerate() -> void:
	for c in get_children():
		c.free()
	ArenaBuilder.ensure_materials()
	_map_img = null
	if density_map:
		_map_img = density_map.get_image()
		if _map_img and _map_img.is_compressed():
			_map_img.decompress()
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var placed := []  # [Vector2 位置, 间距]
	for rule in rules:
		if rule == null or not rule.enabled:
			continue
		var target := rng.randi_range(rule.count_min, rule.count_max)
		var n := 0
		var tries := 0
		while n < target and tries < target * 60:
			tries += 1
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(rule.ring_min * rule.ring_min, rule.ring_max * rule.ring_max))  # 面积均匀
			var p := Vector2(cos(a) * r, sin(a) * r)
			if not rule.ignore_avoid and r < avoid_radius:
				continue
			if rng.randf() > lerpf(1.0, smoothstep(0.3, 0.7, density_at(p.x, p.y)), rule.clustering):
				continue
			var ok := true
			for q in placed:
				if p.distance_to(q[0]) < (rule.min_spacing + q[1]) * 0.5:
					ok = false
					break
			if not ok:
				continue
			placed.append([p, rule.min_spacing])
			_spawn(rule, Vector3(p.x, rule.y_offset, p.y), rng)
			n += 1


## 0 ~ 1，越大越密
func density_at(x: float, z: float) -> float:
	var d := 1.0
	if density_noise:
		d = density_noise.get_noise_2d(x, z) * 0.5 + 0.5
	if _map_img:
		var u := clampf(x / density_map_size + 0.5, 0.0, 1.0)
		var v := clampf(z / density_map_size + 0.5, 0.0, 1.0)
		d *= _map_img.get_pixel(int(u * (_map_img.get_width() - 1)), int(v * (_map_img.get_height() - 1))).r
	return d


func _spawn(rule: ScatterRule, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var scl := rng.randf_range(rule.scale_min, rule.scale_max)
	if rule.kind == ScatterRule.Kind.DEAD_TREE:
		ArenaBuilder.make_tree(self, pos, rng, scl)
		return
	if rule.scene_path == "":
		return
	if not _scenes.has(rule.scene_path):
		_scenes[rule.scene_path] = load(rule.scene_path)
	var node: Node3D = _scenes[rule.scene_path].instantiate()
	node.position = pos
	if rule.random_rotation:
		node.rotation.y = rng.randf() * TAU
	node.scale = Vector3.ONE * scl
	if rule.snow:
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			mi.material_overlay = ArenaBuilder.snow_cap()
	add_child(node)
