@tool
class_name UpgradeData
extends Resource
## A purchasable upgrade. Every effect must be expressible as StatModifiers.

enum Category { MOBILITY, WEAPON, SURVIVABILITY }

## Las familias de mejoras. Una mejora lleva una o dos, y las raras de sinergia
## (Aerialist, Deadeye, Streamliner, Bulwark) escalan con cuantas de una familia
## tiene el build - ver `StatModifier.per_tag`. Es lo que convierte una pila de
## numeros sueltos en un build: comprar la tercera mejora de aire vale mas si ya
## esta el Aerialist, y la de armadura le cobra al Streamliner.
const TAG_AIR: StringName = &"air"
const TAG_MOMENTUM: StringName = &"momentum"
const TAG_GRAPPLE: StringName = &"grapple"
const TAG_PRECISION: StringName = &"precision"
const TAG_ARMOR: StringName = &"armor"
const TAG_AMMO: StringName = &"ammo"
const TAG_FIREPOWER: StringName = &"firepower"
const TAG_STYLE: StringName = &"style"
## Lo que dice la tarjeta. Una etiqueta que no esta aca no existe (hay un test).
const TAG_LABELS: Dictionary = {
	TAG_AIR: "AIR",
	TAG_MOMENTUM: "MOMENTUM",
	TAG_GRAPPLE: "GRAPPLE",
	TAG_PRECISION: "PRECISION",
	TAG_ARMOR: "ARMOR",
	TAG_AMMO: "AMMO",
	TAG_FIREPOWER: "FIREPOWER",
	TAG_STYLE: "STYLE",
}

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var cost: int = 100
@export var category: Category = Category.WEAPON
@export var stat_modifiers: Array[StatModifier] = []
@export var max_stacks: int = 1
@export var is_temporary: bool = false
## Only meaningful when `is_temporary` is true.
@export var duration: float = 0.0
## Rara: agrega una regla en vez de mover un numero (deslizar recarga, el slide
## atropella...). Sigue siendo solo StatModifiers - sobre stats cuya base neutra
## deja la regla apagada (ver StatsComponent). La tienda ofrece como mucho una por
## visita y no todas las visitas: ver ShopCatalog.rare_upgrades.
@export var is_rare: bool = false
## Las armas para las que existe, por id. Vacio: todas. Una rara de arma (la bala
## que atraviesa de la pistola, el slug de la escopeta) solo se ofrece con una de
## estas equipada, porque la regla no significa nada en otra.
@export var weapon_ids: Array[StringName] = []
## Las familias a las que pertenece (TAG_*). Las cuentan las raras de sinergia.
@export var tags: Array[StringName] = []


func fits_weapon(weapon_id: StringName) -> bool:
	return weapon_ids.is_empty() or weapon_ids.has(weapon_id)


## "AIR · MOMENTUM": las etiquetas como las muestra una tarjeta.
func get_tag_text() -> String:
	var labels: PackedStringArray = PackedStringArray()
	for tag: StringName in tags:
		labels.append(String(TAG_LABELS.get(tag, String(tag).to_upper())))
	return " · ".join(labels)


## Las etiquetas con las que escala alguno de sus modificadores: lo que hace de
## esta mejora una rara de sinergia.
func get_scaling_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for modifier: StatModifier in stat_modifiers:
		if modifier != null and modifier.per_tag != &"" and not out.has(modifier.per_tag):
			out.append(modifier.per_tag)
	return out
