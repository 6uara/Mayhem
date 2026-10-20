shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
// La superficie de las piezas greybox: chapa de placas atornilladas en vez de
// una caja de un solo color.
//
// Todo es procedural y en espacio de mundo, sin texturas ni UVs. Dos razones:
// las piezas se dibujan en MultiMesh compartiendo una caja por medida, asi que
// cualquier patron en UV se repetiria igual en cada celda y marcaria la
// grilla; y en mundo las juntas de un piso 3x3 siguen de corrido a la
// baldosa de al lado, que es lo que hace que el suelo lea como un suelo y no
// como trescientas cajas.
//
// El color sigue siendo el `greybox_color` de la pieza: el shader le pone
// materia, no le cambia el significado. Una rampa sigue siendo la rampa ocre.
//
// La posicion y la normal salen de INV_VIEW_MATRIX en el fragment y no de
// MODEL_MATRIX en el vertex: asi no depende de como el MultiMesh compone la
// transformacion de cada instancia.

uniform vec4 albedo : source_color = vec4(0.52, 0.53, 0.56, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.15;
// Metros de cada placa en el piso. La celda mide 4: con 2 entran cuatro placas
// por celda y las juntas caen siempre sobre los bordes de celda.
uniform float plate_size = 2.0;
// Placas de las caras verticales: ancho y alto. 1.5 de alto parte una pared de
// un nivel (3 m) en dos bandas.
uniform vec2 side_plate_size = vec2(2.0, 1.5);
uniform float seam_width : hint_range(0.0, 0.1) = 0.02;
uniform float bevel_width : hint_range(0.0, 0.2) = 0.05;
uniform float seam_darken : hint_range(0.0, 1.0) = 0.55;
uniform float bump_strength : hint_range(0.0, 4.0) = 1.0;
// Cuanto varia el brillo de una placa a otra. Poco: es lo que rompe el
// "todo el mismo gris" sin convertirse en un tablero de ajedrez.
uniform float plate_variation : hint_range(0.0, 0.3) = 0.07;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.25;
uniform float grime_scale = 0.18;
// Chapa antideslizante (diamante) sobre las caras de arriba. La activan las
// piezas elevadas: el mismo piso en el nivel 0 es liso y en el 1 es pasarela.
uniform float tread_strength : hint_range(0.0, 1.0) = 0.0;
uniform float tread_density = 6.0;
uniform float bolt_radius : hint_range(0.0, 0.1) = 0.035;
uniform float bolt_inset : hint_range(0.0, 0.5) = 0.14;

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
		p = p * 2.03 + vec2(17.1, 9.4);
		amplitude *= 0.5;
	}
	return total;
}

// Distancia en metros a la junta mas cercana, por eje.
vec2 seam_distance(vec2 p, vec2 size) {
	vec2 f = fract(p / size);
	return min(f, 1.0 - f) * size;
}

// Relieve: 0 en el fondo de la junta, 1 sobre la placa. El bisel es la rampa
// entre los dos, que es lo que agarra la luz.
float plate_height(vec2 p, vec2 size) {
	vec2 d = seam_distance(p, size);
	float edge = min(d.x, d.y);
	return smoothstep(seam_width, seam_width + bevel_width, edge);
}

