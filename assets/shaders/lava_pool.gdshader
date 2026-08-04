shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// Molten rock: a dark crust with glowing cracks that drift, not a flat coloured
// disc. Two copies of the same noise texture scroll at different speeds and
// blend together - one texture alone repeats in an obviously loopable way, two
// drifting against each other almost never lines up, which is what makes it read
// as something flowing rather than a texture sliding.

uniform sampler2D noise_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 crust_color : source_color = vec4(0.05, 0.03, 0.02, 1.0);
uniform vec4 glow_color : source_color = vec4(0.988, 0.227, 0.0, 1.0);
uniform float glow_energy : hint_range(0.0, 6.0) = 2.0;
// Crust cracks open above this, so raising it means more dark crust and thinner
// veins of glow - the same knob a real flow field would call "cooling".
uniform float crack_threshold : hint_range(0.0, 1.0) = 0.55;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	vec2 uv_a = UV * 1.3 + vec2(TIME * flow_speed, TIME * flow_speed * 0.6);
	vec2 uv_b = UV * 2.1 - vec2(TIME * flow_speed * 0.7, TIME * flow_speed * 0.4);
	float mask = texture(noise_texture, uv_a).r * texture(noise_texture, uv_b).r;

	float veins = smoothstep(crack_threshold - 0.12, crack_threshold + 0.12, mask);
	ALBEDO = mix(crust_color.rgb, glow_color.rgb, veins * 0.4);
	EMISSION = glow_color.rgb * veins * glow_energy;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
