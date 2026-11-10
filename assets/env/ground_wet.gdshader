shader_type spatial;
render_mode cull_disabled;
// 方案 B 地面：湿泥 + 枯叶，低洼平地积水成水洼，雨点在水洼里打出一圈圈涟漪。
// 水洼的分布用一张无缝噪声图决定（puddle_amount 越大水洼越多）；只在平地上积水。

uniform sampler2D leaves_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaves_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D leaves_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_noise : hint_default_black, filter_linear, repeat_enable;
// 碎石泥土（Poly Haven CC0）：坑底被踩烂的地方、和落叶之间的一块块碎石地
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_gravel = false;
uniform float gravel_tile = 0.45;
uniform vec3 gravel_tint : source_color = vec3(0.72, 0.68, 0.64);
uniform float gravel_amount : hint_range(0.0, 1.0) = 0.6;

uniform float leaves_tile = 0.35;
uniform vec3 mud_color : source_color = vec3(0.16, 0.13, 0.10);
uniform vec3 leaves_tint : source_color = vec3(0.62, 0.58, 0.54);
uniform float puddle_amount : hint_range(0.0, 1.0) = 0.24;
uniform float pit_radius = 13.5;
uniform float rain = 1.0;          // 雨的大小：涟漪强度
uniform float wetness = 1.0;       // 整体湿度：越湿越暗、越反光

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// 雨点涟漪：每个格子里一个随机位置、随机时刻的扩散圆环，返回法线的 xy 偏移
vec2 ripples(vec2 uv, float t) {
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	vec2 n = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 h = hash22(cell + o);
			vec2 d = f - (o + h);
			float dist = length(d);
			float ph = fract(t * 0.8 + h.x * 7.13 + h.y * 3.7);
			float r = ph * 0.75;
			float ring = sin((dist - r) * 45.0) * smoothstep(0.07, 0.0, abs(dist - r)) * (1.0 - ph) * (1.0 - ph);
			n += (dist > 0.0001 ? d / dist : vec2(0.0)) * ring;
		}
	}
	return n;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 uv = p * leaves_tile;
	vec3 leaves = texture(leaves_albedo, uv).rgb * leaves_tint;
	float mud_n = texture(mask_noise, p * 0.035).r;
	float r = length(p);
	// 坑底被踩成烂泥，坑外落叶多一些
	float mud_k = smoothstep(0.42, 0.72, mud_n) * 0.75 + (1.0 - smoothstep(pit_radius - 3.0, pit_radius + 2.0, r)) * 0.35;
	mud_k = clamp(mud_k, 0.0, 1.0);
	// 碎石泥土：泥地里全是碎石，落叶之间也露出一块块
	float gn = texture(mask_noise, p * 0.05 + vec2(0.71, 0.23)).r;
	float grav_k = clamp(max(mud_k, smoothstep(0.55 - gravel_amount * 0.3, 0.75 - gravel_amount * 0.3, gn)), 0.0, 1.0);
	vec2 guv = p * gravel_tile;
	// 两个方向、两种尺度混一下，避免一眼看出重复
	vec3 grav = texture(gravel_albedo, guv).rgb;
	grav = mix(grav, texture(gravel_albedo, guv * 0.37 + vec2(0.3, 0.6)).rgb, 0.35) * gravel_tint;
	vec3 mud = has_gravel ? mix(mud_color, grav, 0.85) : mud_color;
	// 程序生成的小石子（没有贴图时也有颗粒感）：格子里随机点，亮一点或暗一点
	vec2 sc = floor(p * 6.0);
	vec2 sh = hash22(sc);
	float sd = length(fract(p * 6.0) - sh);
	float speck = smoothstep(0.22 * sh.y + 0.05, 0.0, sd) * step(0.55, sh.x);
	mud *= 1.0 + speck * (sh.y - 0.4) * 0.9;
	vec3 base = mix(leaves, mud, has_gravel ? grav_k : mud_k);

	float pn = texture(mask_noise, p * 0.07 + vec2(0.37, 0.11)).r;
	float flat_k = smoothstep(0.93, 0.995, normalize(wnorm).y);
	float puddle = smoothstep(1.0 - puddle_amount - 0.025, 1.0 - puddle_amount + 0.025, pn) * flat_k;
	float damp_edge = smoothstep(1.0 - puddle_amount - 0.12, 1.0 - puddle_amount, pn) * flat_k;  // 水洼边缘一圈更湿更暗

	float rough = mix(texture(leaves_rough, uv).r, has_gravel ? texture(gravel_rough, guv).r : 0.9, has_gravel ? grav_k : 0.0);
	vec3 wet = base * mix(1.0, 0.55, wetness);
	wet *= mix(1.0, 0.75, damp_edge);
	ALBEDO = mix(wet, base * 0.3, puddle);
	// 湿但不是镜面：v2 用 rough * 0.45，坡面在光束下一片闪光，像金属
	ROUGHNESS = mix(max(mix(rough, rough * 0.8, wetness), 0.55), 0.03, puddle);
	SPECULAR = 0.5;
	METALLIC = 0.0;

	vec3 leaf_n = texture(leaves_normal, uv).rgb;
	if (has_gravel) {
		leaf_n = mix(leaf_n, texture(gravel_normal, guv).rgb, grav_k);
	}
	// 小石子的凸起
	vec2 sdir = fract(p * 6.0) - sh;
	leaf_n.xy += (sd > 0.0001 ? sdir / sd : vec2(0.0)) * speck * 0.25;
	vec2 rip = (ripples(p * 1.7, TIME) + ripples(p * 2.9 + 17.0, TIME * 1.13) * 0.6) * rain;
	vec3 water_n = vec3(rip * 0.22 + 0.5, 1.0);
	NORMAL_MAP = mix(leaf_n, water_n, puddle);
	NORMAL_MAP_DEPTH = mix(mix(0.6, 1.3, has_gravel ? grav_k : 0.0), 1.0, puddle);
}
