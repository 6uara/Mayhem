class_name LoadingScreen
extends CanvasLayer
## What the player looks at while a scene is actually being read off disk.
##
## It exists because change_scene_to_file() is synchronous: it loads the whole
## scene - the arena, every enemy model, 100MB of textures - on the main thread
## before it returns. Cold, that measured over ten seconds, and every one of them
## was spent with the process not answering the window manager. The fade covered
## it, so it did not read as a crash; it read as the game having stopped.
##
## GameManager loads through ResourceLoader's threaded path now and this shows the
## progress. Deliberately cheap to draw - a label, a percentage and a bar - because
## the frames it renders are competing with the load it is reporting on.
##
## Sits at layer 9, directly under SceneTransition's 10: the wipe has to be able to
## cover this too, since revealing and hiding it are themselves scene transitions.

## How much of the bar's travel is smoothed rather than snapped. ResourceLoader
## reports progress in stages, so the raw value arrives in jumps - a bar that
## teleports reads as broken, and one that eases reads as work happening.
const BAR_CATCHUP_SPEED: float = 3.0
const BAR_SIZE: Vector2 = Vector2(560.0, 6.0)

@onready var _percent: Label = $Root/Column/Percent
@onready var _bar: SegmentStrip = $Root/Column/Bar

## Where the bar is being told to go, 0..1.
var _target: float = 0.0
## Where it is actually drawn, chasing `_target`.
var _shown: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 9
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_shown = move_toward(_shown, _target, BAR_CATCHUP_SPEED * delta)
	_bar.filled = int(round(_shown * float(_bar.count)))
	_percent.text = "%d%%" % int(round(_shown * 100.0))


# Public API

## Puts the screen up at zero. Call before the first set_progress().
func begin() -> void:
	_target = 0.0
	_shown = 0.0
	_bar.filled = 0
	_percent.text = "0%"
	visible = true


## `value` is 0..1. Values that go backwards are ignored: ResourceLoader's
## reported progress is not guaranteed monotonic across stages, and a bar that
## retreats tells the player the load is failing when it is not.
func set_progress(value: float) -> void:
	_target = maxf(_target, clampf(value, 0.0, 1.0))


## Snaps to full and takes the screen down. The snap is on purpose - the load is
## already over, and easing the last of the bar would hold the player on a screen
## whose job is finished.
func finish() -> void:
	_target = 1.0
	_shown = 1.0
	_bar.filled = _bar.count
	_percent.text = "100%"
	visible = false
