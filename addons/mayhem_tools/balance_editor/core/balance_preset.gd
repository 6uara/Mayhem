@tool
class_name BalancePreset
extends Resource
## A full set of tuning values, captured so two configurations can be compared
## without keeping notes in a text file.

@export var preset_name: String = ""
@export var created_at: String = ""
## Serialized economy values, field name -> value.
@export var economy: Dictionary = {}
## Archetype id -> {field name -> value}.
@export var enemies: Dictionary = {}

const PRESET_DIR: String = "res://data/balance_presets"
## The archetype fields a preset carries. Everything else about an enemy is
## content, not balance, and copying it between presets would be noise.
const ENEMY_FIELDS: Array[StringName] = [
	&"max_health", &"move_speed", &"damage", &"attack_range", &"attack_cooldown",
	&"mass", &"stagger_resistance",
]


static func capture(model: BalanceModel, preset_name: String) -> BalancePreset:
	var preset := BalancePreset.new()
	preset.preset_name = preset_name
	preset.created_at = Time.get_datetime_string_from_system(true)
	if model.economy != null:
		for property: Dictionary in model.economy.get_property_list():
			if not _is_exported(property):
				continue
			preset.economy[property["name"]] = model.economy.get(property["name"])
	for enemy: EnemyData in model.enemies:
		var values: Dictionary = {}
		for field: StringName in ENEMY_FIELDS:
			values[String(field)] = enemy.get(field)
		preset.enemies[String(enemy.id)] = values
	return preset


## Writes the preset's values back onto the live resources. Fields the preset
## does not know about are left alone, so an older preset never blanks a value
## added since it was captured.
func apply(model: BalanceModel) -> void:
	if model.economy != null:
		for key: String in economy.keys():
			model.economy.set(StringName(key), economy[key])
	for enemy_id: String in enemies.keys():
		var enemy: EnemyData = model.find_enemy(StringName(enemy_id))
		if enemy == null:
			continue
		var values: Dictionary = enemies[enemy_id]
		for key: String in values.keys():
			enemy.set(StringName(key), values[key])


static func list_presets() -> PackedStringArray:
	var out := PackedStringArray()
	for file_name: String in DirAccess.get_files_at(PRESET_DIR):
		var clean: String = file_name.trim_suffix(".remap")
		if clean.get_extension().to_lower() == "tres":
			out.append(PRESET_DIR.path_join(clean))
	return out


# Private

static func _is_exported(property: Dictionary) -> bool:
	return int(property["usage"]) & PROPERTY_USAGE_STORAGE != 0 \
		and int(property["usage"]) & PROPERTY_USAGE_EDITOR != 0 \
		and String(property["name"]) != "script"
