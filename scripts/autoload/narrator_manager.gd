extends Node
## The Host's VO: priority queue with per-line and per-category cooldowns.
## Never blocks gameplay. Subtitles are supported with or without audio.

signal subtitle_shown(text: String, duration: float, tier: int)
signal subtitle_hidden()

## Higher priority preempts lower. Critical state lines beat flavor.
enum Priority { FLAVOR = 0, FEEDBACK = 1, STATE = 2, CRITICAL = 3 }

## Subtitle treatment, per SPEC-MENUS-HOST 7.3.
##   STANDARD  - amber rail, HOST tag. Taunts and commentary.
##   WARNING   - acid rail. Lines carrying a threat the player must act on.
##   PUNCHLINE - no tag, the line itself in display type. Once per wave, or it
##               stops landing.
enum Tier { STANDARD = 1, WARNING = 2, PUNCHLINE = 3 }

const DEFAULT_CATEGORY_COOLDOWN: float = 8.0
## He addresses the crowd, not the player, and he does it sparingly - a Host who
## never shuts up stops being cruel and starts being noise.
const LINE_COOLDOWN: float = 20.0
const DEFAULT_LINE_COOLDOWN: float = 30.0
const PLACEHOLDER_DURATION: float = 2.5

var is_speaking: bool = false

var _queue: Array[Dictionary] = []
var _category_cooldowns: Dictionary = {}  # StringName -> seconds remaining
var _line_cooldowns: Dictionary = {}      # StringName -> seconds remaining
var _current_priority: int = -1
var _since_last_line: float = LINE_COOLDOWN
var _punchlines_this_wave: int = 0
## Incremented on every line start so a preempted line's timer cannot stop its successor.
var _generation: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.wave_started.connect(_on_wave_started.unbind(2))


func _process(delta: float) -> void:
	_since_last_line += delta
	_tick_cooldowns(_category_cooldowns, delta)
	_tick_cooldowns(_line_cooldowns, delta)
	if not is_speaking:
		_try_play_next()


# Public API

## Request a line. Silently ignored while its line/category cooldown is active.
func request_line(line_id: StringName, category: StringName, text: String,
		priority: Priority = Priority.FLAVOR, stream: AudioStream = null,
		tier: Tier = Tier.STANDARD) -> void:
	if _line_cooldowns.has(line_id) or _category_cooldowns.has(category):
		return
	# A punchline is allowed to break the pacing rule; ordinary chatter is not.
	var is_paced: bool = tier != Tier.PUNCHLINE and priority < Priority.CRITICAL
	if is_paced and _since_last_line < LINE_COOLDOWN:
		return
	if tier == Tier.PUNCHLINE:
		if _punchlines_this_wave >= Tokens.HOST_PUNCHLINE_PER_WAVE:
			return
		_punchlines_this_wave += 1
	if is_speaking and int(priority) > _current_priority:
		_stop_current()
	_queue.push_back({
		"line_id": line_id,
		"category": category,
		"text": text,
		"priority": int(priority),
		"stream": stream,
		"tier": int(tier),
	})
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]))


func clear_queue() -> void:
	_queue.clear()


# Private

func _try_play_next() -> void:
	if _queue.is_empty():
		return
	var line: Dictionary = _queue.pop_front()
	_play(line)


func _play(line: Dictionary) -> void:
	is_speaking = true
	_generation += 1
	var generation: int = _generation
	_current_priority = int(line["priority"])
	_line_cooldowns[line["line_id"]] = DEFAULT_LINE_COOLDOWN
	_category_cooldowns[line["category"]] = DEFAULT_CATEGORY_COOLDOWN

	var stream: AudioStream = line["stream"]
	var duration: float = PLACEHOLDER_DURATION
	if stream != null:
		duration = stream.get_length()
		AudioPool.play_2d(stream, AudioPool.BUS_VO)
	AudioPool.push_duck()
	_since_last_line = 0.0
	subtitle_shown.emit(String(line["text"]), duration, int(line["tier"]))

	await get_tree().create_timer(duration).timeout
	if generation == _generation:
		_stop_current()


func _stop_current() -> void:
	if not is_speaking:
		return
	is_speaking = false
	_current_priority = -1
	AudioPool.pop_duck()
	subtitle_hidden.emit()


func _on_wave_started() -> void:
	_punchlines_this_wave = 0


func _tick_cooldowns(dictionary: Dictionary, delta: float) -> void:
	if dictionary.is_empty():
		return
	for key: Variant in dictionary.keys():
		var remaining: float = dictionary[key] - delta
		if remaining <= 0.0:
			dictionary.erase(key)
		else:
			dictionary[key] = remaining
