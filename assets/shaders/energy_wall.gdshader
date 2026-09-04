shader_type spatial;
render_mode blend_add, cull_disabled, shadows_disabled, unshaded, depth_draw_never;

// El limite de la arena, hecho visible.
//
// Antes era una caja invisible: chocabas con aire y no habia nada que aprender.
// El problema de arreglarlo es que un campo de fuerza que se ve demasiado
// convierte cada pelea contra el borde en pelear a traves de un vidrio sucio, y
// eso es peor que no ver nada.
//
// La respuesta es fresnel: casi transparente cuando lo mirás de frente -que es
// cuando estas peleando contra el borde y necesitas ver- y encendido en angulo
// rasante, que es cuando estas corriendo a lo largo de el y lo que necesitas es
// saber donde termina la arena.
//
// Y sobre todo: contesta cuando lo tocas. Una onda que se abre desde el punto
// donde golpeaste es lo que convierte el limite en algo que se aprende de una
// vez, en lugar de algo que se redescubre cada vez.

const int MAX_IMPACTS = 8;

group_uniforms Aspecto;
uniform vec3 wall_color : source_color = vec3(0.208, 0.878, 0.831);
// Cuanto se ve mirandolo de frente. Bajo a proposito.
uniform float face_opacity : hint_range(0.0, 1.0) = 0.035;
// Y cuanto en angulo rasante.
uniform float edge_opacity : hint_range(0.0, 2.0) = 0.55;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;

group_uniforms Reticula;
// Metros de lado de cada hexagono.
uniform float cell_size : hint_range(0.5, 12.0) = 3.0;
uniform float line_width : hint_range(0.0, 0.3) = 0.035;
uniform float grid_strength : hint_range(0.0, 2.0) = 0.5;
// El barrido lento que sube por la pared, para que no se lea como una textura.
uniform float scan_speed : hint_range(0.0, 4.0) = 0.35;
uniform float scan_strength : hint_range(0.0, 2.0) = 0.25;

group_uniforms Impactos;
// xyz: donde se golpeo, en mundo. w: cuando, en el reloj de abajo. Un hueco sin
// usar viene con w negativo - y negativo y no cero porque ese reloj arranca en
// cero, asi que el primer golpe de la partida se fecharia como hueco vacio.
uniform vec4 impacts[MAX_IMPACTS];
// El reloj de la pared. Las ondas se fechan contra este y no contra TIME: son
// dos relojes distintos -uno lo lleva el motor, el otro arranca cuando se arma
// la arena- y una onda fechada en uno y leida en el otro sale con el radio
// equivocado o directamente no sale.
uniform float wall_time = 0.0;
uniform float ripple_speed : hint_range(1.0, 80.0) = 26.0;
uniform float ripple_life : hint_range(0.1, 4.0) = 1.1;
uniform float ripple_width : hint_range(0.1, 8.0) = 2.4;
uniform float ripple_strength : hint_range(0.0, 8.0) = 3.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Distancia al borde de hexagono mas cercano, en coordenadas de celda.
//
// Hexagonos y no cuadrados porque un enrejado cuadrado sobre una pared
// rectangular se alinea con sus bordes y se lee como el borde mismo. El
// hexagono no tiene ningun lado paralelo a la pared.
float hex_edge(vec2 point) {
	vec2 grid = vec2(point.x * 1.1547005, point.y + point.x * 0.5773503);
	vec2 cell = floor(grid);
	vec2 inside = fract(grid);
	float diagonal = inside.x + inside.y;
	// Cada rombo de la grilla se parte en dos triangulos; el borde mas cercano
	// es el mas cercano de los tres lados del que toca.
	vec3 sides = diagonal < 1.0
		? vec3(inside.x, inside.y, 1.0 - diagonal)
		: vec3(1.0 - inside.x, 1.0 - inside.y, diagonal - 1.0);
	return min(min(sides.x, sides.y), sides.z) * 0.866;
}

void fragment() {
	// Coordenadas sobre la pared, en metros: la altura, y el avance a lo largo
	// de ella. Se toman del mundo y no de la UV para que las cuatro paredes
	// tengan la reticula del mismo tamano sin importar cuanto miden.
	vec2 surface = vec2(v_world.x + v_world.z, v_world.y);

	float edge = hex_edge(surface / cell_size);
	float grid = smoothstep(line_width, 0.0, edge) * grid_strength;

	float scan = pow(max(sin((v_world.y - TIME * ripple_speed * scan_speed * 0.1)
		* 0.35) * 0.5 + 0.5, 0.0), 6.0) * scan_strength;

	// Fresnel: casi nada de frente, encendido de costado.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, fresnel_power);
	float base = mix(face_opacity, edge_opacity, rim);

	// Las ondas de los impactos. Cada una es un anillo que se abre desde donde
	// se golpeo y se apaga con el tiempo.
	float ripple = 0.0;
	for (int i = 0; i < MAX_IMPACTS; i++) {
		float age = wall_time - impacts[i].w;
		if (impacts[i].w < 0.0 || age < 0.0 || age > ripple_life) {
			continue;
		}
		float radius = age * ripple_speed;
		float to_hit = distance(v_world, impacts[i].xyz);
		float ring = smoothstep(ripple_width, 0.0, abs(to_hit - radius));
		// Se apaga con el tiempo y tambien con la distancia: una onda que llega
		// igual de fuerte a treinta metros no se lee como un golpe.
		ripple += ring * (1.0 - age / ripple_life)
			* (1.0 - clamp(radius / 40.0, 0.0, 1.0));
	}

	float amount = clamp(base + grid * (0.35 + rim) + scan * rim
		+ ripple * ripple_strength, 0.0, 4.0);
	ALBEDO = wall_color * amount;
	ALPHA = 1.0;
}
