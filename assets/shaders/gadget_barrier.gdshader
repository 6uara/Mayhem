shader_type spatial;
// El muro de la barrera: una rejilla de energia en el color del gadget, no una
// caja translucida. Se lee como algo que el jugador puso (el mismo color que su
// icono y el proyector a los pies), y la rejilla deja ver a traves lo que
// bloquea. `fade` lo apaga parejo; el parpadeo del final lo maneja TempWall.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.561, 0.827, 1.0, 1.0);
uniform float cells = 10.0;
uniform float line_width = 0.06;
uniform float fill = 0.06;
uniform float energy = 0.9;
uniform float scroll_speed = 0.35;
uniform float fade = 1.0;

void fragment() {
	vec2 uv = UV * vec2(cells * 1.333, cells);
	uv.y += TIME * scroll_speed;
	vec2 cell = abs(fract(uv) - 0.5);
	float line = smoothstep(0.5 - line_width, 0.5, max(cell.x, cell.y));
	// Borde mas brillante, para que el contorno del muro se vea de canto.
	float edge = 1.0 - smoothstep(0.0, 0.04, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	float strength = clamp(fill + line * 0.9 + edge, 0.0, 2.0);
	ALBEDO = color.rgb * strength * energy * fade;
}
