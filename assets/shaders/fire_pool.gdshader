shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// El piso que arde: brasas en las grietas, un frente de fuego en el borde y
// hollin alrededor. Es la cara de `fire_pool.tscn` (Scorched Earth); el charco
// de acido sigue siendo el de los frascos y las trampas. Mismo dano, otro
// origen: si los dos se vieran igual, el jugador no sabria si el charco es de
// la transmision o de un enemigo que sigue vivo.
//
// El contorno es el de `acid_pool.gdshader`, cuenta por cuenta: tres armonicos
// con las fases que escribe HazardZone, que evalua lo mismo en GDScript para
// decidir quien se quema. Lo que brilla termina donde termina el dano; el
// hollin de afuera no emite, igual que la mancha corroida del acido.
//
// Lo vertical (llamas, chispas, la luz) es de FireZone. Este shader es solo el
// piso, y no se mueve hacia arriba: un quad plano con llamas pintadas se ve
// plano en cuanto la camara baja.
//
// TelegraphComponent maneja `glow_energy`; HazardZone maneja `spread`,
// `evaporate` y el contorno. Material local a la escena, por el mismo motivo
// que el del acido.

uniform sampler2D noise_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
// El piso quemado bajo las brasas, y el hollin que lo rodea.
uniform vec4 char_color : source_color = vec4(0.035, 0.02, 0.015, 1.0);
uniform vec4 soot_color : source_color = vec4(0.012, 0.01, 0.01, 1.0);
// Brasa tibia y brasa al rojo blanco: el calor va de una a la otra.
uniform vec4 ember_color : source_color = vec4(0.988, 0.227, 0.0, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.72, 0.25, 1.0);
uniform float glow_energy : hint_range(0.0, 6.0) = 0.6;
// Cuanto del radio esta cubierto ahora mismo, 0..1.
uniform float spread : hint_range(0.0, 1.0) = 1.0;
// 0 = ardiendo, 1 = apagado y frio.
uniform float evaporate : hint_range(0.0, 1.0) = 0.0;
// El contorno. Los escribe HazardZone; con shape_inset en 0 es un circulo.
uniform float shape_inset : hint_range(0.0, 0.5) = 0.0;
uniform vec3 shape_phase = vec3(0.0);
uniform vec3 shape_weights = vec3(0.5, 0.3, 0.2);
uniform float shape_min = -1.0;
uniform float shape_span = 2.0;
// Ruido fino del borde, en fraccion del radio y siempre hacia adentro.
uniform float edge_wobble : hint_range(0.0, 0.1) = 0.04;
uniform float edge_scale = 1.6;
// Metros que el hollin se extiende mas alla del fuego.
uniform float soot_width = 0.5;
uniform float soot_opacity : hint_range(0.0, 1.0) = 0.85;
// Metros del frente de fuego, la franja mas viva pegada al borde.
uniform float front_width = 0.3;
uniform float crack_threshold : hint_range(0.0, 1.0) = 0.6;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.03;
// Que tan rapido respira el calor. El acido fluye; el fuego titila.
uniform float flicker_speed = 2.4;

varying vec2 local_xz;
varying vec2 world_xz;
varying float world_radius;

void vertex() {
	local_xz = VERTEX.xz;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	world_radius = length(MODEL_MATRIX[0].xyz);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += value_noise(p) * amplitude;
		p = p * 2.07 + vec2(5.3, 11.7);
		amplitude *= 0.5;
	}
	return total / 0.875;
}

void fragment() {
	float r = length(local_xz);
	float px = fwidth(r);
	if (r > 1.15) {
		discard;
	}

	// El contorno: la misma cuenta que HazardZone.reach_at().
	float angle = atan(local_xz.y, local_xz.x);
	float wave = shape_weights.x * sin(2.0 * angle + shape_phase.x)
		+ shape_weights.y * sin(3.0 * angle + shape_phase.y)
		+ shape_weights.z * sin(5.0 * angle + shape_phase.z);
	float reach = 1.0 - shape_inset * clamp((wave - shape_min) / shape_span, 0.0, 1.0);
	float wobble = fbm(world_xz * edge_scale + vec2(TIME * 0.11, -TIME * 0.07));
	float full_edge = spread * reach * (1.0 - edge_wobble * wobble);
	// Al apagarse el fuego se retira hacia el centro; el quemado queda.
	float burn_edge = full_edge * (1.0 - 0.7 * evaporate);
	float burned = 1.0 - smoothstep(full_edge - px, full_edge + px, r);
	float burning = 1.0 - smoothstep(burn_edge - px, burn_edge + px, r);

	// Grietas con brasa: dos capas del mismo ruido que derivan despacio, como
	// el lava_pool. Bajo umbral = mas grieta encendida que en la lava.
	vec2 uv_a = world_xz * 0.55 + vec2(TIME * flow_speed, TIME * flow_speed * 0.6);
	vec2 uv_b = world_xz * 0.9 - vec2(TIME * flow_speed * 0.7, TIME * flow_speed * 0.4);
	float mask = texture(noise_texture, uv_a).r * texture(noise_texture, uv_b).r;
	float cracks = smoothstep(crack_threshold - 0.1, crack_threshold + 0.1, mask);

	// El titileo: manchas de calor que suben y bajan rapido, ancladas al mundo
	// para que dos charcos vecinos no respiren al unisono.
	float flicker = fbm(world_xz * 1.7 + vec2(TIME * flicker_speed * 0.3, -TIME * flicker_speed));
	float core = 1.0 - clamp(r / max(burn_edge, 0.001), 0.0, 1.0);
	float to_edge = (burn_edge - r) * world_radius;
	float front = (1.0 - smoothstep(0.0, front_width, to_edge)) * burning;

	float heat = clamp(cracks * 0.8 + core * 0.15 + front * 0.7, 0.0, 1.0)
		* (0.55 + 0.45 * flicker) * burning;
	vec3 fire = mix(ember_color.rgb, hot_color.rgb, smoothstep(0.45, 1.0, heat));

	// Hollin alrededor: sigue el contorno y se deshilacha. Sin emision.
	float soot_noise = fbm(world_xz * 2.1 + 9.0);
	float soot_reach = full_edge + soot_width * (0.4 + 0.6 * soot_noise) / max(world_radius, 0.01);
	float soot = (1.0 - smoothstep(full_edge, soot_reach, r)) * (0.5 + 0.5 * soot_noise) * soot_opacity;

	ALBEDO = mix(soot_color.rgb, char_color.rgb, burned);
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	// Lo quemado se borra recien al final del apagado: primero se va el fuego.
	float fade_out = 1.0 - smoothstep(0.5, 1.0, evaporate);
	ALPHA = max(burned, soot) * fade_out * (1.0 - smoothstep(1.15 - 0.05, 1.15, r));
	EMISSION = fire * heat * glow_energy * 0.8 * (1.0 - evaporate);
}
