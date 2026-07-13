shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D cover_texture : source_color;
uniform sampler2D previous_cover_texture : source_color;
uniform sampler2D edge_texture;
uniform sampler2D depth_texture;
uniform float color_mix = 1.0;
uniform float has_cover = 0.0;
uniform float shape_preset = 0.0;
uniform float time = 0.0;
uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float treble = 0.0;
uniform float kick = 0.0;
uniform float vocal = 0.0;
uniform float instrument_mid = 0.0;
uniform float treble_air = 0.0;
uniform float rms = 0.0;
uniform float energy_onset = 0.0;
uniform float beat = 0.0;
uniform float energy = 0.0;
uniform float burst = 0.0;
uniform float activity = 1.0;
uniform float alpha = 0.94;
uniform float point_scale = 1.0;
uniform vec4 tint_color : source_color = vec4(0.44, 0.92, 1.0, 1.0);
uniform vec4 ripple0 = vec4(0.0, 0.0, 9.0, 0.0);
uniform vec4 ripple1 = vec4(0.0, 0.0, 9.0, 0.0);
uniform vec4 ripple2 = vec4(0.0, 0.0, 9.0, 0.0);
uniform vec4 ripple3 = vec4(0.0, 0.0, 9.0, 0.0);

varying vec2 v_dot_uv;
varying vec2 v_cover_uv;
varying float v_bright;
varying float v_random;
varying float v_ripple;
varying float v_edge;
varying float v_depth;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float ripple_at(vec2 p, vec4 ripple_data) {
	float age = ripple_data.z;
	float strength = ripple_data.w;
	if (age < 0.0 || age > 1.25 || strength <= 0.001) {
		return 0.0;
	}
	float dist = distance(p, ripple_data.xy);
	float wave_radius = age * 3.45;
	float ring = exp(-pow((dist - wave_radius) / 0.22, 2.0));
	float bulge = exp(-dot(p - ripple_data.xy, p - ripple_data.xy) / (0.95 + age * 1.25));
	float fade = 1.0 - smoothstep(0.68, 1.25, age);
	return (ring * 1.15 + bulge * 0.45) * strength * fade;
}

void vertex() {
	vec2 cover_uv = UV;
	vec2 centered = cover_uv * 2.0 - 1.0;
	float random_value = COLOR.a;
	float edge_value = texture(edge_texture, cover_uv).r;
	float depth_value = texture(depth_texture, cover_uv).r;
	float local_ripple = 0.0;
	local_ripple += ripple_at(centered, ripple0);
	local_ripple += ripple_at(centered, ripple1);
	local_ripple += ripple_at(centered, ripple2);
	local_ripple += ripple_at(centered, ripple3);

	float preset = floor(shape_preset + 0.5);
	float radial = length(centered);
	float orbit = sin(atan(centered.y, centered.x) * 4.0 + time * 0.42 + random_value * 2.0);
	float tunnel = exp(-pow((radial - 0.58) / 0.24, 2.0));
	float kick_power = max(kick, bass * 0.72);
	float vocal_power = max(vocal, mid * 0.62);
	float mid_power = max(instrument_mid, mid * 0.68);
	float air_power = max(treble_air, treble * 0.50);
	float onset_power = max(energy_onset, burst * 0.45);
	float low_wave = sin(centered.x * 4.2 + centered.y * 1.3 + time * 1.5 + random_value * 6.2831) * kick_power * 0.27;
	float vocal_wave = sin(centered.y * 5.8 + time * 1.15 + random_value * 2.4) * vocal_power * 0.075 * (0.35 + depth_value);
	float mid_wave = sin((centered.x + centered.y) * 7.0 - time * 2.4 + random_value * 5.0) * mid_power * 0.13;
	float high_jitter = sin(random_value * 38.0 + time * 10.0) * air_power * 0.052;
	float center_push = (1.0 - smoothstep(0.0, 1.15, length(centered))) * (beat * 0.40 + onset_power * 0.36 + burst * 0.30);
	float depth_push = (depth_value - 0.5) * (0.34 + kick_power * 0.18 + vocal_power * 0.08) + edge_value * (0.08 + air_power * 0.11);
	float preset_push = 0.0;
	if (preset == 1.0) {
		preset_push = orbit * (0.12 + mid_power * 0.10);
		VERTEX.xy += vec2(-centered.y, centered.x) * (0.012 + onset_power * 0.016 + burst * 0.018) * activity * (0.4 + edge_value);
	} else if (preset == 2.0) {
		preset_push = tunnel * (0.18 + kick_power * 0.16) - radial * 0.05;
		VERTEX.xy += centered * tunnel * (beat * 0.018 + onset_power * 0.016 + burst * 0.026) * activity;
	} else if (preset == 3.0) {
		preset_push = sin(centered.y * 13.0 + time * 1.2 + random_value) * (0.06 + air_power * 0.09 + vocal_power * 0.035);
		VERTEX.x += sin(centered.y * 5.0 + time * 0.7) * 0.018 * activity;
	}
	float z = (low_wave + vocal_wave + mid_wave + high_jitter + local_ripple * 0.55 + center_push + depth_push + preset_push) * activity;
	VERTEX.z += z;
	VERTEX.xy += centered * (beat * 0.020 + onset_power * 0.018 + burst * 0.026 + local_ripple * 0.010 + edge_value * 0.006) * activity;

	float dot_size = (0.92 + depth_value * 0.24 + edge_value * 0.34 + beat * 0.24 + air_power * 0.28 + onset_power * 0.22 + local_ripple * 0.18 + burst * 0.18) * point_scale;
	vec2 dot_dir = UV2 * 2.0 - 1.0;
	VERTEX.xy += dot_dir * 0.006 * dot_size;

	v_dot_uv = UV2;
	v_cover_uv = cover_uv;
	v_random = random_value;
	v_ripple = clamp(local_ripple, 0.0, 1.0);
	v_edge = edge_value;
	v_depth = depth_value;
	v_bright = 0.60 + depth_value * 0.20 + edge_value * 0.24 + max(energy, rms) * 0.25 + kick_power * 0.17 + air_power * 0.10 + beat * 0.35 + onset_power * 0.30 + burst * 0.30 + local_ripple * 0.34;
}

