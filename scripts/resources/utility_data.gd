@tool
class_name UtilityData
extends Resource
## A throwable/deployable utility (stun grenade, temporary wall, slow field).

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene
## Sin uso desde que los gadgets salieron del shop y pasaron a caer de las
## gradas. Se deja porque los tres .tres lo tienen serializado y porque un
## gadget vuelve a tener precio el dia que algo vuelva a venderlos; hoy no lo
## lee nadie. Ver CrowdDropTable.
@export var cost: int = 75
@export var max_carried: int = 2
@export var cooldown: float = 6.0
@export var throw_force: float = 14.0
@export var effect_radius: float = 5.0
@export var effect_duration: float = 3.0

## El color con el que se lee este gadget cuando esta tirado en la arena.
##
## Existe porque los gadgets dejaron de comprarse y pasaron a caer de las
## gradas: el jugador ve una cosa lejos y tiene que decidir si vale la pena
## cruzar la arena por ella antes de llegar. Si las tres se ven iguales, esa
## decision no se puede tomar y el pickup se vuelve una sorpresa.
##
## El ambar de `Tokens.WORLD_PICKUP` sigue siendo el marco -toda la casa es
## ambar-, asi que esto tiñe el nucleo y no el halo.
@export var accent_color: Color = Color(1.0, 0.69, 0.13)
## Vida que cura al levantarlo. Mayor que cero convierte al gadget en un botiquin:
## no va a ningun slot ni se tira, se usa al agarrarlo. Es la unica curacion que
## cae de la tribuna - la otra es la mejora de regeneracion de la tienda.
@export var heal_amount: float = 0.0


func is_heal() -> bool:
	return heal_amount > 0.0
