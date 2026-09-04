class_name GrappleAnchor
extends StaticBody3D
## A grapple point that says so before you aim at it.
##
## Idle sits at 60% emission; coming into range pushes it to full with a 2s pulse -
## and the crosshair changes shape at the same moment, so the confirmation exists
## both in the world and on the HUD. Two places, one instant.

## El grupo por el que la asistencia de apuntado del grapple encuentra anclas
## que el rayo no toco. Una sola definicion: el .tscn declara el grupo, esto lo
## nombra, y GrappleComponent lo lee de aca.
const GROUP: StringName = &"grapple_anchor"

@export var telegraph: TelegraphComponent

var _player: Player
var _was_available: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.IDLE


func _physics_process(_delta: float) -> void:
	if telegraph == null:
		return
	var available: bool = _is_in_player_range()
	if available == _was_available:
		return
	_was_available = available
	telegraph.state = TelegraphComponent.State.AVAILABLE if available \
		else TelegraphComponent.State.IDLE


## In range means the grapple could actually take it, so the world never promises
## something the component would refuse.
func _is_in_player_range() -> bool:
	var player: Player = _get_player()
	if player == null or player.grapple == null:
		return false
	return global_position.distance_to(player.global_position) <= player.grapple.get_max_range()


## The anchor highlight is a local visual - it answers "can *I* grapple this
## right now", so it tracks our own body rather than whichever teammate is
## nearest. Two players looking at the same anchor each see their own range.
func _get_player() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = Players.local() as Player
	return _player
