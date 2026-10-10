shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// arena_glitch_panel.gdshader sin animacion: la grilla triplanar y el fresnel por
// celda, nada que dependa de TIME. Para superficies que van congeladas (el cuenco
// del coliseo): con los parametros de animacion en cero el shader animado daba
// este mismo resultado, pero pagaba los pulsos y el barrido por pixel igual.
// Los nombres de los uniforms coinciden con los del animado, asi que quien lo
// configura no tiene que saber cual de los dos le toco.

uniform vec4 base_color : source_color = vec4(0.078, 0.086, 0.106, 1.0);
uniform vec4 line_color : source_color = vec4(0.208, 0.878, 0.831, 1.0);
uniform float grid_scale : hint_range(0.05, 4.0) = 0.4;
uniform float line_width : hint_range(0.005, 0.3) = 0.045;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.8;
uniform float glitch_strength : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_speed : hint_range(0.0, 10.0) = 0.0;
uniform float scanline_speed : hint_range(0.0, 4.0) = 0.0;
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

float grid_line(vec2 uv, float scale, float width) {
	vec2 cell = fract(uv * scale) - 0.5;
	vec2 dist = abs(cell);
	float edge = max(dist.x, dist.y);
	return smoothstep(0.5 - width, 0.5, edge);
}

void fragment() {
	vec3 blend = abs(world_normal);
	blend = blend / max(blend.x + blend.y + blend.z, 0.0001);

	vec2 uv_x = world_pos.zy;
	vec2 uv_y = world_pos.xz;
	vec2 uv_z = world_pos.xy;

	float lines = grid_line(uv_x, grid_scale, line_width) * blend.x
		+ grid_line(uv_y, grid_scale, line_width) * blend.y
		+ grid_line(uv_z, grid_scale, line_width) * blend.z;

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		fresnel_power);
	float cell_shine = mix(0.5, 1.0, hash21(floor(uv_x * grid_scale))) * blend.x
		+ mix(0.5, 1.0, hash21(floor(uv_y * grid_scale))) * blend.y
		+ mix(0.5, 1.0, hash21(floor(uv_z * grid_scale))) * blend.z;

	ALBEDO = mix(base_color.rgb, line_color.rgb, lines * 0.5);
	EMISSION = line_color.rgb * (emission_energy * clamp(lines, 0.0, 1.6)
		+ fresnel * fresnel_strength * cell_shine);
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}
