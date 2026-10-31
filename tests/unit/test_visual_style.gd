extends GutTest
## Los estilos visuales: que cada uno ponga lo suyo, no toque lo ajeno, y que
## volver al estandar deje todo como estaba.

var _was: int


func before_each() -> void:
	_was = VisualStyle.style


func after_each() -> void:
	VisualStyle.set_style(_was as VisualStyle.Style)


func _lit_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.metallic = 0.8
	material.normal_enabled = true
	return material


func test_a_lit_material_turns_toon_and_comes_back() -> void:
	var material: StandardMaterial3D = _lit_material()
	assert_true(VisualStyle.convert_material(material))
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON)
	assert_eq(material.specular_mode, BaseMaterial3D.SPECULAR_DISABLED)
	assert_eq(material.metallic, 0.0)
	assert_false(material.normal_enabled)

	VisualStyle.restore_material(material)
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY)
	assert_eq(material.specular_mode, BaseMaterial3D.SPECULAR_SCHLICK_GGX)
	assert_almost_eq(material.metallic, 0.8, 0.001)
	assert_true(material.normal_enabled)


## Las texturas aplanadas que escribe tools/blender/flatten_textures.py.
func test_a_model_texture_swaps_to_its_flat_version_and_back() -> void:
	var original: Texture2D = load("res://assets/models/props/ramp_Image_0.jpg") as Texture2D
	var material: StandardMaterial3D = _lit_material()
	material.albedo_texture = original
	VisualStyle.convert_material(material)
	assert_eq(material.albedo_texture.resource_path,
		"res://assets/models/props/ramp_Image_0_toon.png")
	VisualStyle.restore_material(material)
	assert_eq(material.albedo_texture, original)


func test_a_texture_without_a_flat_version_is_kept() -> void:
	var material: StandardMaterial3D = _lit_material()
	material.albedo_texture = ImageTexture.create_from_image(
		Image.create(4, 4, false, Image.FORMAT_RGB8))
	var texture: Texture2D = material.albedo_texture
	VisualStyle.convert_material(material)
	assert_eq(material.albedo_texture, texture)


## Un VFX o un contorno ya tienen su propio look: la luz en bandas no les cambia
## nada y tocarlos solo ensuciaria la lista de lo convertido.
func test_unshaded_and_shader_materials_are_left_alone() -> void:
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	assert_false(VisualStyle.convert_material(unshaded))
	assert_eq(unshaded.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY)
	assert_false(VisualStyle.convert_material(ShaderMaterial.new()))


func _mesh_with(material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	var instance := MeshInstance3D.new()
	add_child_autofree(instance)
	# Asignada despues del add_child, como la arma mucho codigo del juego.
	mesh.material = material
	instance.mesh = mesh
	return instance


func test_toon_converts_a_mesh_entering_the_tree() -> void:
	VisualStyle.set_style(VisualStyle.Style.TOON)
	var material: StandardMaterial3D = _lit_material()
	_mesh_with(material)
	await wait_process_frames(2)
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON)


## El neon es una capa encima: los materiales quedan como llegaron.
func test_neon_leaves_materials_as_modelled() -> void:
	VisualStyle.set_style(VisualStyle.Style.NEON)
	var material: StandardMaterial3D = _lit_material()
	_mesh_with(material)
	await wait_process_frames(2)
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY)
	assert_true(material.normal_enabled)


func test_every_camera_gets_edges_and_loses_them_in_standard() -> void:
	VisualStyle.set_style(VisualStyle.Style.NEON)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	await wait_process_frames(2)
	assert_not_null(VisualStyle.get_edges(camera))

	VisualStyle.set_style(VisualStyle.Style.STANDARD)
	assert_null(VisualStyle.get_edges(camera))


## En neon el arma queda como esta: en la pasada del toon se notaba demasiado.
func test_neon_draws_no_edge_on_the_first_person_weapon() -> void:
	VisualStyle.set_style(VisualStyle.Style.NEON)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	await wait_process_frames(2)
	assert_null(VisualStyle.get_edges(camera))


func test_switching_style_swaps_the_edge_kind() -> void:
	VisualStyle.set_style(VisualStyle.Style.NEON)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	await wait_process_frames(2)
	var neon: Material = VisualStyle.get_edges(camera).material_override
	VisualStyle.set_style(VisualStyle.Style.TOON)
	assert_ne(VisualStyle.get_edges(camera).material_override, neon)


## La pasada de transmision es de la partida: sin jugador (menu, pruebas) no se ve.
func test_the_broadcast_pass_needs_a_player() -> void:
	VisualStyle.set_style(VisualStyle.Style.NEON)
	await wait_process_frames(2)
	assert_eq(VisualStyle.is_broadcast_visible(), Players.local() != null)


func test_the_default_ink_width_is_the_token() -> void:
	assert_eq(float(SettingsManager.DEFAULTS["video/toon_line_px"]), Tokens.TOON_LINE_PX)
