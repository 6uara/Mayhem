@tool
class_name BalanceModel
extends RefCounted
## Everything the balance editor can touch, loaded from the same `.tres` files
## the game loads.
##
## MAYHEM already keeps its tuning in resources (`data/economy/economy_config.tres`
## and one file per archetype under `data/enemies/`), so this loads and saves
## those files rather than owning a parallel copy of the numbers.

signal changed()

const ECONOMY_PATH: String = "res://data/economy/economy_config.tres"
const SHOP_PATH: String = "res://data/economy/shop_catalog.tres"
const ENEMY_DIR: String = "res://data/enemies"
const WAVE_DIR: String = "res://data/waves"

var economy: EconomyConfig
var shop: ShopCatalog
## Archetype id -> EnemyData, in load order.
var enemies: Array[EnemyData] = []
var waves: Array = []


func load_all() -> void:
	economy = load(ECONOMY_PATH) as EconomyConfig
	shop = load(SHOP_PATH) as ShopCatalog
	enemies.clear()
	for resource: Variant in _load_dir(ENEMY_DIR):
		enemies.append(resource as EnemyData)
	waves = _load_dir(WAVE_DIR)
	waves.sort_custom(func(a: WaveData, b: WaveData) -> bool:
		return a.wave_index < b.wave_index)
	changed.emit()


## Writes the tuning back to disk and tells anything running to re-read it.
func save_all() -> Error:
	var result: Error = OK
	if economy != null:
		result = ResourceSaver.save(economy, ECONOMY_PATH)
	for enemy: EnemyData in enemies:
		var path: String = enemy.resource_path
		if path != "":
			var enemy_result: Error = ResourceSaver.save(enemy, path)
			if enemy_result != OK:
				result = enemy_result
	apply_live()
	return result


## Hot apply. The editor and the running game are separate processes, so the
## handoff is the file itself: `BalanceHub` in the game watches these paths and
## reloads them in place, which is why saving is all this has to do.
func apply_live() -> void:
	changed.emit()


func find_enemy(id: StringName) -> EnemyData:
	for enemy: EnemyData in enemies:
		if enemy.id == id:
			return enemy
	return null


# Private

func _load_dir(dir_path: String) -> Array:
	var out: Array = []
	for file_name: String in DirAccess.get_files_at(dir_path):
		var clean: String = file_name.trim_suffix(".remap")
		if clean.get_extension().to_lower() != "tres":
			continue
		var resource: Resource = load(dir_path.path_join(clean))
		if resource != null:
			out.append(resource)
	return out
