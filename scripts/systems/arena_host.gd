class_name ArenaHost
extends Node3D
## Puts an arena file into the game scene.
##
## MAYHEM used to carry one hand-built arena inside `game.tscn`. Now the match
## scene is arena-agnostic: this node loads whichever arena applies and hands the
## player spawn to the spawn controller before it readies.
##
## Three sources, in order of precedence:
##   1. The arena the player is playtesting from the in-game editor.
##   2. The one they picked on the Play screen.
##   3. The one the Godot dock's Play button wrote into project settings.
##   4. `default_arena`, which is what a run with no choice made uses.

const ARENA_PATH_SETTING: String = "mayhem_tools/playtest/arena_path"
const DEFAULT_CATALOG_PATH: String = "res://data/arena_pieces/default_catalog.tres"

## The arena a run happens in when nobody asked for another one.
@export var default_arena: ArenaData
@export var catalog: PieceCatalog
## Told where to put the player, before it spawns one.
@export var player_spawn_controller: PlayerSpawnController

var runtime: ArenaRuntime


func _ready() -> void:
	var arena: ArenaData = _pick_arena()
	var piece_catalog: PieceCatalog = _pick_catalog()
	if arena == null or piece_catalog == null:
		push_error("ArenaHost: no arena to load")
		return
	runtime = ArenaLoader.load_arena(arena, self, piece_catalog)
	if runtime == null:
		return
	# Para que un reporte de feedback diga en que arena paso sin preguntarselo al
	# jugador, que es la clase de dato que escrito a mano no llega nunca.
	FeedbackManager.set_arena_name(arena.arena_name)
	if player_spawn_controller != null:
		player_spawn_controller.spawn_point = runtime.get_player_spawn()


# Private

func _pick_arena() -> ArenaData:
	var session: Node = get_node_or_null(^"/root/ArenaSession")
	if session != null and bool(session.get(&"is_playtesting")):
		var playtest: ArenaData = session.get(&"arena")
		if playtest != null:
			return playtest
	if session != null:
		var chosen: ArenaData = session.call(&"get_run_arena")
		if chosen != null:
			return chosen
	# The dock's Play button writes a path into project settings. Only honoured
	# in an editor run: in a shipped build that setting points at a temp file
	# from someone else's machine.
	var path: String = str(ProjectSettings.get_setting(ARENA_PATH_SETTING, ""))
	if OS.has_feature("editor") and path != "" and ResourceLoader.exists(path):
		var from_settings: ArenaData = ArenaIO.load_arena(path)
		if from_settings != null:
			return from_settings
	return default_arena


func _pick_catalog() -> PieceCatalog:
	if catalog != null:
		return catalog
	var session: Node = get_node_or_null(^"/root/ArenaSession")
	if session != null and session.get(&"catalog") != null:
		return session.get(&"catalog")
	return load(DEFAULT_CATALOG_PATH) as PieceCatalog
