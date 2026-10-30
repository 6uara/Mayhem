extends GutTest
## El estilo toon: que convierta lo que tiene que convertir, deje lo que no, y
## que apagarlo deje todo como estaba.

var _was_enabled: bool


func before_each() -> void:
	_was_enabled = ToonStyle.enabled


func after_each() -> void:
	ToonStyle.set_enabled(_was_enabled)


func _lit_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.metallic = 0.8
	material.normal_enabled = true
	return material


func test_a_lit_material_turns_toon_and_comes_back() -> void:
	var material: StandardMaterial3D = _lit_material()
	assert_true(ToonStyle.convert_material(material))
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON)
	assert_eq(material.specular_mode, BaseMaterial3D.SPECULAR_DISABLED)
	assert_eq(material.metallic, 0.0)
	assert_false(material.normal_enabled)

	ToonStyle.restore_material(material)
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY)
	assert_eq(material.specular_mode, BaseMaterial3D.SPECULAR_SCHLICK_GGX)
	assert_almost_eq(material.metallic, 0.8, 0.001)
	assert_true(material.normal_enabled)


## Las texturas aplanadas que escribe tools/blender/flatten_textures.py.
func test_a_model_texture_swaps_to_its_flat_version_and_back() -> void:
	var original: Texture2D = load("res://assets/models/props/ramp_Image_0.jpg") as Texture2D
	var material: StandardMaterial3D = _lit_material()
	material.albedo_texture = original
	ToonStyle.convert_material(material)
	assert_ne(material.albedo_texture, original)
	assert_eq(material.albedo_texture.resource_path,
		"res://assets/models/props/ramp_Image_0_toon.png")
	ToonStyle.restore_material(material)
	assert_eq(material.albedo_texture, original)


func test_a_texture_without_a_flat_version_is_kept() -> void:
	var material: StandardMaterial3D = _lit_material()
	material.albedo_texture = ImageTexture.create_from_image(
		Image.create(4, 4, false, Image.FORMAT_RGB8))
	var texture: Texture2D = material.albedo_texture
	ToonStyle.convert_material(material)
	assert_eq(material.albedo_texture, texture)


## Un VFX o un contorno ya tienen su propio look: la luz en bandas no les cambia
## nada y tocarlos solo ensuciaria la lista de lo convertido.
func test_unshaded_and_shader_materials_are_left_alone() -> void:
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	assert_false(ToonStyle.convert_material(unshaded))
	assert_eq(unshaded.diffuse_mode, BaseMaterial3D.DIFFUSE_BURLEY)
	assert_false(ToonStyle.convert_material(ShaderMaterial.new()))


func test_a_mesh_entering_the_tree_is_converted() -> void:
	ToonStyle.set_enabled(true)
	var material: StandardMaterial3D = _lit_material()
	var mesh := BoxMesh.new()
	var instance := MeshInstance3D.new()
	add_child_autofree(instance)
	# Asignada despues del add_child, como la arma mucho codigo del juego.
	mesh.material = material
	instance.mesh = mesh
	await wait_process_frames(2)
	assert_eq(material.diffuse_mode, BaseMaterial3D.DIFFUSE_TOON)


func test_every_camera_gets_an_ink_line_and_loses_it_when_turned_off() -> void:
	ToonStyle.set_enabled(true)
	var camera := Camera3D.new()
	add_child_autofree(camera)
	await wait_process_frames(2)
	assert_not_null(ToonStyle.get_outline(camera))

	ToonStyle.set_enabled(false)
	await wait_process_frames(1)
	assert_null(ToonStyle.get_outline(camera))
