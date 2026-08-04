shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;
// The doorway a wave spawns through. Additive and unshaded on purpose: this reads
// as a hole into somewhere else, not a lit surface, and it has to stay visible
// against both the bright ground and the dark high walkway.
//
// A rotating swirl noise plus an inward-pulling radial distortion is the whole
// trick - the same noise sampled through polar coordinates instead of UV reads as
// a vortex rather than a texture, because the distortion itself spins.

uniform sampler2D noise_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.231, 0.757, 1.0);
uniform float spin_speed : hint_range(-4.0, 4.0) = 1.2;
uniform float pull_strength : hint_range(0.0, 1.0) = 0.35;
// 0 outside the ring, 1 inside - driven from GDScript so a closed door is dark
// and a telegraphing one brightens without swapping materials.
uniform float glow_energy : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec2 centred = UV - vec2(0.5);
	float radius = length(centred) * 2.0;
	float angle = atan(centred.y, centred.x) + TIME * spin_speed;

	// Sampling further from centre pulls the noise inward, like the doorway is
	// draining toward its middle rather than just spinning in place.
	vec2 polar_uv = vec2(angle / TAU + 0.5, radius - TIME * pull_strength * 0.3);
	float swirl = texture(noise_texture, polar_uv).r;

	float ring = smoothstep(1.0, 0.0, radius) * smoothstep(0.0, 0.35, radius);
	float alpha = ring * mix(0.4, 1.0, swirl);

	ALBEDO = tint.rgb;
	ALPHA = alpha * glow_energy;
}
