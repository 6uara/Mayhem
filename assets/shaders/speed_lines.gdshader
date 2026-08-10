shader_type canvas_item;
// Radial speed-line vignette. `intensity` (0..1) is the only thing driven at
// runtime, from SpeedLinesOverlay.set_speed() - everything else here is
// static per-frame geometry. See docs/Mayhem/08 VFX and Shaders.md.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform int line_count : hint_range(4, 64) = 28;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.35;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	// Recentre and correct for aspect ratio so the radial fade reads as a
	// circle, not an ellipse, regardless of window shape.
	vec2 centered = UV - vec2(0.5);
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);

	// Each slice gets its own random width so the lines read as streaks
	// rather than a perfectly even fan.
	float slot = angle / (TAU / float(line_count));
	float cell = floor(slot);
	float frac_part = fract(slot);
	float width = mix(0.06, 0.20, hash(cell));
	float line_mask = 1.0 - smoothstep(width, width + 0.05, abs(frac_part - 0.5));

	// Invisible near the centre (the no-UI reticle zone) and at the very
	// edge - the streaks live in the ring between.
	float radial_fade = smoothstep(inner_radius, 0.75, dist)
		* (1.0 - smoothstep(0.85, 1.1, dist));

	float alpha = line_mask * radial_fade * intensity;
	COLOR = vec4(line_color.rgb, alpha * line_color.a);
}
