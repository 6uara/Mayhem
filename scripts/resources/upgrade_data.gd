@tool
class_name UpgradeData
extends Resource
## A purchasable upgrade. Every effect must be expressible as StatModifiers.

enum Category { MOBILITY, WEAPON, SURVIVABILITY }

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
## Rara: agrega una regla en vez de mover un numero (deslizar recarga, el dash
## atropella...). Sigue siendo solo StatModifiers - sobre stats cuya base neutra
## deja la regla apagada (ver StatsComponent). La tienda ofrece como mucho una por
## visita y no todas las visitas: ver ShopCatalog.rare_upgrades.
@export var is_rare: bool = false
