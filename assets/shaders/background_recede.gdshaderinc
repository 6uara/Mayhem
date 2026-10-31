// Lo que es fondo -el cuenco del coliseo, el publico, la ciudad, la pared de
// energia- retrocede en el estilo Claridad (VisualStyle): menos color y menos
// brillo, para que lo que se juega (enemigos, lo que se usa, lo que se levanta)
// sea lo unico que salta a la vista.
//
// Existe porque el fondo era lo mas fuerte de la pantalla, y en cyan: el color
// que la ley reserva para "lo tuyo" (Tokens.PLAYER) ocupaba media imagen sin
// significar nada. Un jugador nuevo no tenia como saber que mirar.
//
// 0 en el estilo Estandar: sin cambios. Global para que cambiar de estilo no
// tenga que recorrer cada material del venue.
global uniform float background_dim;

// `strength` escala el efecto por superficie: la pared de energia es limite de
// juego y retrocede menos que la ciudad.
vec3 recede(vec3 color, float strength) {
	float amount = clamp(background_dim * strength, 0.0, 1.0);
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(color, vec3(luma), amount * 0.7) * (1.0 - amount * 0.55);
}
