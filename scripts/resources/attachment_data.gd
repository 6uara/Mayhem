@tool
class_name AttachmentData
extends Resource
## Un attachment de arma: una pieza que se desbloquea jugando con esa arma y que
## se lleva puesta a las runs siguientes. Ver Armory.
##
## Es lo unico del juego que se arrastra entre runs, y por eso esta hecho para
## cambiar como se juega el arma y no para hacerla mas fuerte: cada uno da algo y
## cobra algo (el compensador baja el recoil y el daño, el cargador tambor suma
## balas y tarda mas en recargar). Sigue siendo solo StatModifiers, como una
## mejora de tienda: se aplica al arrancar la run como una mejora de arma.

enum Slot { MUZZLE, MAGAZINE, OPTIC }

const SLOT_LABEL: Dictionary = {
	Slot.MUZZLE: "MUZZLE",
	Slot.MAGAZINE: "MAGAZINE",
	Slot.OPTIC: "OPTIC",
}

@export var id: StringName = &""
@export var display_name: String = ""
## Lo que da y lo que cobra, en una linea.
@export var description: String = ""
## El arma a la que va (`WeaponData.id`).
@export var weapon_id: StringName = &""
## Un attachment por ranura y por arma puesto a la vez.
@export var slot: Slot = Slot.MUZZLE
## El nivel de maestria del arma que lo desbloquea (1-based).
@export var unlock_level: int = 1
@export var stat_modifiers: Array[StatModifier] = []


static func slot_label(value: int) -> String:
	return String(SLOT_LABEL.get(value, "SLOT"))
