shader_type canvas_item;
render_mode blend_mix;

uniform float pulse = 0.0;
uniform float scanline_alpha = 0.055;
uniform float vignette_alpha = 0.56;
uniform float rgb_shift = 0.006;
uniform float flow_strength = 1.0;
uniform float line_density = 1.0;
uniform float grain_alpha = 0.018;
uniform float air = 0.0;
uniform float onset = 0.0;
uniform vec4 tint : source_color = vec4(0.08, 0.9, 1.0, 1.0);

float saturate(float v) {
	return clamp(v, 0.0, 1.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

float neon_loop(vec2 uv, float t, float channel) {
	vec2 q = uv;
	q *= rot(0.24 + sin(t * 0.12 + channel) * 0.08);
	q.x += 0.035 * sin(t * 0.22 + channel);
	q.y += 0.028 * cos(t * 0.18 + channel * 1.7);
	float ang = atan(q.y, q.x);
	float warp_d = length(q * vec2(1.28 + 0.05 * sin(t * 0.19), 0.84 + 0.04 * cos(t * 0.23)));
	warp_d += 0.024 * sin(q.x * 4.4 + t * 0.46) + 0.016 * sin(q.y * 5.2 - t * 0.36);
	float diamond_d = abs(q.x) * 1.18 + abs(q.y) * 0.82;
	float d = mix(warp_d, diamond_d, 0.28);
	float pattern = mod((q.x + q.y) * 0.62 + sin(q.x * 5.5 + t) * 0.015, 0.20 / max(line_density, 0.35));
	float acc = 0.0;
	for (int i = 1; i <= 5; i++) {
		float fi = float(i);
		float f = fract(t * 0.095 - channel * 0.020 + 0.012 * fi) * 4.3 - d + pattern;
		acc += 0.00072 * fi * fi / max(abs(f), 0.010);
	}
	float thread_coord = q.x * 0.88 - q.y * 0.55 + 0.026 * sin(q.x * 5.2 + t * 0.54);
	float thread_lines = 0.0034 / max(abs(sin((thread_coord + t * 0.070 + channel * 0.035) * (18.0 + line_density * 9.0))), 0.080);
	acc += thread_lines * (0.32 + 0.22 * sin(ang * 1.2 + t + channel));
	return min(acc, 1.25);
}

float fiber_field(vec2 uv, float t, float offset) {
	vec2 q = uv * rot(-0.64 + offset * 0.08);
	q.x += sin(q.y * 3.0 + t * 0.22 + offset) * 0.06;
	float major = abs(sin((q.x * 10.0 + q.y * 2.8 - t * 0.34 + offset) * line_density));
	float minor = abs(sin((q.x * 28.0 - q.y * 9.0 + t * 0.58 + offset) * (0.65 + line_density * 0.25)));
	float major_line = smoothstep(0.040, 0.0, major);
	float minor_line = smoothstep(0.018, 0.0, minor);
	float gate = smoothstep(-1.05, 0.15, q.y) * (1.0 - smoothstep(0.38, 1.25, q.y));
	return (major_line * 0.18 + minor_line * 0.075) * gate;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= 0.46;
	float t = TIME;
	vec2 flow_axis = normalize(vec2(0.86, -0.50));
	vec2 cross_axis = vec2(-flow_axis.y, flow_axis.x);
	float lane = dot(p, flow_axis);
	float cross_lane = dot(p, cross_axis);
	float sync_wave = sin(cross_lane * 5.4 + lane * 1.1 - t * 1.12);
	float active_pulse = clamp(pulse + onset * 0.65, 0.0, 1.25);
	vec2 uv = p * (1.06 + active_pulse * 0.025);
	uv += flow_axis * sync_wave * (0.016 + active_pulse * 0.018) * flow_strength;
	uv += cross_axis * sin(lane * 7.2 + t * 0.72) * 0.016 * flow_strength;
	float shift = rgb_shift * (0.7 + active_pulse * 0.55 + air * 0.42);
	vec2 rgb_axis = normalize(vec2(0.86, -0.36));

	vec3 cyan = vec3(0.12, 0.95, 0.86);
	vec3 gold = vec3(1.00, 0.72, 0.28);
	vec3 rose = vec3(1.00, 0.16, 0.34);
	float a_r = neon_loop(uv + rgb_axis * shift, t, 0.0);
	float a_g = neon_loop(uv, t + 0.05, 0.38);
	float a_b = neon_loop(uv - rgb_axis * shift, t + 0.10, 0.76);
	float b = neon_loop(uv * 1.018 + vec2(0.012, -0.008), t + 0.18, 1.0);
	float c = neon_loop(uv * 0.986 + vec2(-0.010, 0.010), t + 0.35, 2.0);
	vec3 chroma = vec3(a_r, a_g, a_b);
	vec3 loop_col = cyan * chroma.g + vec3(0.95, 0.18, 0.20) * chroma.r * 0.20 + vec3(0.16, 0.44, 1.0) * chroma.b * 0.24 + gold * b * 0.64 + rose * c * 0.22;
	float fibers = fiber_field(uv, t, 0.0) + fiber_field(uv * 1.14 + vec2(0.08, -0.04), t + 0.7, 1.8);
	vec3 fiber_col = mix(cyan, gold, saturate(UV.x + active_pulse * 0.15)) * fibers * (0.42 + air * 0.36);

	float beam = exp(-abs(p.y + 0.006 * sin(t * 1.8)) * 20.0);
	float blade_mask = smoothstep(-1.45, -0.08, p.x) * (1.0 - smoothstep(0.08, 1.45, p.x));
	vec3 blade = mix(cyan, gold, UV.x) * beam * blade_mask * (0.044 + active_pulse * 0.070);
	float diagonal = exp(-pow(lane * 1.2 + cross_lane * 0.1, 2.0) / 0.045) * (0.042 + active_pulse * 0.085);
	float scan = step(0.78, fract(UV.y * (650.0 + line_density * 180.0) + TIME * (6.0 + air * 8.0))) * scanline_alpha;
	float grain = noise(UV * vec2(360.0, 680.0) + t * 10.0) - 0.5;
	float dist = distance(UV, vec2(0.5, 0.5));
	float vignette = smoothstep(0.24, 0.82, dist) * vignette_alpha;
	float center_glow = smoothstep(0.74, 0.0, dist) * (0.020 + active_pulse * 0.065);

	vec3 color = loop_col * (0.14 + active_pulse * 0.20) + fiber_col + blade + gold * diagonal + tint.rgb * center_glow;
	color += vec3(grain * grain_alpha);
	float alpha = clamp(max(max(color.r, color.g), color.b) * 0.72 + scan + vignette, 0.0, 0.82);
	color += tint.rgb * scan * 0.55;
	color = max(color, vec3(0.0));
	COLOR = vec4(color, alpha);
}
