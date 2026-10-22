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
	# Y para que la run se anote en la tabla de esta arena y no en otra.
	RunRecord.set_arena(_arena_id(arena), arena.arena_name)
	# Lo que queda adentro de la pared perimetral, para que un enemigo que aparece
	# o termina afuera se devuelva solo. Ver ArenaBounds.
	ArenaBounds.set_box(runtime.get_content_bounds())
	if player_spawn_controller != null:
		player_spawn_controller.spawn_point = runtime.get_player_spawn()


func _exit_tree() -> void:
	ArenaBounds.clear()


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


## Con que clave se anota esta arena en la tabla. El archivo de donde salio, que
## es estable; el nombre se puede repetir entre arenas distintas.
func _arena_id(arena: ArenaData) -> String:
	if arena.resource_path != "":
		return arena.resource_path
	var session: Node = get_node_or_null(^"/root/ArenaSession")
	if session != null:
		var path: String = str(session.get(&"run_arena_path"))
		if bool(session.get(&"is_playtesting")):
			path = str(session.get(&"current_path"))
		if path != "":
			return path
	return "arena:%s" % arena.arena_name


func _pick_catalog() -> PieceCatalog:
	if catalog != null:
		return catalog
	var session: Node = get_node_or_null(^"/root/ArenaSession")
	if session != null and session.get(&"catalog") != null:
		return session.get(&"catalog")
	return load(DEFAULT_CATALOG_PATH) as PieceCatalog
