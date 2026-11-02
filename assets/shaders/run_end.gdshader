shader_type canvas_item;
// El fondo de la pantalla de fin, que es lo que dice "ganaste" o "perdiste"
// antes de leer una palabra. Va sobre la partida congelada, oscureciendola.
//
// Victoria (`mood` = 1): una luz calida que baja desde arriba, rayos lentos y
// chispas que suben. Derrota (`mood` = 0): el borde se cierra en rojo, lineas de
// barrido y una franja de interferencia que pasa cada tanto, como una
// transmision que se corta.
//
// Sin lectura de pantalla: todo se compone encima, alfa sobre alfa. `motion` en
// 0 lo deja quieto (reduce_flashing). Los colores llegan desde Tokens en
// run_summary.gd.

uniform float mood : hint_range(0.0, 1.0) = 0.0;
uniform float motion : hint_range(0.0, 1.0) = 1.0;
// Cuanto tapa la partida de atras.
uniform float dim : hint_range(0.0, 1.0) = 0.86;
uniform vec4 base_color : source_color = vec4(0.027, 0.031, 0.043, 1.0);
uniform vec4 win_color : source_color = vec4(1.0, 0.69, 0.125, 1.0);
uniform vec4 lose_color : source_color = vec4(1.0, 0.231, 0.329, 1.0);
// Lo que lleva entrar: el efecto arranca fuerte y se asienta en su nivel.
uniform float intro : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 victory(vec2 uv, vec2 aspect, float t) {
	// Luz desde arriba al centro.
	vec2 from_top = (uv - vec2(0.5, -0.15)) * aspect;
	float glow = exp(-dot(from_top, from_top) * 2.2) * 0.45;
	// Rayos: bandas angulares que giran muy lento.
	float angle = atan(from_top.x, from_top.y);
	float rays = pow(0.5 + 0.5 * sin(angle * 14.0 + t * 0.15), 6.0);
	rays *= smoothstep(1.4, 0.2, length(from_top)) * 0.12;
	// Chispas que suben: una por celda, con su propio ritmo.
	vec2 cell_uv = vec2(uv.x * aspect.x * 18.0, uv.y * 10.0 + t * 0.35);
	vec2 cell = floor(cell_uv);
	vec2 local = fract(cell_uv) - 0.5;
	float seed = hash(cell);
	float spark = step(0.86, seed) * smoothstep(0.08, 0.0, length(local + vec2(seed - 0.5, 0.0) * 0.6));
	spark *= 0.5 + 0.5 * sin(t * 3.0 + seed * 40.0);
	spark *= smoothstep(1.0, 0.3, uv.y) * 0.5;
	float light = glow + rays + spark;
	return vec4(win_color.rgb, light);
}

vec4 defeat(vec2 uv, vec2 aspect, float t) {
	// Viñeta roja desde los bordes.
	vec2 centered = (uv - 0.5) * aspect;
	float edge = smoothstep(0.55, 1.15, length(centered) * 1.25) * 0.4;
	// Barrido: lineas finas que bajan.
	float scan = 0.5 + 0.5 * sin((uv.y + t * 0.03) * 900.0);
	scan = pow(scan, 8.0) * 0.06;
	// Interferencia: una franja horizontal que cruza cada tanto.
	float band_y = fract(t * 0.13);
	float band = smoothstep(0.02, 0.0, abs(uv.y - band_y)) * step(0.55, fract(t * 0.13 * 3.0));
	band *= 0.25 * (0.6 + 0.4 * hash(vec2(floor(uv.y * 200.0), floor(t * 20.0))));
	float light = edge + scan + band;
	return vec4(lose_color.rgb, light);
}

void fragment() {
	float t = TIME * motion;
	vec2 aspect = vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	vec4 fx = mix(defeat(UV, aspect, t), victory(UV, aspect, t), mood);
	fx.a *= 1.0 + intro * 1.5;
	vec3 color = mix(base_color.rgb, fx.rgb, clamp(fx.a, 0.0, 1.0));
	COLOR = vec4(color, clamp(dim + fx.a * (1.0 - dim), 0.0, 1.0));
}
