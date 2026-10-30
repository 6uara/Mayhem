shader_type spatial;
// El contorno de un enemigo, del color de su arquetipo (EnemyData.body_color).
//
// Casco invertido: la misma malla otra vez, inflada y dibujando solo las caras
// de atras, asi que lo unico que asoma es un borde alrededor de la silueta. Se
// infla en el espacio de la pantalla y no en metros, para que el borde mida lo
// mismo en pixeles a dos metros que a treinta: es lo que hace que un enemigo
// oscuro se lea contra el piso oscuro a cualquier distancia.
//
// La piel ya esta aplicada cuando corre vertex(), asi que sigue a los modelos
// animados. Emisivo, para que lo agarre el bloom de la arena.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.23, 0.33, 1.0);
// El ancho sale de opciones (video/enemy_outline_px) y es uno para todos:
// global, para que cambiarlo no tenga que recorrer cada enemigo del pool.
global uniform float enemy_outline_px;
uniform float energy = 1.6;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 clip_normal = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(clip_normal) > 0.0001) {
		clip.xy += normalize(clip_normal) * enemy_outline_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * energy;
}
