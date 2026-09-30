extends Node
## Loads, saves and applies user settings. Touches no gameplay logic.

const SETTINGS_PATH: String = "user://settings.cfg"

## `video/fps_cap` value that means "whatever the monitor refreshes at".
const FPS_CAP_MONITOR: int = -1
## `video/anti_aliasing` values.
const ANTI_ALIASING_OFF: int = 0
const ANTI_ALIASING_FXAA: int = 1
const ANTI_ALIASING_MSAA_2X: int = 2
const ANTI_ALIASING_MSAA_4X: int = 3
const ANTI_ALIASING_TAA: int = 4

## Defaults come from the design handoff (theme_tokens.gd), not from taste.
const DEFAULTS: Dictionary = {
	"input/mouse_sensitivity": 2.40,
	"input/ads_sensitivity_multiplier": 0.72,
	"input/invert_y": false,
	## Grados por segundo con el stick derecho a fondo. Ver Player._tick_stick_look().
	"input/stick_sensitivity": 200.0,
	## Quick cast: el gadget sale al apretar la tecla. Apagado, la tecla lo pone
	## en la mano y el jugador elige cuando lanzarlo con el disparo.
	##
	## Por defecto en quick cast porque es el esquema con el que se diseñaron los
	## cooldowns y el ritmo de las oleadas; el otro existe porque no todos leen
	## una granada como algo que se tira sin mirar. Ver UtilityComponent.
	"input/gadget_quick_cast": true,
	## The arena editor shows its controls the first time and never again on its
	## own. Persisted so "never again" survives closing the game.
	"editor/help_seen": false,
	"video/fov": 104.0,
	"video/fullscreen": true,
	"video/vsync": false,
	## FPS_CAP_MONITOR sigue a la frecuencia del monitor. Era 60 fijo: en un shooter
	## con V-Sync apagado, un monitor de 144Hz mostraba 60 cuadros y el input lag de 60.
	"video/fps_cap": -1,
	## Porcentaje de la resolucion a la que se dibuja el 3D, escalado con FSR 1. La
	## HUD y los menus quedan siempre a resolucion nativa.
	"video/render_scale": 100,
	## Ver ANTI_ALIASING_*. Apagado por defecto porque es como se vio siempre.
	"video/anti_aliasing": 0,
	## 0 bajo, 1 medio, 2 alto. Alto es lo que el proyecto dibujaba antes de que
	## existiera la opcion (atlas de 4096, filtro suave bajo).
	"video/shadow_quality": 2,
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


## The actions the options screen lets the player rebind, in the order it lists
## them, with the name it shows. Menu keys (pause, the dev console) stay fixed: a
## player who rebinds pause onto a key they then forget cannot reach this screen
## again to undo it.
const REBINDABLE_ACTIONS: Array = [
	[&"move_forward", "Move forward"], [&"move_back", "Move back"],
	[&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"jump", "Jump"], [&"crouch_slide", "Crouch / slide"], [&"dash", "Dash"],
	[&"grapple", "Grapple"], [&"fire", "Fire"], [&"ads", "Aim down sights"],
	[&"reload", "Reload"], [&"interact", "Interact"],
	[&"utility_1", "Gadget 1"], [&"utility_2", "Gadget 2"], [&"utility_3", "Gadget 3"],
]


## Binds `event` as the keyboard/mouse input of `action`.
##
## Only the keyboard and mouse events are replaced: a gamepad binding on the same
## action is a different device and survives. If another rebindable action was
## already on that input, the two swap - leaving it on both would make one of them
## unreachable, and leaving the other one with nothing is worse than a swap.
func rebind_primary(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action) or not _is_key_or_mouse(event):
		return
	var previous: InputEvent = get_primary_event(action)
	for entry: Array in REBINDABLE_ACTIONS:
		var other: StringName = entry[0]
		if other == action or not InputMap.has_action(other):
			continue
		var other_primary: InputEvent = get_primary_event(other)
		if other_primary != null and _same_input(other_primary, event):
			_set_primary(other, previous)
	_set_primary(action, event)


## The keyboard or mouse event an action shows on screen - the first one bound.
func get_primary_event(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if _is_key_or_mouse(event):
			return event
	return null


## What a binding is called on screen. Physical keycodes, so it names the key by
## where it is and a WASD layout reads the same on an AZERTY board.
func describe_event(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE \
			else key.keycode
		return OS.get_keycode_string(code)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		match mouse.button_index:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			_: return "Mouse %d" % mouse.button_index
	return "-"


func _set_primary(action: StringName, event: InputEvent) -> void:
	var events: Array[InputEvent] = []
	if event != null:
		events.append(event)
	for existing: InputEvent in InputMap.action_get_events(action):
		if not _is_key_or_mouse(existing):
			events.append(existing)
	rebind_action(action, events)


static func _is_key_or_mouse(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	var key_a := a as InputEventKey
	var key_b := b as InputEventKey
	if key_a != null and key_b != null:
		return key_a.physical_keycode == key_b.physical_keycode \
			and key_a.keycode == key_b.keycode
	var mouse_a := a as InputEventMouseButton
	var mouse_b := b as InputEventMouseButton
	return mouse_a != null and mouse_b != null \
		and mouse_a.button_index == mouse_b.button_index


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
	Engine.max_fps = resolve_fps_cap(int(get_value("video/fps_cap")))
	_apply_render_quality()


## The cap Engine.max_fps gets for a setting value. FPS_CAP_MONITOR reads the
## monitor the window is on; a monitor that does not report (some remote desktops
## and capture setups say 0 or -1) falls back to the old fixed 60 rather than to
## uncapped, which on a laptop is a fan at full speed for frames nobody sees.
func resolve_fps_cap(setting: int, refresh_rate: float = NAN) -> int:
	if setting != FPS_CAP_MONITOR:
		return maxi(setting, 0)
	var rate: float = refresh_rate
	if is_nan(rate):
		rate = DisplayServer.screen_get_refresh_rate()
	return roundi(rate) if rate > 1.0 else 60


func _apply_render_quality() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	# Render scale. FSR 1 because it is a single cheap pass that any GPU the
	# Forward+ renderer runs on can afford - which is the point of turning it down.
	var scale: float = clampf(float(get_value("video/render_scale")) / 100.0, 0.25, 1.0)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 \
		else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = scale

	var aa: int = int(get_value("video/anti_aliasing"))
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == ANTI_ALIASING_FXAA \
		else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X if aa == ANTI_ALIASING_MSAA_2X \
		else Viewport.MSAA_4X if aa == ANTI_ALIASING_MSAA_4X \
		else Viewport.MSAA_DISABLED
	viewport.use_taa = aa == ANTI_ALIASING_TAA

	var quality: int = clampi(int(get_value("video/shadow_quality")), 0, 2)
	var atlas: int = [1024, 2048, 4096][quality]
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	viewport.positional_shadow_atlas_size = atlas
	var filter: int = [RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW][quality]
	RenderingServer.directional_soft_shadow_filter_set_quality(filter)
	RenderingServer.positional_soft_shadow_filter_set_quality(filter)


func _apply_bindings() -> void:
	for action: String in _bindings:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for event: Variant in _bindings[action]:
			if event is InputEvent:
				InputMap.action_add_event(action, event)
