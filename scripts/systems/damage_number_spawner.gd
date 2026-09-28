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
##
## El pool es propio y no `ObjectPool`. El generico paga, por cada numero que
## entra y sale, un cambio de grupo, dos de `process_mode` (que notifican a
## todo el subarbol), un teletransporte y dos diccionarios - y cada numero
## corria su propio `_process`. Aca hay un anillo fijo de `max_live_numbers`
## numeros, creados una sola vez como hijos de este nodo y que no salen nunca
## del arbol: uno libre esta oculto y nada mas, y los vivos los avanza el unico
## `_process` de abajo. El tope deja de ser un conteo: es el tamaño del anillo.

@export var damage_number_scene: PackedScene
## Enemy origins sit at the feet (EnemyData.head_offset etc. are all measured
## up from there) - numbers spawning at ground level would read as coming from
## the floor, not the hit.
@export var height_offset: float = 1.1
## Cuantos numeros pueden estar vivos a la vez, y por lo tanto cuantos se crean.
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

## target -> { "number": DamageNumber, "play_id": int, "at": float } del ultimo
## numero abierto sobre ese objetivo.
var _open: Dictionary = {}
## Los numeros en pantalla, del mas viejo al mas nuevo.
var _live: Array[DamageNumber] = []
## Los libres, como pila.
var _free: Array[DamageNumber] = []


func _ready() -> void:
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.healed.connect(_on_healed)
	EventBus.kill_payout.connect(_on_kill_payout)
	_build_pool()


## Todos los numeros vivos en una sola pasada. Al reves para poder sacar
## mientras se recorre.
func _process(delta: float) -> void:
	for i: int in range(_live.size() - 1, -1, -1):
		var number: DamageNumber = _live[i]
		if not number.tick(delta):
			_release_at(i)


# Public API

func get_live_count() -> int:
	return _live.size()


func get_pool_size() -> int:
	return _live.size() + _free.size()


# Signal handlers

func _on_damage_dealt(target: Node, amount: float, is_headshot: bool) -> void:
	if amount <= 0.0 or not _numbers_enabled():
		return
	var target_3d: Node3D = target as Node3D
	if target_3d == null:
		return

	var existing: DamageNumber = _open_number_for(target_3d)
	if existing != null:
		existing.add_damage(amount, is_headshot)
		return

	var number: DamageNumber = _acquire()
	if number == null:
		return
	number.play_at(target_3d.global_position + Vector3.UP * height_offset,
		amount, is_headshot)
	_open[target_3d] = {"number": number, "play_id": number.play_id, "at": _now()}


## La curacion sale del mismo anillo y con el mismo tope que el daño: es un
## numero flotante mas, y el presupuesto que existe es para todos.
##
## No se agrega con `add_damage` sobre un numero abierto - un +12 verde sumado
## a un 240 rojo no es ningun numero - asi que una curacion sobre un objetivo
## que ya tiene un numero arriba pide el suyo.
func _on_healed(target: Node, amount: float) -> void:
	if amount <= 0.0 or not _numbers_enabled():
		return
	var target_3d: Node3D = target as Node3D
	if target_3d == null:
		return
	var number: DamageNumber = _acquire()
	if number == null:
		return
	number.play_heal_at(target_3d.global_position + Vector3.UP * height_offset, amount)


## La plata que dejo la kill, sobre el cuerpo, recompensa y bono en un solo
## numero.
##
## Entra en el mismo tope que el daño, pero se cuela por encima de el cuando
## hace falta: una kill es exactamente el momento en que el anillo esta lleno de
## numeros de daño sobre el enemigo que acaba de morir, y perder justo ahi el
## unico numero que dice cuanto cobraste seria quedarse sin la informacion en el
## unico instante en que importa. Se libera el mas viejo para hacerle lugar.
func _on_kill_payout(reward: int, _bonus_ids: Array, bonus_total: int,
		position: Vector3) -> void:
	var total: int = reward + bonus_total
	if total <= 0 or not _numbers_enabled():
		return
	if _free.is_empty() and not _live.is_empty():
		_release_at(0)
	var number: DamageNumber = _acquire()
	if number == null:
		return
	number.play_reward_at(position + Vector3.UP * height_offset, total)


# Private

func _build_pool() -> void:
	if damage_number_scene == null:
		return
	for _i: int in maxi(max_live_numbers, 0):
		var number := damage_number_scene.instantiate() as DamageNumber
		if number == null:
			push_error("DamageNumberSpawner: damage_number_scene is not a DamageNumber")
			return
		add_child(number)
		number.stop()
		_free.push_back(number)


## Un numero libre, ya contado como vivo, o null si el anillo esta lleno.
func _acquire() -> DamageNumber:
	if _free.is_empty():
		return null
	var number: DamageNumber = _free.pop_back()
	_live.push_back(number)
	return number


func _release_at(index: int) -> void:
	var number: DamageNumber = _live[index]
	_live.remove_at(index)
	number.stop()
	_free.push_back(number)


## El numero todavia abierto sobre este objetivo, o null. Limpia de paso la
## entrada vencida: el diccionario no puede crecer con enemigos muertos.
##
## El `play_id` es lo que impide sumarle daño a un numero ajeno: si el numero se
## apago y el anillo lo reciclo para otro enemigo, sigue "jugando", pero ya no es
## el mismo numero que se guardo aca.
func _open_number_for(target: Node3D) -> DamageNumber:
	var entry: Dictionary = _open.get(target, {})
	if entry.is_empty():
		return null
	var number := entry["number"] as DamageNumber
	if not number.is_playing() or number.play_id != int(entry["play_id"]) \
			or _now() - float(entry["at"]) > merge_window:
		_open.erase(target)
		return null
	return number


func _numbers_enabled() -> bool:
	return damage_number_scene != null \
		and bool(SettingsManager.get_value("hud/damage_numbers", true))


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
