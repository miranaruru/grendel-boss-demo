shader_type spatial;
render_mode cull_disabled;
// 挂着的小孩衣物：上边被绳子吊住不动，越往下晃得越厉害（风 + 雨）

uniform vec3 tint : source_color = vec3(0.4, 0.08, 0.06);
uniform float sway = 0.09;
instance uniform float top_y = 0.2;   // 网格本地坐标里吊着的上沿
instance uniform float len_y = 0.4;
instance uniform float phase = 0.0;

void vertex() {
	float w = clamp((top_y - VERTEX.y) / max(len_y, 0.01), 0.0, 1.0);
	float s = sin(TIME * 1.6 + phase + VERTEX.y * 3.0) * sway * w * w + sin(TIME * 3.3 + phase * 1.7) * sway * 0.3 * w;
	VERTEX.z += s;
	VERTEX.x += s * 0.3;
}

void fragment() {
	// 贴着镜头时用抖动镂空淡出，不会突然糊满一屏
	float d = length(VERTEX);
	float keep = smoothstep(0.8, 2.2, d);
	float dither = fract(dot(FRAGCOORD.xy, vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
	if (keep < 1.0 && dither > keep) {
		discard;
	}
	ALBEDO = tint * 0.8;  // 淋湿的布颜色更深
	ROUGHNESS = 0.75;
}
