shader_type spatial;
// Lineas sobre los bordes del mundo, en un solo pase de pantalla: donde la
// profundidad salta o la superficie dobla. VisualStyle lo usa de dos formas:
//
// - Toon: tinta oscura en siluetas y quiebres (line_color oscuro, energy 1).
// - Neon: un filo de luz solo en las siluetas y solo del lado del objeto
//   (near_side_only, normales apagadas con normal_threshold > 2), con energia
//   por encima de 1 para que el glow de la arena lo levante. Sobre un juego de
//   noche una linea oscura no tiene contra que leerse; una clara si.
//
// El ancho (line_px) es la distancia de muestreo, asi que la franja donde se
// detecta el borde -la linea- crece con el.
//
// Va en un quad pegado a la camara (VisualStyle lo pone) y no como un casco
// invertido por malla, como el de los enemigos: duplicar cada malla de la arena
// duplica draw calls, y con la ola 10 el techo ya es la CPU. Esto cuesta lo mismo
// con un enemigo que con cuarenta, y lo paga la GPU.
//
// Lo que no escribe profundidad (particulas, VFX, transparentes) no recibe linea,
// a proposito: un fogonazo con borde negro deja de leerse como luz.
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never,
	cull_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform vec4 line_color : source_color = vec4(0.027, 0.031, 0.043, 1.0);
// Por encima de 1 la linea entra al glow (es unshaded: el color sale tal cual).
uniform float line_energy = 1.0;
// Ancho en pixeles de la resolucion de render.
uniform float line_px = 3.0;
// Cuanto tiene que saltar la profundidad, relativa a la del pixel, para que haya
// linea. Relativa y por segunda derivada: un piso visto de costado cambia mucho
// de profundidad pero en forma pareja, y no tiene que llenarse de rayas.
uniform float depth_threshold = 0.04;
// 1 - coseno entre normales vecinas a partir del cual hay linea (0.3 ~ 45
// grados). Por encima de 2 nunca hay: solo siluetas.
uniform float normal_threshold = 0.3;
// Solo el lado cercano del borde: el filo queda sobre el objeto y no como un
// halo sobre lo que tiene detras.
uniform bool near_side_only = false;
// Desde donde la linea se va apagando, en metros: lejos todo es borde y la
// ciudad del fondo se volveria ruido.
uniform float fade_start = 90.0;
uniform float fade_end = 160.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
	// Cielo: profundidad 0 con z invertida. Sin esto la division da infinito, el
	// resto de la cuenta da NaN y el cielo entero sale del color de la linea.
	if (raw <= 0.000001) {
		return 100000.0;
	}
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return min(-view.z / view.w, 100000.0);
}

vec3 view_normal(vec2 uv) {
	return texture(normal_texture, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 step_uv = line_px / VIEWPORT_SIZE;
	vec2 dx = vec2(step_uv.x, 0.0);
	vec2 dy = vec2(0.0, step_uv.y);

	float center = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float left = linear_depth(SCREEN_UV - dx, INV_PROJECTION_MATRIX);
	float right = linear_depth(SCREEN_UV + dx, INV_PROJECTION_MATRIX);
	float up = linear_depth(SCREEN_UV - dy, INV_PROJECTION_MATRIX);
	float down = linear_depth(SCREEN_UV + dy, INV_PROJECTION_MATRIX);
	float curvature = (abs(left + right - 2.0 * center) + abs(up + down - 2.0 * center))
		/ max(center, 0.001);
	float depth_edge = step(depth_threshold, curvature);
	if (near_side_only) {
		float farthest = max(max(left, right), max(up, down));
		depth_edge *= step(depth_threshold, (farthest - center) / max(center, 0.001));
	}

	float normal_edge = 0.0;
	if (normal_threshold <= 2.0) {
		vec3 n = view_normal(SCREEN_UV);
		float bend = max(max(1.0 - dot(n, view_normal(SCREEN_UV + dx)),
			1.0 - dot(n, view_normal(SCREEN_UV - dx))),
			max(1.0 - dot(n, view_normal(SCREEN_UV + dy)),
			1.0 - dot(n, view_normal(SCREEN_UV - dy))));
		normal_edge = step(normal_threshold, bend);
	}

	float edge = max(depth_edge, normal_edge);
	edge *= 1.0 - smoothstep(fade_start, fade_end, min(center, min(left, min(right, min(up, down)))));
	ALBEDO = line_color.rgb * line_energy;
	ALPHA = edge * line_color.a;
}
