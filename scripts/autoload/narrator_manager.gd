extends Node
## The Host's VO: priority queue with per-line and per-category cooldowns.
## Never blocks gameplay. Subtitles are supported with or without audio.

signal subtitle_shown(text: String, duration: float)
signal subtitle_hidden()

## Higher priority preempts lower. Critical state lines beat flavor.
enum Priority { FLAVOR = 0, FEEDBACK = 1, STATE = 2, CRITICAL = 3 }

const DEFAULT_CATEGORY_COOLDOWN: float = 8.0
const DEFAULT_LINE_COOLDOWN: float = 30.0
const PLACEHOLDER_DURATION: float = 2.5

var is_speaking: bool = false

var _queue: Array[Dictionary] = []
var _category_cooldowns: Dictionary = {}  # StringName -> seconds remaining
var _line_cooldowns: Dictionary = {}      # StringName -> seconds remaining
var _current_priority: int = -1
## Incremented on every line start so a preempted line's timer cannot stop its successor.
var _generation: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_tick_cooldowns(_category_cooldowns, delta)
	_tick_cooldowns(_line_cooldowns, delta)
	if not is_speaking:
		_try_play_next()


# Public API

## Request a line. Silently ignored while its line/category cooldown is active.
func request_line(line_id: StringName, category: StringName, text: String,
		priority: Priority = Priority.FLAVOR, stream: AudioStream = null) -> void:
	if _line_cooldowns.has(line_id) or _category_cooldowns.has(category):
		return
	if is_speaking and int(priority) > _current_priority:
		_stop_current()
	_queue.push_back({
		"line_id": line_id,
		"category": category,
		"text": text,
		"priority": int(priority),
		"stream": stream,
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
	subtitle_shown.emit(String(line["text"]), duration)

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


func _tick_cooldowns(dictionary: Dictionary, delta: float) -> void:
	if dictionary.is_empty():
		return
	for key: Variant in dictionary.keys():
		var remaining: float = dictionary[key] - delta
		if remaining <= 0.0:
			dictionary.erase(key)
		else:
			dictionary[key] = remaining
