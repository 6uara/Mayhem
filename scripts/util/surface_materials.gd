class_name SurfaceMaterials
extends RefCounted
## Resolves which SurfaceMaterialData a raycast hit belongs to, and caches the
## catalog. Static utility, like PhysicsLayers - no instance ever needed.
##
## Surfaces are tagged with a meta key on the collider (`set_meta(&"surface",
## &"metal")` in the editor or on `_ready()`), not a group: a group would
## conflict with the gameplay groups a collider might already need (&"player"
## etc.), and a meta value reads better in the inspector than a group name
## that only means something here.

const META_KEY: StringName = &"surface"
const DEFAULT_ID: StringName = &"concrete"
const CATALOG_DIR: String = "res://data/surfaces/"

static var _catalog: Dictionary = {}  # StringName -> SurfaceMaterialData
static var _loaded: bool = false


## The material for whatever `collider` is - falls back to DEFAULT_ID (never
## errors) when the collider has no `surface` meta at all, which is the normal
## case for most world geometry until someone tags it.
static func resolve(collider: Object) -> SurfaceMaterialData:
	var id: StringName = DEFAULT_ID
	if collider is Object and collider.has_meta(META_KEY):
		id = StringName(collider.get_meta(META_KEY))
	return get_material(id)


static func get_material(id: StringName) -> SurfaceMaterialData:
	_ensure_loaded()
	var material: SurfaceMaterialData = _catalog.get(id)
	if material != null:
		return material
	return _catalog.get(DEFAULT_ID)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir: DirAccess = DirAccess.open(CATALOG_DIR)
	if dir == null:
		push_warning("SurfaceMaterials: cannot open %s" % CATALOG_DIR)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var material: SurfaceMaterialData = load(CATALOG_DIR + file_name)
			if material != null and material.id != &"":
				_catalog[material.id] = material
		file_name = dir.get_next()
	dir.list_dir_end()
