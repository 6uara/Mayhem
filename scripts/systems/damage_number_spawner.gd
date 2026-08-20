class_name DamageNumberSpawner
extends Node
## Pools a floating DamageNumber over whatever EventBus.damage_dealt names as
## the target - the same signal HitstopController already consumes, so this
## never becomes a second source of truth for how much damage landed.
##
## `target` on that signal carries no exact hit position, only the Node that
## was hit, so numbers spawn near the target's own origin plus `height_offset`
## rather than the precise impact point. Good enough to read as attached to
## what got hit; a new EventBus parameter for exact position was not worth it
## for a cosmetic-only number.
##
## Este nodo es ademas donde vive el presupuesto: un numero por golpe, sin techo,
## es lo que hacia que una escopeta sobre un grupo costara mas de la mitad del
## framerate (medido con tools/profile_damage_numbers.gd). Las dos reglas de
## abajo - agregar y topear - salen de ahi.

@export var damage_number_scene: PackedScene
## Enemy origins sit at the feet (EnemyData.head_offset etc. are all measured
## up from there) - numbers spawning at ground level would read as coming from
## the floor, not the hit.
@export var height_offset: float = 1.1
## Cuantos numeros pueden estar vivos a la vez.
##
## Pasado este tope no se pide uno nuevo: el golpe sigue existiendo, sigue
## haciendo daño y sigue sonando, simplemente no pinta un Label3D mas. Doce
## numeros en pantalla ya son mas de los que alguien puede leer, asi que el
## numero trece no informa nada y si cuesta un draw call.
@export var max_live_numbers: int = 12
## Ventana en la que dos golpes al mismo objetivo se suman en un numero en vez
## de pedir dos.
##
## Es el caso que rompia la medicion: una escopeta son ocho impactos en el mismo
## frame sobre el mismo enemigo. Sumarlos ademas se lee mejor - un 240 dice mas
## que ocho 30 superpuestos.
@export var merge_window: float = 0.25

## target -> { "number": DamageNumber, "at": float } del ultimo numero abierto
## sobre ese objetivo. Se vacia cuando la ventana de agregacion vence, asi que
## NO sirve para contar cuantos numeros hay vivos - un numero sigue en pantalla
## medio segundo despues de dejar de aceptar sumas.
var _open: Dictionary = {}
## Los numeros efectivamente en pantalla. Lista aparte de _open justamente por lo
## de arriba: contar sobre _open hacia que el tope no topeara nada, que es como
## la primera version de esto no mejoro una sola medicion.
var _live: Array[DamageNumber] = []


func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	# El primer tiroteo no tiene por que pagar la instanciacion de todo el tope.
	if damage_number_scene != null:
		ObjectPool.prewarm(damage_number_scene, max_live_numbers)


func _on_damage_dealt(target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0 or damage_number_scene == null:
		return
	if not bool(SettingsManager.get_value("hud/damage_numbers", true)):
		return
	var target_3d: Node3D = target as Node3D
	if target_3d == null:
		return

	var existing: DamageNumber = _open_number_for(target_3d)
	if existing != null:
		existing.add_damage(amount, is_headshot)
		return

	if _live_count() >= max_live_numbers:
		return

	var number: Node = ObjectPool.acquire(damage_number_scene)
	if number == null or not number.has_method(&"play_at"):
		return
	number.call(&"play_at", target_3d.global_position + Vector3.UP * height_offset,
		amount, is_headshot)
	_open[target_3d] = {"number": number, "at": _now()}
	_live.append(number)


# Private

## El numero todavia abierto sobre este objetivo, o null. Limpia de paso la
## entrada cuando el numero ya se apago o el objetivo se fue: el diccionario no
## puede crecer con enemigos muertos.
func _open_number_for(target: Node3D) -> DamageNumber:
	var entry: Dictionary = _open.get(target, {})
	if entry.is_empty():
		return null
	var number := entry["number"] as DamageNumber
	if not is_instance_valid(number) or not number.is_playing() \
			or _now() - float(entry["at"]) > merge_window:
		_open.erase(target)
		return null
	return number


## Cuantos numeros hay realmente en pantalla, purgando de paso los que ya se
## apagaron. Se recorre al reves para poder borrar mientras se itera.
func _live_count() -> int:
	for i: int in range(_live.size() - 1, -1, -1):
		var number: DamageNumber = _live[i]
		if not is_instance_valid(number) or not number.is_playing():
			_live.remove_at(i)
	return _live.size()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
