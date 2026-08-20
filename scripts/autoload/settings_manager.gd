extends Node
## Loads, saves and applies user settings. Touches no gameplay logic.

const SETTINGS_PATH: String = "user://settings.cfg"

## Defaults come from the design handoff (theme_tokens.gd), not from taste.
const DEFAULTS: Dictionary = {
	"input/mouse_sensitivity": 2.40,
	"input/ads_sensitivity_multiplier": 0.72,
	"input/invert_y": false,
	## Quick cast: el gadget sale al apretar la tecla. Apagado, la tecla lo pone
	## en la mano y el jugador elige cuando lanzarlo con el disparo.
	##
	## Por defecto en quick cast porque es el esquema con el que se diseñaron los
	## cooldowns y el ritmo de las oleadas; el otro existe porque no todos leen
	## una granada como algo que se tira sin mirar. Ver UtilityComponent.
	"input/gadget_quick_cast": true,
	"video/fov": 104.0,
	"video/fullscreen": true,
	"video/vsync": false,
	"video/fps_cap": 60,
	"audio/master_volume": 1.0,
	"audio/sfx_volume": 1.0,
	"audio/music_volume": 0.7,
	"audio/vo_volume": 1.0,
	## String, not StringName - ConfigFile round-trips String cleanly; NarratorManager
	## wraps it back into a StringName on read. See NarratorManager.current_presenter_id.
	"audio/host_presenter": "subtitles_only",
	"accessibility/screenshake_enabled": true,
	"accessibility/motion_blur_enabled": false,
	## View bob is the most common motion-sickness trigger in a first-person game,
	## and it carries no information the player needs - so it gets its own switch
	## rather than riding along with screenshake.
	"accessibility/view_bob_enabled": true,
	"accessibility/subtitles_enabled": true,
	## Replaces the low-health pulse and low-ammo blink with static frames of the
	## same colour, so no information is lost (SPEC-MENUS-HOST 3.3).
	"accessibility/reduce_flashing": false,
	"accessibility/subtitle_size": 1,
	## Screen-space speed lines are the visual half of the same reward
	## Player._tick_speed_fov() sells with the camera - a distinct discomfort
	## trigger from screenshake, so it gets its own switch rather than riding
	## along with it.
	"accessibility/speed_lines_enabled": true,
	"hud/scale": 1.0,
	"hud/crosshair_gap": 8.0,
	"hud/crosshair_thickness": 2.0,
	"hud/crosshair_color": Color("#E6E8EF"),
	"hud/crosshair_dot": true,
	"hud/damage_indicators": true,
	"hud/damage_numbers": true,
}

var _values: Dictionary = {}
## action name -> Array of serialized InputEvent
var _bindings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = DEFAULTS.duplicate(true)
	load_settings()
	apply_all()


# Public API

## `fallback` covers keys a caller knows about before they exist in DEFAULTS,
## so a new setting cannot crash the UI that reads it.
func get_value(key: String, fallback: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return fallback


func set_value(key: String, value: Variant) -> void:
	_values[key] = value


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	_bindings.clear()
	InputMap.load_from_project_settings()
	apply_all()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return  # First run: defaults already in place.
	for key: String in DEFAULTS:
		var parts: PackedStringArray = key.split("/", true, 1)
		_values[key] = config.get_value(parts[0], parts[1], DEFAULTS[key])
	if config.has_section("bindings"):
		for action: String in config.get_section_keys("bindings"):
			_bindings[action] = config.get_value("bindings", action, [])
	_apply_bindings()


func save_settings() -> void:
	var config := ConfigFile.new()
	for key: String in _values:
		var parts: PackedStringArray = key.split("/", true, 1)
		config.set_value(parts[0], parts[1], _values[key])
	for action: String in _bindings:
		config.set_value("bindings", action, _bindings[action])
	var error: int = config.save(SETTINGS_PATH)
	if error != OK:
		push_error("SettingsManager: failed to save settings (%d)" % error)


func apply_all() -> void:
	_apply_audio()
	_apply_video()
	EventBus.settings_applied.emit()


## Replace every event bound to `action`. Persists on save_settings().
func rebind_action(action: StringName, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action):
		push_error("SettingsManager: unknown action '%s'" % action)
		return
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)
	_bindings[String(action)] = events


## Degrees of look per pixel of mouse travel at the slider's default position.
##
## Two things have to be true at once: the settings screen shows the handoff's
## 0.1-10 slider (2.40 by default, as in the mockup), and the game has to actually
## feel like 0.25 degrees per pixel out of the box. Pinning the feel here and
## deriving the scale from the token means moving the slider's default position
## can never silently change how the game plays.
const SENS_DEGREES_AT_DEFAULT: float = 0.25


## Degrees of look per pixel of mouse travel, for the current slider position.
func get_mouse_sensitivity(is_ads: bool) -> float:
	var slider: float = float(get_value("input/mouse_sensitivity"))
	var base: float = slider * (SENS_DEGREES_AT_DEFAULT / maxf(Tokens.SENS_DEFAULT, 0.01))
	if is_ads:
		base *= float(get_value("input/ads_sensitivity_multiplier"))
	return base


# Private

func _apply_audio() -> void:
	# AudioPool owns the final dB per bus so VO ducking is not clobbered here.
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MASTER, float(get_value("audio/master_volume")))
	AudioPool.set_bus_volume_linear(AudioPool.BUS_SFX, float(get_value("audio/sfx_volume")))
	AudioPool.set_bus_volume_linear(AudioPool.BUS_MUSIC, float(get_value("audio/music_volume")))
	AudioPool.set_bus_volume_linear(AudioPool.BUS_VO, float(get_value("audio/vo_volume")))


func _apply_video() -> void:
	var fullscreen: bool = bool(get_value("video/fullscreen"))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)
	var vsync: bool = bool(get_value("video/vsync"))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(get_value("video/fps_cap"))


func _apply_bindings() -> void:
	for action: String in _bindings:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for event: Variant in _bindings[action]:
			if event is InputEvent:
				InputMap.action_add_event(action, event)
