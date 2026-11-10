shader_type spatial;
// 积雪覆盖层：作为 material_overlay 叠在树、石头、木头上，朝上的面（世界坐标法线 y 大）盖一层雪。
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D snow_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_mask : hint_default_black, filter_linear, repeat_enable;
uniform float cover : hint_range(0.0, 1.0) = 0.45;  // 越大，越陡的面也会有雪

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = texture(snow_mask, wpos.xz * 0.3 + wpos.y * 0.05).r;
	float up = wnorm.y + (n - 0.5) * 0.5;
	float a = smoothstep(1.0 - cover, 1.0 - cover + 0.2, up);
	ALBEDO = texture(snow_albedo, wpos.xz * 0.5).rgb;
	ROUGHNESS = 0.85;
	ALPHA = a;
}
