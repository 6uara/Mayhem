extends SceneTree
## Measures real frame time with the largest authored wave (wave_10: 27 enemies,
## an elite wave) fully spawned and alive. Section 10 of CLAUDE.md: "hold 60 FPS
## on a full elite wave" - this is the profiling pass that checks that claim
## against real numbers instead of an impression (backlog tanda G2).
##
## MUST run with real rendering, NOT --headless - headless skips the renderer
## entirely, so any FPS read there would only ever measure script/physics cost,
## missing the GPU-bound half of the question (glow, particles, decals, the
## panel shaders).
##
##     godot --path . -s tools/profile_elite_wave.gd -- [seconds] [fire]
##
## Con `fire` el jugador dispara sin parar durante la medicion. Es la unica forma
## de que el costo de los proyectiles aparezca en el numero: quieto, el arma no
## tira nada y la pregunta "cuanto cuestan los proyectiles" no se puede
## contestar con este perfil.
##
## `seconds` (default 20) is how long to sample after the wave is fully spawned.
## Prints min/avg/max FPS and a percentage of frames under 60, then quits.
## Does not touch git-tracked state - read-only instrumentation.

const GAME_SCENE_PATH: String = "res://scenes/main/game.tscn"
## Frames to let the scene tree finish _ready() (EnemySpawner registering
## itself with WaveManager, the player's viewmodel rig spinning up, etc.)
## before jumping straight to wave 10.
const SETTLE_FRAMES: int = 30
## Real SECONDS, not frames - wave_10's spawn groups stagger over several
## seconds of wall-clock time (SpawnGroup.delay/interval, both time-based) no
## matter the frame rate. Once vsync/the fps cap are removed for the actual
## measurement, this scene renders at 700+ FPS, so 1800 FRAMES is only ~2.5
## real seconds - nowhere near enough. Cost one debugging round-trip the first
## time this tool ran (it settled on 4/27 enemies, having silently mistaken
## "frames elapsed" for "seconds elapsed" in its own progress log).
const MAX_SPAWN_WAIT_SECONDS: float = 90.0

var _sample_seconds: float = 20.0
## Con el gatillo apretado durante la medicion.
var _firing: bool = false
var _holder: Node
var _frame: int = 0
var _sampling: bool = false
var _sample_time: float = 0.0
var _samples: Array[float] = []
var _game: Node
var _waiting_for_spawn: bool = false
var _spawn_wait_time: float = 0.0
var _last_log_second: int = -1
## Sum of wave_10's own authored SpawnGroup counts - computed rather than
## hardcoded so this tool stays correct if the wave content changes.
var _expected_alive: int = 0
## Fetched via get_node("/root/WaveManager") rather than the bare WaveManager
## identifier - a static reference to an autoload identifier forces the
## GDScript compiler to resolve it (and its own dependencies) while compiling
## THIS script, which happens before autoloads exist for a custom -s MainLoop
## script and fails with "Identifier not found". Same gotcha documented in
## tools/export_host_script.gd.
var _wave_manager: Node


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for argument: String in args:
		if argument == "fire":
			_firing = true
	if not args.is_empty():
		_sample_seconds = args[0].to_float()
	var packed: PackedScene = load(GAME_SCENE_PATH)
	_game = packed.instantiate()
	root.add_child(_game)
	print("Loaded %s, settling %d frames before forcing wave 10..." % [
		GAME_SCENE_PATH, SETTLE_FRAMES])


func _process(delta: float) -> bool:
	_frame += 1
	if _firing:
		_hold_the_trigger()

	if _frame == SETTLE_FRAMES:
		_wave_manager = root.get_node("/root/WaveManager")
		# The game's own settings apply a video/fps_cap default of 60 and may
		# leave vsync on - both would silently ceiling this measurement at the
		# monitor's refresh rate regardless of true render cost, which is
		# exactly what happened uncorrected (a flat, useless 60/60/60 read).
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_make_player_invincible()
		_bind_weapon()
		_force_wave_10()
		_waiting_for_spawn = true
		return false

	if _waiting_for_spawn:
		_spawn_wait_time += delta
		var current_second: int = int(_spawn_wait_time)
		if current_second != _last_log_second:
			_last_log_second = current_second
			print("  t+%ds: alive=%d remaining=%d is_wave_active=%s" % [
				current_second, _wave_manager.get_alive_count(),
				_wave_manager.get_remaining_count(), _wave_manager.is_wave_active])
		var alive: int = _wave_manager.get_alive_count()
		# Waiting for remaining == alive (every scheduled spawn landed, nothing
		# pending) never actually happens for wave_10: it includes a Summoner,
		# which keeps adding enemies for as long as it's alive and nothing is
		# killing it (see 05 Enemies and AI - "spawns adds over time,
		# punishes slow clears") - left alone, this tool would wait the full
		# MAX_SPAWN_WAIT_SECONDS every run instead of sampling once the wave's
		# own authored pressure (_expected_alive) is actually on screen. Reaching
		# _expected_alive is the real question CLAUDE.md's "hold 60 on a full
		# elite wave" is asking about; whatever the Summoner adds on top during
		# the sample window is realistic ongoing pressure, not noise to wait out.
		if alive >= _expected_alive or _spawn_wait_time >= MAX_SPAWN_WAIT_SECONDS:
			print("Wave 10 reached %d/%d enemies after %.1fs. Sampling %.0fs..." % [
				alive, _expected_alive, _spawn_wait_time, _sample_seconds])
			_waiting_for_spawn = false
			_sampling = true
		return false

	if _sampling:
		_sample_time += delta
		_samples.push_back(Engine.get_frames_per_second())
		if _sample_time >= _sample_seconds:
			_report()
			quit()
			return true

	return false


