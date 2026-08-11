extends Node
## Shows a one-line HUD overlay the first time the player performs each core
## mechanic - move, jump, mantle, slide, dash, grapple, ADS, reload, first shop
## visit. Content lives in TutorialHint resources (data/tutorial/), never as
## string literals here.
##
## Deliberately NOT NarratorManager: the Host talks to the crowd, not the
## player (see Game Treatment) - a tutorial prompt is a neutral HUD overlay,
## never a Host line. "Seen" persists forever via SaveManager, independent of
## the leaderboard and of any run - there is no meta-progression here, just a
## courtesy that stops repeating once learned.
##
## MovementComponent lives on the player, which is recreated every run
## (GameManager swaps the whole scene) - this autoload is not, so it rebinds
## to the current player's MovementComponent whenever a run starts rather than
## connecting once at startup.

signal hint_shown(text: String, duration: float)
signal hint_hidden()

const CATALOG_PATH: String = "res://data/tutorial/tutorial_hints.tres"
## Hints waiting to be shown are dropped past this, rather than growing
## unbounded - if the player has ignored four mechanics' worth of hints
## already, a fifth queued behind them would show stale advice anyway.
const MAX_QUEUED: int = 4

var _hints_by_id: Dictionary = {}  # StringName -> TutorialHint
var _queue: Array[TutorialHint] = []
var _current: TutorialHint
var _time_left: float = 0.0
var _movement: MovementComponent


func _ready() -> void:
	_load_catalog()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.dash_used.connect(_on_dash_used)
	EventBus.grapple_started.connect(_on_grapple_started)
	EventBus.weapon_reloaded.connect(_on_weapon_reloaded)
	EventBus.weapon_ads_changed.connect(_on_weapon_ads_changed)
	EventBus.shop_opened.connect(_on_shop_opened)
	_bind_player.call_deferred()


func _process(delta: float) -> void:
	if _current == null:
		_try_show_next()
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_finish_current()


# Signal handlers - EventBus

func _on_dash_used(_charges_remaining: int) -> void:
	_fire(&"dash")


func _on_grapple_started(_anchor: Vector3) -> void:
	_fire(&"grapple")


func _on_weapon_reloaded(_weapon_id: StringName) -> void:
	_fire(&"reload")


func _on_weapon_ads_changed(is_ads: bool) -> void:
	if is_ads:
		_fire(&"ads")


func _on_shop_opened() -> void:
	_fire(&"shop")


## Fresh player scene per run - rebind rather than assume the old
## MovementComponent (now freed) is still good.
func _on_game_state_changed(new_state: int) -> void:
	if new_state == GameManager.State.PLAYING:
		_bind_player.call_deferred()


# Signal handlers - MovementComponent

func _on_movement_state_changed(new_state: MovementComponent.State) -> void:
	if new_state == MovementComponent.State.SLIDING:
		_fire(&"slide")


func _on_started_moving() -> void:
	_fire(&"move")


func _on_jumped() -> void:
	_fire(&"jump")


func _on_mantled() -> void:
	_fire(&"mantle")


# Private

func _load_catalog() -> void:
	_hints_by_id.clear()
	if not ResourceLoader.exists(CATALOG_PATH):
		return
	var catalog: TutorialHintCatalog = load(CATALOG_PATH)
	for hint: TutorialHint in catalog.hints:
		if hint != null:
			_hints_by_id[hint.id] = hint


func _bind_player() -> void:
	var player: Player = Players.local() as Player
	if player == null or player.movement == null or player.movement == _movement:
		return
	_movement = player.movement
	_movement.state_changed.connect(_on_movement_state_changed)
	_movement.started_moving.connect(_on_started_moving)
	_movement.jumped.connect(_on_jumped)
	_movement.mantled.connect(_on_mantled)


func _fire(id: StringName) -> void:
	if SaveManager.has_seen_hint(id):
		return
	var hint: TutorialHint = _hints_by_id.get(id)
	if hint == null:
		return
	SaveManager.mark_hint_seen(id)
	if _queue.size() >= MAX_QUEUED:
		return
	_queue.push_back(hint)


## Guards _current itself, not just the _process() caller - hints never
## overlap is a hard invariant, not an accident of who happens to call this.
func _try_show_next() -> void:
	if _current != null or _queue.is_empty():
		return
	_current = _queue.pop_front()
	_time_left = maxf(_current.duration, 0.1)
	hint_shown.emit(_resolve_text(_current), _time_left)


func _finish_current() -> void:
	_current = null
	hint_hidden.emit()


## Substitutes the live-bound key for `hint.action`'s first key event into the
## first "{action}" placeholder - a remapped key is never wrong, and a hint
## with no action (movement, the shop) passes its text through untouched.
func _resolve_text(hint: TutorialHint) -> String:
	if hint.action == &"" or not _text_has_placeholder(hint.text):
		return hint.text
	return hint.text.replace("{action}", _key_label(hint.action))


func _text_has_placeholder(text: String) -> bool:
	return text.find("{action}") >= 0


func _key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			return OS.get_keycode_string(key.physical_keycode)
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse != null:
			return "MOUSE %d" % mouse.button_index
	return "?"
