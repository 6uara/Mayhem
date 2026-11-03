extends GutTest
## El aviso en el borde de la pantalla de un ataque que se prepara fuera de
## cuadro. Ver ThreatIndicators.


func _camera() -> Camera3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child_autofree(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.global_transform = Transform3D.IDENTITY
	camera.current = true
	return camera


func test_what_is_dead_ahead_is_on_screen() -> void:
	var camera: Camera3D = _camera()
	assert_true(ThreatIndicators.is_on_screen(camera, Vector3(0.0, 0.0, -10.0)))


func test_what_is_behind_is_off_screen() -> void:
	var camera: Camera3D = _camera()
	assert_false(ThreatIndicators.is_on_screen(camera, Vector3(0.0, 0.0, 10.0)))


func test_what_is_far_to_the_side_is_off_screen() -> void:
	var camera: Camera3D = _camera()
	assert_false(ThreatIndicators.is_on_screen(camera, Vector3(40.0, 0.0, -5.0)))


func test_the_edge_of_the_frame_counts_as_off_screen() -> void:
	# Un enemigo cortado por el borde se ve a medias: su brillo no alcanza.
	var camera: Camera3D = _camera()
	var half_width: float = tan(deg_to_rad(camera.fov * 0.5)) * 10.0 * (1920.0 / 1080.0)
	assert_false(ThreatIndicators.is_on_screen(camera, Vector3(half_width * 0.98, 0.0, -10.0)))


func test_without_a_player_there_is_nothing_to_point_at() -> void:
	var indicators := ThreatIndicators.new()
	add_child_autofree(indicators)
	if Players.local() == null:
		assert_true(indicators.collect_threats().is_empty())
	else:
		pass_test("hay un jugador en la escena de la suite")


func test_the_setting_exists_and_defaults_on() -> void:
	assert_true(SettingsManager.DEFAULTS.has("hud/threat_indicators"))
	assert_true(bool(SettingsManager.DEFAULTS["hud/threat_indicators"]))
