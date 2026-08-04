shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Arena walls as holographic panels.
//
// Derived from hologram.gdshader, which is written for volumetric holograms - props
// you see *through*. Three things in its render_mode make it unusable as a wall:
// depth_test_disabled draws the surface over everything in front of it (walls on top
// of enemies), blend_add makes it translucent (an arena you can see out of), and
// cull_disabled doubles the fill cost of a surface that is only ever seen from one
// side. Its vertex displacement would also make the arena breathe.
//
// What carries over is the part that reads as a hologram: the scanline signal, the
// wipe travelling up the surface, the stepped flicker, the grain, and the fresnel
// edge highlight. Those go into EMISSION over an opaque dark panel, so the wall is
// still a wall - it occludes, it takes light, it stops bullets - and looks like a
// projection while doing it.

uniform vec3 base_color : source_color = vec3(0.05, 0.055, 0.07);
uniform vec3 primary_color : source_color = vec3(0.208, 0.878, 0.831);
uniform vec3 secondary_color : source_color = vec3(0.6, 0.95, 1.0);
uniform float effect_strength : hint_range(0.0, 8.0) = 2.2;

group_uniforms Wipe;
uniform float wipe_scale : hint_range(0.0, 16.0, 0.01) = 3.0;
uniform float wipe_speed : hint_range(0.0, 8.0, 0.01) = 0.5;
uniform float wipe_blend : hint_range(0.0, 1.0, 0.01) = 0.7;

group_uniforms Signal;
uniform float signal_scale = 40.0;
uniform float signal_speed = 1.0;
uniform float signal_random_scale : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float signal_blend : hint_range(0.0, 1.0, 0.01) = 1.0;

group_uniforms Noise;
uniform sampler2D noise_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform float noise_distort_amount : hint_range(0.0, 1.0, 0.01) = 0.1;
uniform float noise_amount : hint_range(0.0, 1.0, 0.01) = 1.0;

group_uniforms Grain;
uniform float grain_amount : hint_range(0.0, 1.0, 0.01) = 0.4;

group_uniforms Flicker;
uniform float flicker_amount : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float flicker_speed : hint_range(0.0, 30.0, 0.01) = 10.0;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.15;

varying vec3 vert;

float overlay(float base, float blend) {
	float limit = step(0.5, base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

vec2 overlay(vec2 base, vec2 blend) {
	vec2 limit = step(0.5, base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

float sample_wipe(float offset) {
	return 1.0 - fract(vert.y * wipe_scale + TIME * wipe_speed + offset);
}

void vertex() {
	// Object space, so the pattern is anchored to the wall rather than swimming
	// across it as the player moves.
	vert = VERTEX;
}

void fragment() {
	float step_time = round(TIME * 4.0) / 4.0;

	float grain = fract(dot(vert.x * 234.1421, vert.z * 123.7312) * 20.0);
	float noise_xy = texture(noise_texture, vert.xy + step_time).r;
	float noise_zy = texture(noise_texture, vert.zy + step_time).r;

	vec2 checker_pos = overlay(floor(vert.xy * 2.0 + step_time) / 3.0,
		floor(vert.zy * 2.0 - step_time) / 3.0);
	float checker = 1.0 + (fract(dot(checker_pos, vec2(1.0))) * 2.0 - 1.0) * signal_random_scale;

	float noise_xyz = mix(1.0, overlay(noise_xy, noise_zy), noise_amount);
	float stepped_noise = step(noise_xyz, 0.9);

	float scan = sample_wipe(stepped_noise * noise_distort_amount);
	float signal = pow(abs(fract(vert.y * checker * signal_scale
		- (TIME * signal_speed)) * 2.0 - 1.0), 0.5);

	// A stepped flicker rather than a smooth one - a projection drops frames, it
	// does not fade.
	float flicker_mult = cos(TIME * PI * 2.0);
	float flicker = sin(TIME * flicker_speed + flicker_mult) / 2.0 + 0.5;
	flicker = floor(flicker * 4.0) / 3.0;
	flicker = 1.0 - flicker * flicker_amount;

	float fresnel = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float highlight = pow(1.0 - fresnel, 3.0);
	highlight = mix(highlight, highlight / (signal + 0.1), signal_blend);
	highlight *= (1.0 - wipe_blend) + scan * wipe_blend;
	highlight *= (1.0 - grain_amount) + grain * grain_amount;
	highlight *= noise_xyz * flicker;

	ALBEDO = base_color;
	EMISSION = mix(primary_color * 0.15, secondary_color, clamp(highlight, 0.0, 1.0))
		* effect_strength * highlight;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