## Nothing here fights back or moves the player - left alone, 27 aggroed
## enemies kill it in seconds, which fires EventBus.player_died ->
## WaveManager.reset() and wipes the whole wave mid-measurement (this
## happened the first time: alive count climbed to 16/27 then dropped to 0
## and stayed there, is_wave_active flipping false, at t+12s). Zeroing
## damage_taken_multiplier is enough - apply_damage() multiplies incoming
## damage by it before subtracting, so this is a real "cannot die", not a
## race against a heal-every-frame patch that a single lucky big hit could
## still beat.
## Deja el gatillo apretado y la municion llena.
##
## Recargar cortaria la cadencia a la mitad y el perfil terminaria midiendo
## pausas de recarga en vez de disparos. La municion se rellena a mano por eso, y
## porque lo que se quiere medir es el costo sostenido, no el realista.
## El arma se relee cada frame en vez de guardarse: cambiar de arma es un swap de
## 0.35s, asi que una referencia tomada antes apunta a la anterior - que despues
## del swap deja de procesar, y apretarle el gatillo no dispara nada. Esa version
## de esto midio una corrida entera creyendo que estaba disparando.
func _hold_the_trigger() -> void:
	if _holder == null or not is_instance_valid(_holder):
		return
	var weapon: Node = _holder.get("current")
	if weapon == null:
		return
	weapon.set("_ammo", 999)
	weapon.call("set_trigger", true)


func _bind_weapon() -> void:
	if not _firing:
		return
	var player: Node = _game.get_node_or_null("Player")
	if player == null:
		return
	var holder: Node = player.get("weapon_holder")
	if holder == null:
		return
	# La SMG, no la pistola con la que arranca el jugador: 15 disparos por segundo
	# contra 5. Lo que se quiere medir es el techo de proyectiles en vuelo, y con
	# el arma inicial el numero sale tres veces mas bajo de lo que el juego llega
	# a pedir.
	holder.call("acquire", &"smg")
	_holder = holder
	if holder.get("current") == null:
		push_warning("profile_elite_wave: no hay arma equipada, se mide sin disparar")


func _make_player_invincible() -> void:
	var player: Node = _game.get_node_or_null("Player")
	if player == null:
		push_warning("profile_elite_wave: no Player node, can't make it invincible")
		return
	var health: Node = player.get("health")
	if health != null:
		health.set("damage_taken_multiplier", 0.0)


func _force_wave_10() -> void:
	var director: Node = _game.get_node_or_null("MatchDirector")
	if director == null:
		push_error("profile_elite_wave: no MatchDirector in %s" % GAME_SCENE_PATH)
		quit(1)
		return
	var waves: Array = director.get("waves")
	if waves.size() < 10:
		push_error("profile_elite_wave: MatchDirector has %d waves, need 10" % waves.size())
		quit(1)
		return

	var wave_10: Resource = waves[9]
	_expected_alive = 0
	for group: Resource in wave_10.get("spawn_groups"):
		_expected_alive += int(group.get("count"))

	_wave_manager.reset()
	_wave_manager.setup(waves)
	_wave_manager.current_index = 8  # start_next_wave() advances to 9 = wave_10.tres
	if not _wave_manager.start_next_wave():
		push_error("profile_elite_wave: start_next_wave() refused wave 10")
		quit(1)


func _report() -> void:
	if _samples.is_empty():
		print("No samples collected.")
		return
	var total: float = 0.0
	var minimum: float = _samples[0]
	var maximum: float = _samples[0]
	var under_60: int = 0
	for fps: float in _samples:
		total += fps
		minimum = minf(minimum, fps)
		maximum = maxf(maximum, fps)
		if fps < 60.0:
			under_60 += 1
	var average: float = total / _samples.size()
	print("--- wave 10 profile (%d samples, %.0fs) ---" % [_samples.size(), _sample_time])
	print("  min %.1f  avg %.1f  max %.1f FPS" % [minimum, average, maximum])
	print("  %.1f%% of frames under 60 FPS" % (100.0 * under_60 / _samples.size()))
