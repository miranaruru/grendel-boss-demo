extends MeshInstance3D
## 刀光 / 爪光拖尾：每帧记下 base / tip 两个点的位置，连成一条渐隐的带子。
## active = false 时不再记新点，旧的按 LIFE 淡完就不画了。

const MAX_SAMPLES := 16
const LIFE := 0.14

var base_node: Node3D
var base_offset := Vector3.ZERO  # 在 base_node 局部坐标里
var tip_offset := Vector3(0, 0, 1)
var color := Color(0.85, 0.92, 1.0, 0.8)
var active := false

var _samples: Array = []  # [base 全局, tip 全局, 剩余寿命]
var _im := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	material_override = m
	extra_cull_margin = 8.0


func _process(delta: float) -> void:
	for s in _samples:
		s[2] -= delta
	while _samples.size() > 0 and _samples[0][2] <= 0.0:
		_samples.pop_front()
	if active and base_node and base_node.is_inside_tree():
		_samples.append([base_node.to_global(base_offset), base_node.to_global(tip_offset), LIFE])
		if _samples.size() > MAX_SAMPLES:
			_samples.pop_front()
	_im.clear_surfaces()
	if _samples.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var a: float = clampf(s[2] / LIFE, 0.0, 1.0)
		_im.surface_set_color(Color(color, 0.0))
		_im.surface_add_vertex(s[0])
		_im.surface_set_color(Color(color, color.a * a * a))
		_im.surface_add_vertex(s[1])
	_im.surface_end()
