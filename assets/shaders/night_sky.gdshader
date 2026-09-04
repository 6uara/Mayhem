shader_type sky;

// El cielo nocturno del coliseo.
//
// Un shader de cielo y no un ProceduralSkyMaterial porque hacen falta dos cosas
// que ese no da: estrellas, y un resplandor de ciudad en el horizonte que no sea
// un sol. Lo segundo es lo que hace que el skyline se lea - una silueta oscura
// contra un cielo negro no es una silueta, es nada.
//
// Cuesta lo que cuesta cualquier cielo: se evalua una vez por pixel de fondo, y
// en una arena cerrada casi todo el fondo esta tapado por las gradas.

uniform vec3 zenith_color : source_color = vec3(0.012, 0.016, 0.035);
uniform vec3 horizon_color : source_color = vec3(0.09, 0.05, 0.14);
// El halo de la ciudad, justo sobre la linea del horizonte.
uniform vec3 glow_color : source_color = vec3(0.55, 0.18, 0.42);
uniform float glow_falloff : hint_range(1.0, 64.0) = 18.0;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.9;

uniform float star_density : hint_range(0.0, 1.0) = 0.16;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;
// Cuanto titilan. En 0 quedan fijas.
uniform float star_twinkle : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453123);
}

// Estrellas por celda: una por celda como mucho, en una posicion propia dentro
// de ella. Sembradas sobre una grilla y no con ruido continuo para que ninguna
// aparezca al lado de otra formando manchas.
float stars(vec3 direction) {
	vec2 grid = vec2(atan(direction.x, direction.z), acos(clamp(direction.y, -1.0, 1.0)))
		* vec2(46.0, 46.0);
	vec2 cell = floor(grid);
	float seed = hash(cell);
	if (seed > star_density) {
		return 0.0;
	}
	vec2 offset = vec2(hash(cell + 3.7), hash(cell + 9.1));
	float distance_to = length(fract(grid) - offset);
	float point = smoothstep(0.09, 0.0, distance_to);
	// Cada una titila a su ritmo, o la boveda entera late junta.
	float flicker = mix(1.0, 0.55 + 0.45 * sin(TIME * (0.7 + seed * 2.5) + seed * 30.0),
		star_twinkle);
	return point * flicker * (0.35 + seed * 2.0);
}

void sky() {
	float height = clamp(EYEDIR.y, -1.0, 1.0);
	vec3 base = mix(horizon_color, zenith_color, smoothstep(0.0, 0.55, height));

	// El resplandor solo sube desde el horizonte: por debajo no hay cielo que
	// mirar, y por encima la ciudad no llega.
	float halo = pow(max(1.0 - abs(height), 0.0), glow_falloff);
	base += glow_color * halo * glow_strength;

	// Las estrellas se apagan cerca del horizonte, tapadas por el mismo halo.
	base += vec3(stars(EYEDIR)) * star_brightness
		* smoothstep(0.02, 0.30, height);

	COLOR = base;
}
