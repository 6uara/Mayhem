extends GutTest
## SurfaceMaterials: resolves a raycast collider to its SurfaceMaterialData,
## defaulting gracefully rather than erroring on anything untagged.


func test_the_catalog_loads_every_tres_in_data_surfaces() -> void:
	for id: StringName in [&"concrete", &"metal", &"flesh"]:
		var material: SurfaceMaterialData = SurfaceMaterials.get_material(id)
		assert_not_null(material, "%s must be in the catalog" % id)
		assert_eq(material.id, id)


func test_an_untagged_collider_resolves_to_the_default() -> void:
	var plain := Node3D.new()
	add_child_autofree(plain)
	var material: SurfaceMaterialData = SurfaceMaterials.resolve(plain)
	assert_eq(material.id, SurfaceMaterials.DEFAULT_ID)


func test_a_tagged_collider_resolves_to_its_own_material() -> void:
	var body := StaticBody3D.new()
	body.set_meta(SurfaceMaterials.META_KEY, &"metal")
	add_child_autofree(body)
	var material: SurfaceMaterialData = SurfaceMaterials.resolve(body)
	assert_eq(material.id, &"metal")


func test_an_unknown_tag_falls_back_to_the_default_rather_than_erroring() -> void:
	var body := StaticBody3D.new()
	body.set_meta(SurfaceMaterials.META_KEY, &"lava_of_the_gods")
	add_child_autofree(body)
	var material: SurfaceMaterialData = SurfaceMaterials.resolve(body)
	assert_eq(material.id, SurfaceMaterials.DEFAULT_ID)


func test_flesh_never_spawns_a_decal() -> void:
	var flesh: SurfaceMaterialData = SurfaceMaterials.get_material(&"flesh")
	assert_false(flesh.spawns_decal)


func test_every_hitbox_resolves_to_flesh() -> void:
	var hitbox := HitboxComponent.new()
	add_child_autofree(hitbox)
	var material: SurfaceMaterialData = SurfaceMaterials.resolve(hitbox)
	assert_eq(material.id, &"flesh")