void fragment() {
	vec2 dot_centered = v_dot_uv * 2.0 - 1.0;
	float dot_dist = length(dot_centered);
	float dot_alpha = smoothstep(1.0, 0.28, dot_dist);
	vec2 cover_centered = v_cover_uv * 2.0 - 1.0;
	float cover_dist = length(cover_centered);
	float record_mask = mix(1.0, 1.0 - smoothstep(0.86, 1.04, cover_dist), 1.0 - clamp(has_cover, 0.0, 1.0));
	float inner_hole = mix(1.0, smoothstep(0.095, 0.15, cover_dist), 1.0 - clamp(has_cover, 0.0, 1.0));
	float edge_alpha = 0.68 + v_depth * 0.20 + v_edge * 0.45;
	dot_alpha *= record_mask * inner_hole * edge_alpha;
	if (dot_alpha <= 0.01) {
		discard;
	}

	vec3 current_color = texture(cover_texture, v_cover_uv).rgb;
	vec3 previous_color = texture(previous_cover_texture, v_cover_uv).rgb;
	vec3 cover_color = mix(previous_color, current_color, clamp(color_mix, 0.0, 1.0));
	vec3 fallback = mix(
		mix(vec3(0.08, 0.48, 0.72), vec3(0.86, 0.60, 0.24), v_cover_uv.x),
		vec3(0.16, 0.94, 0.86),
		smoothstep(0.25, 1.0, v_cover_uv.y)
	);
	float groove = 0.5 + 0.5 * sin(cover_dist * 86.0 - time * 0.45);
	float rim = exp(-pow((cover_dist - 0.78) / 0.035, 2.0));
	fallback = mix(fallback * (0.62 + groove * 0.24), vec3(0.95, 0.88, 0.56), rim * 0.55);
	vec3 color = mix(fallback, cover_color, clamp(has_cover, 0.0, 1.0));
	float tint_mix = clamp(0.16 + treble_air * 0.30 + treble * 0.12 + beat * 0.18, 0.0, 0.62);
	color = mix(color, tint_color.rgb * max(0.34, max(max(color.r, color.g), color.b)), tint_mix);
	color += tint_color.rgb * (v_edge * 0.18 + v_ripple * 0.20 + beat * 0.08 + energy_onset * 0.10 + burst * 0.08);
	ALBEDO = color * v_bright;
	EMISSION = color * (0.32 + v_edge * 0.62 + beat * 0.95 + energy_onset * 0.82 + v_ripple * 0.75 + burst * 0.75);
	ALPHA = dot_alpha * alpha * (0.72 + v_bright * 0.28);
}
