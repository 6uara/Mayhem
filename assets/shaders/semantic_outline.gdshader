shader_type spatial;
// El borde de lo que se juega: anclas de gancho, pads, plataformas,
// puertas de spawn mientras salen enemigos, municion y gadgets tirados, cada uno en el color de su
// significado (TelegraphComponent.get_color(), el acento del gadget).
//
// Es la regla del estilo Claridad (VisualStyle): **si tiene borde, importa**, y
// el color dice que hace. El mapa no lleva borde -con todo delineado nada se
// destacaba- y los enemigos tienen el suyo (enemy_outline.gdshader).
//
// La misma tecnica que el de los enemigos: casco invertido inflado en pixeles de
// pantalla, asi mide lo mismo cerca y lejos. Lo pone SemanticOutline como
// overlay del objeto. Con el ancho global en 0 (otros estilos) no dibuja nada.
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.69, 0.13, 1.0);
global uniform float semantic_outline_px;
uniform float energy = 1.4;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 clip_normal = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(clip_normal) > 0.0001) {
		clip.xy += normalize(clip_normal) * semantic_outline_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	if (semantic_outline_px <= 0.0) {
		discard;
	}
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * energy;
}