// Diamante antideslizante: lozenges cortos que alternan de orientacion por
// celda, como la chapa de una pasarela industrial.
float tread_height(vec2 p) {
	vec2 q = p * tread_density;
	vec2 cell = floor(q);
	vec2 f = fract(q) - 0.5;
	bool flip = mod(cell.x + cell.y, 2.0) > 0.5;
	float c = 0.7071;
	vec2 r = flip ? vec2(c * f.x + c * f.y, -c * f.x + c * f.y)
		: vec2(c * f.x - c * f.y, c * f.x + c * f.y);
	float lozenge = length(r * vec2(1.0, 4.0));
	return 1.0 - smoothstep(0.22, 0.32, lozenge);
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 a = abs(world_normal);

	// Proyeccion por el eje dominante, sin mezclar: las piezas son cajas
	// alineadas, y una mezcla triplanar solo sumaria juntas fantasma en las
	// aristas.
	bool top = a.y >= a.x && a.y >= a.z;
	vec2 p;
	vec3 tangent;
	vec3 bitangent;
	vec2 size;
	if (top) {
		p = world_pos.xz;
		tangent = vec3(1.0, 0.0, 0.0);
		bitangent = vec3(0.0, 0.0, 1.0);
		size = vec2(plate_size);
	} else if (a.x >= a.z) {
		p = world_pos.zy;
		tangent = vec3(0.0, 0.0, 1.0);
		bitangent = vec3(0.0, 1.0, 0.0);
		size = side_plate_size;
	} else {
		p = world_pos.xy;
		tangent = vec3(1.0, 0.0, 0.0);
		bitangent = vec3(0.0, 1.0, 0.0);
		size = side_plate_size;
	}

	// Metros por pixel: de lejos el detalle fino se apaga en vez de
	// titilar. La junta aguanta mas que el diamante porque es mas ancha.
	float footprint = length(fwidth(p));
	float seam_fade = 1.0 - smoothstep(0.03, 0.12, footprint);
	float tread_fade = (1.0 - smoothstep(0.01, 0.04, footprint))
		* (top ? tread_strength : 0.0);

	vec2 plate_id = floor(p / size);
	float plate_rand = hash21(plate_id + (top ? 0.0 : 71.0));
	vec2 local = fract(p / size) * size;

	// Tornillos en las cuatro esquinas de cada placa.
	vec2 corner = min(local, size - local);
	float bolt_d = length(corner - vec2(bolt_inset));
	float bolt = (1.0 - smoothstep(bolt_radius * 0.8, bolt_radius, bolt_d)) * seam_fade;
	float bolt_ring = smoothstep(bolt_radius * 0.8, bolt_radius, bolt_d)
		* (1.0 - smoothstep(bolt_radius, bolt_radius * 1.5, bolt_d)) * seam_fade;

	// Relieve por diferencias finitas: una sola funcion de altura para
	// juntas, diamante y tornillos, y la normal sale sola.
	float e = 0.006;
	float h0 = plate_height(p, size) + tread_height(p) * 0.25 * tread_fade;
	float hx = plate_height(p + vec2(e, 0.0), size)
		+ tread_height(p + vec2(e, 0.0)) * 0.25 * tread_fade;
	float hy = plate_height(p + vec2(0.0, e), size)
		+ tread_height(p + vec2(0.0, e)) * 0.25 * tread_fade;
	vec2 grad = vec2(hx - h0, hy - h0) / e * 0.02 * bump_strength * seam_fade;
	vec3 bumped = normalize(world_normal - tangent * grad.x - bitangent * grad.y);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	float groove = 1.0 - plate_height(p, size);
	float grime = fbm(p * grime_scale + plate_rand * 3.0);
	// La mugre se junta en las juntas: es lo primero que delata que la
	// superficie se usa.
	float dirt = clamp(grime * grime_strength + groove * 0.35 * grime_strength, 0.0, 1.0);

	vec3 color = albedo.rgb * (1.0 + (plate_rand - 0.5) * 2.0 * plate_variation);
	color *= 1.0 - groove * seam_darken * seam_fade;
	color *= 1.0 - dirt * 0.45;
	color *= 1.0 - bolt_ring * 0.4;
	color = mix(color, albedo.rgb * 1.25, bolt * 0.6);
	float tread = tread_height(p) * tread_fade;
	color *= 1.0 + tread * 0.08;

	ALBEDO = color;
	METALLIC = mix(metallic, 0.8, max(bolt, tread * 0.5));
	// Lo pisado y los tornillos brillan, la mugre y las juntas no.
	ROUGHNESS = clamp(roughness + dirt * 0.25 + groove * 0.1 * seam_fade
		- tread * 0.25 - bolt * 0.35, 0.05, 1.0);
}
