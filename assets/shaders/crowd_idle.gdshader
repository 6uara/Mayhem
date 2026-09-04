shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// El idle del publico, hecho en el vertex y no en _process().
//
// Son mil y pico de espectadores y ninguno hace nada que el jugador vaya a
// mirar de cerca: mover cada uno desde GDScript seria mil transformadas por
// cuadro para un detalle de fondo. Aca cada instancia se mueve sola, y el costo
// no cambia si manana el publico es el doble.
//
// El desfase sale de INSTANCE_CUSTOM.x, que CrowdStands siembra por asiento. Sin
// eso la tribuna entera sube y baja al mismo tiempo y se lee como una sola pieza
// respirando, que es peor que si no se moviera nada.

uniform float bob_amplitude : hint_range(0.0, 0.5) = 0.11;
uniform float bob_speed : hint_range(0.0, 8.0) = 2.4;
uniform float sway_amplitude : hint_range(0.0, 0.3) = 0.04;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	// Cada uno a su propio ritmo ademas de su propio desfase: con una sola
	// frecuencia la tribuna termina sincronizandose sola a la vista.
	float rate = bob_speed * (0.7 + INSTANCE_CUSTOM.y * 0.6);
	VERTEX.y += sin(TIME * rate + phase) * bob_amplitude;
	VERTEX.x += cos(TIME * rate * 0.5 + phase) * sway_amplitude;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}
