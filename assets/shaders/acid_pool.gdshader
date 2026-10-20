shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// El charco de acido: liquido con contorno de charco, burbujas y una mancha
// corroida alrededor.
//
// Va sobre un quad plano de 2.3x2.3 (radio 1 = el radio de dano, con margen
// para que la mancha no se corte en seco) que HazardZone
// escala al radio. El contorno sale de tres armonicos en angulo con fases al
// azar (`shape_*`), que HazardZone evalua igual en GDScript para decidir quien
// se quema: el dano sigue el dibujo, no el circulo. Encima va un ruido fino
// que solo se mete hacia adentro y unos pocos centimetros, para que el borde
// no sea una curva limpia.
//
// La mancha que rodea al liquido es piso corroido: oscura, sin brillo. Lo que
// avisa es el verde que brilla, y ese termina donde termina el dano.
//
// TelegraphComponent maneja `glow_energy` (parpadeo de WARNING, pulso de
// ACTIVE). HazardZone maneja `spread` (se esparce durante el aviso),
// `evaporate` (se seca al vencer) y el contorno. El material es local a la
// escena: si fuera compartido, todos los charcos pooleados parpadearian, se
// secarian y tendrian la forma del ultimo que aparecio.

uniform sampler2D noise_texture : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec4 liquid_color : source_color = vec4(0.03, 0.07, 0.02, 1.0);
uniform vec4 glow_color : source_color = vec4(0.776, 1.0, 0.239, 1.0);
uniform vec4 stain_color : source_color = vec4(0.04, 0.05, 0.02, 1.0);
uniform float glow_energy : hint_range(0.0, 6.0) = 0.6;
// Cuanto del radio esta cubierto ahora mismo, 0..1.
uniform float spread : hint_range(0.0, 1.0) = 1.0;
// 0 = charco entero, 1 = seco y apagado.
uniform float evaporate : hint_range(0.0, 1.0) = 0.0;
// El contorno. Los escribe HazardZone; con shape_inset en 0 es un circulo.
uniform float shape_inset : hint_range(0.0, 0.5) = 0.0;
uniform vec3 shape_phase = vec3(0.0);
uniform vec3 shape_weights = vec3(0.5, 0.3, 0.2);
uniform float shape_min = -1.0;
uniform float shape_span = 2.0;
// Ruido fino del borde, en fraccion del radio y siempre hacia adentro.
uniform float edge_wobble : hint_range(0.0, 0.1) = 0.03;
uniform float edge_scale = 1.6;
// Metros que la mancha corroida se extiende mas alla del liquido.
uniform float stain_width = 0.35;
uniform float stain_opacity : hint_range(0.0, 1.0) = 0.7;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.04;
uniform float vein_threshold : hint_range(0.0, 1.0) = 0.7;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.6;
// Metros de cada celda de burbujas y cuantas celdas tienen una.
uniform float bubble_cell = 0.55;
uniform float bubble_density : hint_range(0.0, 1.0) = 0.35;
uniform float bubble_speed = 0.45;

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

