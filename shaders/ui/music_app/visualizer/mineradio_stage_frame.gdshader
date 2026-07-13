shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform vec4 tint : source_color = vec4(0.44, 0.92, 1.0, 1.0);
uniform float pulse = 0.0;
uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float treble = 0.0;
uniform float alpha = 0.38;
uniform float radius = 0.72;
uniform float line_width = 0.018;
uniform float glow_width = 0.18;
uniform float spoke_count = 24.0;
uniform float spin_speed = 0.08;
uniform float glass_fill = 0.10;

float ring_line(float d, float r, float w) {
	return smoothstep(w, 0.0, abs(d - r));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float angle = TIME * spin_speed + pulse * 0.08;
	float c = cos(angle);
	float s = sin(angle);
	uv = mat2(vec2(c, -s), vec2(s, c)) * uv;

	float d = length(uv);
	float beat = clamp(pulse + bass * 0.35, 0.0, 1.25);
	float outer = ring_line(d, radius, line_width * (1.0 + beat * 0.35));
	float inner = ring_line(d, radius * 0.72, line_width * 0.62);
	float halo = smoothstep(radius + glow_width, radius - glow_width, d) * (1.0 - smoothstep(radius - 0.10, radius + 0.05, d));
	float core = smoothstep(0.92, 0.08, d) * glass_fill;

	float spoke_phase = abs(sin((atan(uv.y, uv.x) + TIME * spin_speed * 0.7) * spoke_count));
	float spokes = smoothstep(0.996, 1.0, spoke_phase) * smoothstep(0.18, radius + 0.12, d) * (1.0 - smoothstep(radius + 0.18, radius + 0.32, d));
	float scan = smoothstep(0.026, 0.0, abs(fract((uv.y + TIME * 0.10) * 7.0) - 0.5)) * 0.08;
	float edge_flash = ring_line(d, radius * (0.92 + pulse * 0.08), line_width * 1.8) * pulse;

	vec3 gold = vec3(1.0, 0.72, 0.28);
	vec3 stage_color = mix(tint.rgb, gold, clamp(treble * 0.18 + pulse * 0.20, 0.0, 0.42));
	float intensity = outer * (1.15 + pulse * 1.6) + inner * (0.42 + mid * 0.55) + halo * (0.18 + bass * 0.25) + spokes * (0.18 + treble * 0.44) + core + scan + edge_flash * 0.75;
	float out_alpha = clamp(intensity * alpha, 0.0, 0.86);
	ALBEDO = stage_color * intensity;
	EMISSION = stage_color * (intensity * (1.2 + pulse * 1.4));
	ALPHA = out_alpha;
}
