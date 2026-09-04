shader_type spatial;
render_mode cull_back, shadows_disabled, specular_disabled, unshaded;

// Las torres del skyline: cajas oscuras con ventanas encendidas.
//
// Cajas de verdad y no billboards, aunque esten a trescientos metros. Un anillo
// de billboards gira con la camara, y el jugador de este juego se mueve todo el
// tiempo -corre, dashea, se cuelga de un gancho- asi que ese giro se notaria en
// cada desplazamiento. Una caja son doce triangulos y da paralaje de verdad.
//
// Unshaded a proposito: son siluetas contra el cielo. Iluminarlas de noche solo
// las volveria grises.
//
// INSTANCE_CUSTOM, sembrado por CitySkyline:
//   x - semilla propia de la torre
//   y - que fraccion de sus ventanas esta encendida
//   z - color de las ventanas: frio o calido
//   w - sin usar

uniform vec3 body_color : source_color = vec3(0.035, 0.032, 0.055);
uniform vec3 window_cold : source_color = vec3(0.45, 0.85, 1.0);
uniform vec3 window_warm : source_color = vec3(1.0, 0.62, 0.25);
uniform float window_energy : hint_range(0.0, 8.0) = 2.6;
// Ventanas por metro de fachada. Fijo en metros y no en UV para que una torre
// ancha no tenga ventanas anchas.
uniform float windows_per_metre : hint_range(0.05, 2.0) = 0.34;
// La luz roja de la punta, que es lo que dice "esto es alto".
uniform vec3 beacon_color : source_color = vec3(1.0, 0.15, 0.2);

varying vec3 v_local;
varying vec3 v_size;
varying float v_seed;
varying float v_lit_share;
varying float v_warmth;
varying vec3 v_normal_local;

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	v_local = VERTEX;
	v_size = vec3(
		length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	v_seed = INSTANCE_CUSTOM.x;
	v_lit_share = INSTANCE_CUSTOM.y;
	v_warmth = INSTANCE_CUSTOM.z;
	v_normal_local = NORMAL;
}

void fragment() {
	// Sin salidas tempranas: el lenguaje de shaders de Godot no acepta `return`
	// dentro de fragment(), asi que las dos caras se resuelven y se elige.
	bool is_roof = abs(v_normal_local.y) > 0.5;

	// La cara de arriba no lleva ventanas: lleva la baliza roja de la punta, que
	// es lo que dice "esto es alto".
	float to_middle = length(v_local.xz);
	vec3 roof = to_middle < 0.12
		? beacon_color * (0.4 + 0.6 * abs(sin(TIME * 1.6 + v_seed * 10.0)))
		: body_color;

	// La fachada que toca: la que mira a X o la que mira a Z.
	vec2 facade = abs(v_normal_local.x) > 0.5
		? vec2(v_local.z * v_size.z, v_local.y * v_size.y)
		: vec2(v_local.x * v_size.x, v_local.y * v_size.y);
	vec2 cell = floor(facade * windows_per_metre);
	vec2 inside = fract(facade * windows_per_metre);

	// El marco entre ventana y ventana.
	float pane = step(0.18, inside.x) * step(inside.x, 0.82)
		* step(0.25, inside.y) * step(inside.y, 0.78);
	float lit = step(hash(cell + v_seed * 71.0), v_lit_share) * pane;
	vec3 window = mix(window_cold, window_warm, step(0.5, v_warmth));
	vec3 wall = mix(body_color, window * window_energy, lit);

	ALBEDO = is_roof ? roof : wall;
}
