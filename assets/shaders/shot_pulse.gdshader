shader_type canvas_item;
// Edge darkening on a shot or a kill. `intensity` (0..1) is the only thing
// driven at runtime, from ShotPulseOverlay. No screen texture read on purpose:
// a full-screen copy fifteen times a second costs more than the effect is worth
// on an integrated GPU. See docs/Mayhem/08 VFX and Shaders.md.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 pulse_color : source_color = vec4(0.027, 0.031, 0.043, 1.0);
// Where the darkening starts, as a fraction of the half-diagonal. The centre,
// where the reticle and the target are, is never touched.
uniform float inner_radius : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(centered) / 0.70710678;
	float edge = smoothstep(inner_radius, 1.0, dist);
	COLOR = vec4(pulse_color.rgb, edge * intensity * pulse_color.a);
}
