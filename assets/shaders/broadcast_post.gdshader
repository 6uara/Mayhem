shader_type canvas_item;
// La imagen como sale al aire: el look "neon de transmision" (VisualStyle).
//
// Mayhem es un show televisado -Host, rating, cartel de LIVE- y esto lo dice en
// la imagen: un ajuste de color (mas contraste, sombras un poco mas frias),
// lineas de barrido casi invisibles, viñeta, y un corrimiento de color en los
// bordes de la pantalla que crece al recibir daño o al ir muy rapido.
//
// Todo sutil a proposito. Va debajo de la HUD (capa 1, antes que la HUD en el
// arbol), asi que los numeros quedan nitidos: lo que se toca es el mundo y el
// arma, no lo que el jugador tiene que leer. Un pase de pantalla, en la GPU.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

// Cuanto oscurecen las esquinas (0 nada).
uniform float vignette = 0.32;
// Lineas de barrido: cada cuantos pixeles de pantalla, y cuanto oscurecen.
uniform float scanline_px = 3.0;
uniform float scanline_alpha = 0.035;
// Corrimiento de color en el borde de la pantalla, en pixeles, en reposo.
uniform float aberration_px = 1.2;
// Lo que suma un golpe o la velocidad (0-1, lo maneja VisualStyle).
uniform float pulse = 0.0;
uniform float pulse_aberration_px = 7.0;
// Contraste alrededor del gris medio.
uniform float contrast = 1.07;
// Hacia donde van las sombras, y cuanto.
uniform vec4 shadow_tint : source_color = vec4(0.10, 0.16, 0.42, 1.0);
uniform float shadow_tint_amount = 0.10;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	// 0 en el centro, 1 en las esquinas.
	float radius = length(centered) * 1.4142;
	float rim = smoothstep(0.3, 1.0, radius);

	vec2 shift = normalize(centered + 0.00001) * SCREEN_PIXEL_SIZE
		* (aberration_px + pulse * pulse_aberration_px) * rim;
	vec3 color = vec3(
		texture(screen_texture, uv + shift).r,
		texture(screen_texture, uv).g,
		texture(screen_texture, uv - shift).b);

	color = (color - 0.5) * contrast + 0.5;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, color * 0.6 + shadow_tint.rgb * 0.4,
		shadow_tint_amount * (1.0 - smoothstep(0.0, 0.45, luma)));

	float scan = step(0.5, fract(FRAGCOORD.y / scanline_px));
	color *= 1.0 - scanline_alpha * scan;
	color *= 1.0 - (vignette + pulse * 0.12) * smoothstep(0.45, 1.05, radius);

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