vec2 hash22(vec2 p) {
	return vec2(hash21(p), hash21(p + 19.19));
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

// Una burbuja por celda como mucho, que crece y revienta. Devuelve
// (altura del domo, destello del reventon).
vec2 bubble(vec2 p) {
	vec2 cell = floor(p / bubble_cell);
	vec2 rnd = hash22(cell);
	if (rnd.x > bubble_density) {
		return vec2(0.0);
	}
	float life = fract(TIME * bubble_speed * (0.6 + rnd.y) + rnd.y * 7.0);
	vec2 center = (cell + 0.3 + 0.4 * hash22(cell + 3.1)) * bubble_cell;
	float max_r = bubble_cell * (0.12 + 0.12 * rnd.y);
	float r = max_r * smoothstep(0.0, 0.85, life);
	float d = length(p - center);
	float dome = life < 0.9 ? sqrt(max(1.0 - (d * d) / max(r * r, 1e-5), 0.0)) : 0.0;
	// El reventon: un anillo que se abre y se apaga en el ultimo 10% de vida.
	float pop_t = clamp((life - 0.9) / 0.1, 0.0, 1.0);
	float pop_r = max_r * (1.0 + pop_t * 0.8);
	float pop = (1.0 - smoothstep(0.0, max_r * 0.25, abs(d - pop_r)))
		* step(0.9, life) * (1.0 - pop_t);
	return vec2(dome, pop);
}

float ripples(vec2 p) {
	return sin(p.x * 3.1 + TIME * 1.3) * 0.5
		+ sin(p.y * 2.7 - TIME * 1.1 + p.x * 0.8) * 0.5
		+ (value_noise(p * 1.8 + TIME * 0.25) - 0.5);
}

void fragment() {
	float r = length(local_xz);
	float px = fwidth(r);
	if (r > 1.15) {
		discard;
	}

	// El contorno del charco: la misma cuenta que HazardZone.reach_at().
	float angle = atan(local_xz.y, local_xz.x);
	float wave = shape_weights.x * sin(2.0 * angle + shape_phase.x)
		+ shape_weights.y * sin(3.0 * angle + shape_phase.y)
		+ shape_weights.z * sin(5.0 * angle + shape_phase.z);
	float reach = 1.0 - shape_inset * clamp((wave - shape_min) / shape_span, 0.0, 1.0);
	// Ruido fino encima, anclado al mundo y solo hacia adentro: el dibujo nunca
	// pasa del contorno que lastima.
	float wobble = fbm(world_xz * edge_scale + vec2(TIME * 0.05, -TIME * 0.03));
	float full_edge = spread * reach * (1.0 - edge_wobble * wobble);
	float liquid_edge = full_edge * (1.0 - evaporate);
	float liquid = 1.0 - smoothstep(liquid_edge - px, liquid_edge + px, r);
	// Distancia en metros al borde del liquido, para el menisco brillante.
	float to_edge = (liquid_edge - r) * world_radius;
	float meniscus = (1.0 - smoothstep(0.0, 0.12, to_edge)) * liquid;

	// Vetas que derivan bajo la superficie: el mismo truco de dos capas del
	// lava_pool, que no se repite a simple vista.
	vec2 uv_a = world_xz * 0.5 + vec2(TIME * flow_speed, TIME * flow_speed * 0.6);
	vec2 uv_b = world_xz * 0.8 - vec2(TIME * flow_speed * 0.7, TIME * flow_speed * 0.4);
	float mask = texture(noise_texture, uv_a).r * texture(noise_texture, uv_b).r;
	float veins = smoothstep(vein_threshold - 0.06, vein_threshold + 0.06, mask);

	vec2 b = bubble(world_xz);

	// Relieve por diferencias finitas: ondas + domos de las burbujas.
	float e = 0.02;
	float h0 = ripples(world_xz) * 0.02 * ripple_strength + b.x * 0.04;
	float hx = ripples(world_xz + vec2(e, 0.0)) * 0.02 * ripple_strength
		+ bubble(world_xz + vec2(e, 0.0)).x * 0.04;
	float hz = ripples(world_xz + vec2(0.0, e)) * 0.02 * ripple_strength
		+ bubble(world_xz + vec2(0.0, e)).x * 0.04;
	vec3 n_liquid = normalize(vec3(-(hx - h0) / e, 1.0, -(hz - h0) / e));
	vec3 n_world = normalize(mix(vec3(0.0, 1.0, 0.0), n_liquid, liquid));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Mancha corroida alrededor: sigue el contorno, se deshilacha con ruido y
	// se aclara hacia afuera. Sin emision - el piso quemado no avisa nada, el
	// liquido si. Recortada al radio, que es lo que mide el quad.
	float stain_noise = fbm(world_xz * 2.3 + 4.0);
	float stain_reach = full_edge + stain_width * (0.4 + 0.6 * stain_noise) / max(world_radius, 0.01);
	float stain_fade = 1.0 - smoothstep(full_edge, stain_reach, r);
	float stain = stain_fade * (0.55 + 0.45 * stain_noise) * stain_opacity * (1.0 - evaporate);

	vec3 liquid_albedo = mix(liquid_color.rgb, glow_color.rgb * 0.35, veins * 0.25 + b.x * 0.2);
	ALBEDO = mix(stain_color.rgb, liquid_albedo, liquid);
	ROUGHNESS = mix(0.85, 0.06, liquid);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.7, liquid);
	ALPHA = max(liquid, stain) * (1.0 - smoothstep(1.15 - 0.05, 1.15, r));

	float glow = liquid * (veins * 0.3 + b.y * 1.5 + b.x * 0.15)
		+ meniscus * 0.9;
	EMISSION = glow_color.rgb * glow * glow_energy * (1.0 - evaporate);
}
