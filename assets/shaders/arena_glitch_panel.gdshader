shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Triplanar circuit grid over a dark panel, with occasional per-cell glitch pulses
// and a fine scanline sweep. One shader, tinted per-surface via `base_color` /
// `line_color` so floor/wall/mid/high keep their current value-separation instead
// of reading as one flat volume.

uniform vec4 base_color : source_color = vec4(0.078, 0.086, 0.106, 1.0);
uniform vec4 line_color : source_color = vec4(0.208, 0.878, 0.831, 1.0);
uniform float grid_scale : hint_range(0.05, 4.0) = 0.4;
uniform float line_width : hint_range(0.005, 0.3) = 0.045;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.8;
uniform float glitch_strength : hint_range(0.0, 1.0) = 0.5;
uniform float glitch_speed : hint_range(0.0, 10.0) = 2.0;
uniform float scanline_speed : hint_range(0.0, 4.0) = 0.35;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.5;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.2;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 4.0) = 1.2;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 1.0 on the border of each cell, 0.0 inside it.
float grid_line(vec2 uv, float scale, float width) {
	vec2 cell = fract(uv * scale) - 0.5;
	vec2 dist = abs(cell);
	float edge = max(dist.x, dist.y);
	return smoothstep(0.5 - width, 0.5, edge);
}

vec2 cell_id(vec2 uv, float scale) {
	return floor(uv * scale);
}

void fragment() {
	// Triplanar blend so the same shader tiles cleanly across the floor (XZ)
	// and every wall (XY or ZY) without stretching at the CSGBox seams.
	vec3 blend = abs(world_normal);
	blend = blend / max(blend.x + blend.y + blend.z, 0.0001);

	vec2 uv_x = world_pos.zy;
	vec2 uv_y = world_pos.xz;
	vec2 uv_z = world_pos.xy;

	float line_x = grid_line(uv_x, grid_scale, line_width);
	float line_y = grid_line(uv_y, grid_scale, line_width);
	float line_z = grid_line(uv_z, grid_scale, line_width);
	float lines = line_x * blend.x + line_y * blend.y + line_z * blend.z;

	// Per-cell glitch pulse: a cell picks a new random brightness every tick,
	// so panels flicker in blocks instead of uniformly - the "one line strobing"
	// look reads as a light bulb, not a broadcast glitch. glitch_speed/scanline_speed
	// default to 0 for now (frozen), which collapses TIME out and leaves this as a
	// fixed per-cell pattern rather than an animation.
	float tick = floor(TIME * glitch_speed);
	vec2 id_x = cell_id(uv_x, grid_scale);
	vec2 id_y = cell_id(uv_y, grid_scale);
	vec2 id_z = cell_id(uv_z, grid_scale);
	float pulse_x = step(1.0 - glitch_strength * 0.25, hash21(id_x + tick));
	float pulse_y = step(1.0 - glitch_strength * 0.25, hash21(id_y + tick * 1.37));
	float pulse_z = step(1.0 - glitch_strength * 0.25, hash21(id_z + tick * 0.71));
	float pulse = pulse_x * blend.x + pulse_y * blend.y + pulse_z * blend.z;

	// A slow scanline sweep across world Y, so the whole arena reads as one
	// surface being scanned rather than each panel animating independently.
	float scan = 0.5 + 0.5 * sin(world_pos.y * 2.0 - TIME * scanline_speed * TAU);
	float scan_glow = pow(scan, 8.0) * glitch_strength;

	// Fresnel rim, scaled per cell so each panel/quadrant catches the light with
	// its own fixed brightness instead of one uniform sheen across the whole wall.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		fresnel_power);
	float cell_shine = mix(0.5, 1.0, hash21(id_x)) * blend.x
		+ mix(0.5, 1.0, hash21(id_y)) * blend.y
		+ mix(0.5, 1.0, hash21(id_z)) * blend.z;
	float fresnel_glow = fresnel * fresnel_strength * cell_shine;

	float emission_mask = clamp(lines + pulse * 0.8 + scan_glow * lines, 0.0, 1.6);

	ALBEDO = mix(base_color.rgb, line_color.rgb, lines * 0.5);
	EMISSION = line_color.rgb * (emission_energy * emission_mask + fresnel_glow);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
