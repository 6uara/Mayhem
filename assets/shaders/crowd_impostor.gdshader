shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, shadows_disabled,
	specular_disabled, diffuse_lambert, depth_prepass_alpha;

// El publico: un quad por espectador, siempre de frente a la camara, con la
// silueta dibujada aca adentro.
//
// Sin textura a proposito. Un atlas de siluetas seria un archivo mas que
// mantener y una decision de arte tomada antes de tiempo; dibujarla en el
// fragment cuesta unas pocas cuentas, deja que cada espectador tenga sus
// proporciones, y el dia que haya arte de verdad se cambia este archivo y nada
// mas. Lo que importa hoy es que de lejos se lea "persona" y no "capsula".
//
// Todo el movimiento vive aca por la misma razon que antes: son miles y nadie
// los va a mirar de cerca, asi que ninguno puede costar un Node3D ni un frame de
// _process(). Lo que el juego le cuenta a la tribuna son dos numeros -cuanto se
// entusiasma y por donde va la ola- y cada uno reacciona solo.
//
// INSTANCE_CUSTOM, sembrado por CrowdStands:
//   x - desfase propio, para que no respiren todos juntos
//   y - ritmo propio, para que no se sincronicen solos con el tiempo
//   z - que clase de espectador es: pancarta, celular, o nada
//   w - donde esta dando la vuelta al estadio, 0..1, para que la ola viaje

group_uniforms Animacion;
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float idle_bob : hint_range(0.0, 0.5) = 0.06;
uniform float jump_height : hint_range(0.0, 1.5) = 0.45;
uniform float bob_speed : hint_range(0.0, 8.0) = 2.2;

group_uniforms Ola;
// Por donde va la cresta, dando la vuelta al estadio. Fuera de 0..1 no hay ola.
uniform float wave_position = -1.0;
uniform float wave_width : hint_range(0.01, 0.5) = 0.07;

group_uniforms Detalles;
// Cuantos prenden el celular. En 0 no hay ninguno.
uniform float phone_share : hint_range(0.0, 1.0) = 0.0;
uniform vec3 phone_color : source_color = vec3(0.85, 0.93, 1.0);
// Cuantos levantan pancarta.
uniform float sign_share : hint_range(0.0, 1.0) = 0.05;
uniform vec3 sign_color : source_color = vec3(1.0, 0.69, 0.13);

varying float v_stand;
varying vec3 v_tint;
varying float v_trait;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	float rate = bob_speed * (0.7 + INSTANCE_CUSTOM.y * 0.6);
	v_trait = INSTANCE_CUSTOM.z;
	v_tint = COLOR.rgb;

	// Cuanto esta parado este, entre el entusiasmo general y la ola que le pasa
	// por encima. La ola gana cuando pasa: es un gesto que recorre la tribuna y
	// tiene que verse aunque el resto este sentado.
	float ring = INSTANCE_CUSTOM.w;
	float to_crest = abs(fract(ring - wave_position + 0.5) - 0.5);
	float wave = wave_position < 0.0
		? 0.0
		: smoothstep(wave_width, 0.0, to_crest);
	// El entusiasmo no levanta a todos a la vez: cada uno tiene su propio umbral,
	// asi que la tribuna se va parando de a pedazos en vez de de golpe.
	float eager = smoothstep(INSTANCE_CUSTOM.y * 0.8, INSTANCE_CUSTOM.y * 0.8 + 0.35,
		excitement);
	v_stand = clamp(max(wave, eager), 0.0, 1.0);

	float bob = sin(TIME * rate + phase) * idle_bob;
	// Parado salta, sentado apenas respira.
	float hop = abs(sin(TIME * rate * 1.6 + phase)) * jump_height * v_stand;

	// De frente a la camara, girando solo sobre el eje Y: son personas paradas y
	// una silueta que se tumbe hacia la camara se lee como un cartel.
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - origin;
	to_camera.y = 0.0;
	vec3 forward = length(to_camera) > 0.0001
		? normalize(to_camera)
		: vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));

	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	// El quad viene centrado y el espectador se planta en su asiento, asi que se
	// lo sube media altura: el origen de la instancia son los pies.
	vec3 world = origin
		+ right * (VERTEX.x * width)
		+ vec3(0.0, (VERTEX.y + 0.5) * height + bob + hop, 0.0);

	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = (VIEW_MATRIX * vec4(forward, 0.0)).xyz;
}

// Distancia a un segmento, que es con lo que se dibujan el torso y los brazos:
// una capsula plana y no un rectangulo, para que las puntas salgan redondeadas
// sin ningun caso especial.
float segment(vec2 point, vec2 from, vec2 to) {
	vec2 span = to - from;
	float t = clamp(dot(point - from, span) / dot(span, span), 0.0, 1.0);
	return length(point - from - span * t);
}

void fragment() {
	// Coordenadas centradas en el eje del cuerpo: x = 0 en el medio, y = 0 en
	// los pies. Asi la silueta se escribe con las proporciones a la vista.
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);

	float stand = v_stand;
	// Sentado ocupa menos alto y mas ancho; parado se estira. Es lo que hace que
	// una tribuna que se levanta se note desde el piso de la arena.
	float top = mix(0.74, 0.96, stand);
	float hip = mix(0.30, 0.40, stand);

	float head = length((p - vec2(0.0, top - 0.07)) * vec2(1.35, 1.0)) - 0.075;
	float torso = segment(p, vec2(0.0, hip), vec2(0.0, top - 0.17)) - 0.115;

	// Los brazos solo aparecen levantados: sentado quedan contra el cuerpo y no
	// agregan nada que se vea a cuarenta metros.
	float arm_reach = mix(0.0, 1.0, stand);
	float shoulder_y = top - 0.20;
	vec2 hand = vec2(0.20, shoulder_y + 0.20 * arm_reach);
	float arms = min(
		segment(p, vec2(-0.09, shoulder_y), vec2(-hand.x, hand.y)),
		segment(p, vec2(0.09, shoulder_y), hand)) - 0.045;
	arms = mix(1.0, arms, arm_reach);

	float body = min(min(head, torso), arms);

	vec3 albedo = v_tint;
	float alpha = body < 0.0 ? 1.0 : 0.0;

	// La pancarta va arriba de las manos, y solo cuando las manos estan arriba.
	if (v_trait < sign_share && stand > 0.5) {
		vec2 banner = p - vec2(0.0, top + 0.16);
		if (abs(banner.x) < 0.24 && abs(banner.y) < 0.085) {
			albedo = sign_color;
			alpha = 1.0;
		}
	}
	// El celular es un punto brillante a la altura del pecho. Cuesta un if y es
	// lo que hace que la tribuna se lea como gente incluso cuando esta quieta.
	if (v_trait > 1.0 - phone_share) {
		if (length((p - vec2(0.11, shoulder_y - 0.04)) * vec2(1.0, 1.0)) < 0.035) {
			albedo = phone_color;
			alpha = 1.0;
		}
	}

	if (alpha < 0.5) {
		discard;
	}
	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
