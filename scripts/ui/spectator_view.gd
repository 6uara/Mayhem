class_name SpectatorView
extends Node3D
## What a downed player sees: a chase camera on a surviving teammate, and a
## banner explaining why they are no longer holding a gun.
##
## Deliberately a third-person camera rather than borrowing the target's own.
## Their camera sits inside their head, and their viewmodel arms are hidden on
## every machine but their own - riding it would mean staring out of a model
## with no weapon in frame. A shoulder camera also makes it obvious you are
## watching someone rather than playing them, which is the thing a dead player
## most needs to understand in the first second.
##
## Nothing here is networked. Who is dead is already agreed on by everyone
## through Player.is_downed; which teammate you choose to watch is nobody's
## business but yours.

## Metres behind and above the target. Far enough to keep their body and the
## enemies fighting them in frame at once.
const FOLLOW_DISTANCE: float = 4.2
const FOLLOW_HEIGHT: float = 2.4
## Where the camera aims, measured up from the target's feet - roughly their
## head, so the framing matches what they are shooting at.
const LOOK_HEIGHT: float = 1.5
## Chase smoothing. The target's position is already interpolated from the
## network, so this only has to absorb their dodging, not packet jitter.
const FOLLOW_SPEED: float = 8.0

@onready var _camera: Camera3D = $Camera3D
@onready var _overlay: CanvasLayer = $Overlay
@onready var _title: Label = $Overlay/Root/Panel/Margin/Layout/Title
@onready var _target_label: Label = $Overlay/Root/Panel/Margin/Layout/TargetLabel
@onready var _hint: Label = $Overlay/Root/Panel/Margin/Layout/Hint

var _is_spectating: bool = false
var _target: Node3D = null


func _ready() -> void:
	_overlay.visible = false
	_camera.current = false
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.player_revived.connect(_on_player_revived)
	# The run ending takes the screen back - the game over panel is the last
	# word, and a chase camera behind it would just be scenery.
	EventBus.player_died.connect(_stop)


func _process(delta: float) -> void:
	if not _is_spectating:
		return
	if not Players.is_alive(_target):
		# Whoever we were watching just went down too. Move on rather than
		# leaving the camera parked on a corpse.
		_pick_target(1)
		if _target == null:
			return
	_follow(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_spectating:
		return
	# Reuses the firing controls rather than claiming new bindings: a dead
	# player has nothing to shoot, and these are the two buttons their hands
	# are already on.
	if event.is_action_pressed("fire"):
		_pick_target(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ads"):
		_pick_target(-1)
		get_viewport().set_input_as_handled()


# Private

func _on_player_downed(peer_id: int) -> void:
	# Only our own death puts us in the stands. A teammate going down is their
	# problem to watch.
	if peer_id != NetworkManager.local_id():
		return
	if not NetworkManager.is_online():
		# Solo: there is no one to spectate, and the game over panel is already
		# on its way.
		return
	_start()


## The wave break stood us back up: the stands are for people who are dead, and
## we are not any more.
func _on_player_revived(peer_id: int) -> void:
	if peer_id != NetworkManager.local_id():
		return
	_stop()


func _start() -> void:
	if _is_spectating:
		return
	_is_spectating = true
	_overlay.visible = true
	_title.text = "MORISTE"
	_camera.current = true
	_pick_target(1)


func _stop() -> void:
	if not _is_spectating:
		return
	_is_spectating = false
	_overlay.visible = false
	_camera.current = false
	_target = null
	EventBus.spectating_changed.emit(false, "")


## Steps to the next living teammate, wrapping around. Direction is +1 or -1.
func _pick_target(direction: int) -> void:
	var living: Array[Node3D] = Players.alive()
	if living.is_empty():
		_target = null
		_target_label.text = "No queda nadie en pie"
		_hint.text = ""
		EventBus.spectating_changed.emit(true, "")
		return

	var index: int = living.find(_target)
	# find() returns -1 when the previous target just died or we are starting
	# fresh; stepping from there lands on the first entry either way.
	index = wrapi(index + direction, 0, living.size())
	_target = living[index]

	var who: String = _name_of(_target)
	_target_label.text = "Estas viendo a %s" % who
	_hint.text = "Click izq / der para cambiar de jugador" if living.size() > 1 \
		else "Es el ultimo que queda"
	EventBus.spectating_changed.emit(true, who)
	# Jump straight there rather than sweeping across the arena from the last
	# target, which reads as the camera being lost rather than as a cut.
	_follow(1.0)


func _follow(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var behind: Vector3 = _target.global_transform.basis.z * FOLLOW_DISTANCE
	var desired: Vector3 = _target.global_position + behind + Vector3.UP * FOLLOW_HEIGHT
	var weight: float = clampf(FOLLOW_SPEED * delta, 0.0, 1.0)
	_camera.global_position = _camera.global_position.lerp(desired, weight)
	_camera.look_at(_target.global_position + Vector3.UP * LOOK_HEIGHT)


func _name_of(body: Node3D) -> String:
	var player := body as Player
	if player == null:
		return "un companero"
	return NetworkManager.get_player_name(player.get_peer_id())
