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


## Claridad no toca materiales: lo suyo son dos globales de shader.
func test_clarity_leaves_materials_as_modelled() -> void:
	VisualStyle.set_style(VisualStyle.Style.CLARITY)
	var material: StandardMaterial3D = _lit_material()
	_mesh_with(material)
	await wait_process_frames(2)
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY)
	assert_true(material.normal_enabled)


func test_clarity_turns_on_the_edges_of_what_matters_and_fades_the_stands() -> void:
	VisualStyle.set_style(VisualStyle.Style.CLARITY)
	assert_eq(VisualStyle.get_semantic_outline_px(),
		Tokens.SEMANTIC_OUTLINE_PX)
	assert_eq(VisualStyle.get_background_dim(),
		Tokens.BACKGROUND_DIM)
	VisualStyle.set_style(VisualStyle.Style.STANDARD)
	assert_eq(VisualStyle.get_semantic_outline_px(), 0.0)
	assert_eq(VisualStyle.get_background_dim(), 0.0)


## Con todo delineado nada se destaca: el mapa no lleva borde en Claridad.
func test_clarity_draws_no_line_over_the_map() -> void:
	VisualStyle.set_style(VisualStyle.Style.CLARITY)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	await wait_process_frames(2)
	assert_null(VisualStyle.get_edges(camera))


func test_toon_inks_every_camera_and_standard_takes_it_back() -> void:
	VisualStyle.set_style(VisualStyle.Style.TOON)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	await wait_process_frames(2)
	assert_not_null(VisualStyle.get_edges(camera))
	VisualStyle.set_style(VisualStyle.Style.STANDARD)
	assert_null(VisualStyle.get_edges(camera))


func test_an_outline_chains_behind_an_existing_overlay() -> void:
	var mesh := MeshInstance3D.new()
	add_child_autofree(mesh)
	var glow := StandardMaterial3D.new()
	mesh.material_overlay = glow
	VisualStyle.set_style(VisualStyle.Style.CLARITY)
	var outline: ShaderMaterial = SemanticOutline.attach(mesh, Tokens.WORLD_GRAPPLE)
	assert_eq(mesh.material_overlay, glow, "el brillo sigue arriba")
	assert_eq(glow.next_pass, outline, "y el borde va detras")
	# Rearmar con otro color no duplica: el mismo borde, otro color.
	assert_eq(SemanticOutline.attach(mesh, Tokens.WORLD_PICKUP), outline)


## Lo que se juega lleva borde en el color de su significado; el peligro no, es
## un charco sin silueta.
func test_telegraphs_outline_what_you_use_but_not_hazards() -> void:
	var anchor_mesh := MeshInstance3D.new()
	anchor_mesh.mesh = BoxMesh.new()
	var anchor := TelegraphComponent.new()
	anchor.meaning = TelegraphComponent.Meaning.GRAPPLE
	anchor.meshes = [anchor_mesh]
	add_child_autofree(anchor_mesh)
	add_child_autofree(anchor)
	assert_true(anchor_mesh.has_meta(SemanticOutline.META))
	VisualStyle.set_style(VisualStyle.Style.CLARITY)
	assert_true(SemanticOutline.is_chained(anchor_mesh), "colgado en Claridad")
	VisualStyle.set_style(VisualStyle.Style.STANDARD)
	assert_false(SemanticOutline.is_chained(anchor_mesh),
		"y descolgado fuera: con ancho 0 seguiria costando un draw call")

	var hazard_mesh := MeshInstance3D.new()
	hazard_mesh.mesh = BoxMesh.new()
	var hazard := TelegraphComponent.new()
	hazard.meaning = TelegraphComponent.Meaning.HAZARD
	hazard.meshes = [hazard_mesh]
	add_child_autofree(hazard_mesh)
	add_child_autofree(hazard)
	assert_false(hazard_mesh.has_meta(SemanticOutline.META))


func test_the_default_ink_width_is_the_token() -> void:
	assert_eq(float(SettingsManager.DEFAULTS["video/toon_line_px"]), Tokens.TOON_LINE_PX)
