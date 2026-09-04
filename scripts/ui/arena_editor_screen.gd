class_name ArenaEditorScreen
extends Node3D
## The in-game arena editor: what the player gets from CREATE ARENA in the menu.
##
## It is the second face of the same tool. The Godot dock and this screen both
## drive `PlacementModel`, validate with `ArenaValidator` and preview with
## `ArenaPreview` - the only thing that differs is who is clicking. That split is
## the reason the editor's logic was kept out of the UI from the first commit.

const CLICK_DRAG_SLOP: float = 6.0
## Above this the venue is visibly pulled out of shape on one axis, and the
## designer deserves to know while they are still placing floor rather than
## after pressing Play.
const VENUE_STRETCH_WARNING: float = 1.25
## What the model's refusal codes mean to whoever just clicked.
const REFUSAL_TEXT: Dictionary = {
	&"out_of_bounds": "That is outside the grid.",
	&"cell_taken": "There is already a piece of that kind in the cell.",
	&"needs_floor": "That one needs a flat floor tile under it - not a ramp.",
	&"needs_empty": "That one hangs in the air: put it in a cell with no floor.",
	&"too_low": "That one has to go higher up.",
	&"unknown_piece": "That piece is not in the catalog.",
}

@onready var _camera: ArenaEditorCamera = $Camera
@onready var _preview: ArenaPreview = $Preview
@onready var _hud: ArenaEditorHUD = $UI/HUD

var model: PlacementModel
var tool_mode: ArenaPalettePanel.Tool = ArenaPalettePanel.Tool.PLACE
var selected_piece: StringName = &""
var pending_rotation: int = 0
var level: int = 0

var _hover_cell: Vector3i = Vector3i.ZERO
var _press_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	model = PlacementModel.new(ArenaSession.arena, ArenaSession.catalog)
	model.changed.connect(_on_model_changed)
	_preview.model = model
	_preview.level = level
	_hud.set_catalog(ArenaSession.catalog)
	_connect_hud()
	_hud.select_tool(int(tool_mode))
	_hud.set_arena_name(ArenaSession.arena.arena_name)
	_hud.set_level(level)
	_hud.set_rotation_steps(pending_rotation)
	_hud.set_grid_size(ArenaSession.arena.grid_size)
	_hud.set_theme_id(ArenaSession.arena.theme_id)
	_hud.set_status("Left click builds. Right drag orbits, WASD pans, wheel zooms. H for help.")
	_show_help_on_first_visit()
	if not ArenaSession.catalog.pieces.is_empty():
		_select_piece(ArenaSession.catalog.pieces[0].id)
	_camera.frame_grid(ArenaSession.arena.grid_size, ArenaSession.catalog.cell_size)
	_on_model_changed()


func _unhandled_input(event: InputEvent) -> void:
	if _camera.handle_input(event):
		return
	if _hud.is_typing():
		return
	if _handle_keys(event):
		return
	if _hud.is_modal_open():
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		_update_hover(motion.position)
		return

	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_position = button.position
		return
	# Released: a drag that orbited the camera must not also place a piece.
	if button.position.distance_to(_press_position) > CLICK_DRAG_SLOP:
		return
	_update_hover(button.position)
	_apply_tool(_hover_cell)


# Private

func _handle_keys(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			_set_tool(key.keycode - KEY_1)
		KEY_R:
			_rotate()
		KEY_Q:
			_set_level(level - 1)
		KEY_E:
			_set_level(level + 1)
		KEY_Z:
			if not model.undo():
				_hud.set_status("Nothing to undo.")
		KEY_DELETE:
			_set_tool(int(ArenaPalettePanel.Tool.ERASE))
		KEY_H:
			_hud.toggle_help()
		_:
			return false
	return true


func _connect_hud() -> void:
	_hud.tool_changed.connect(_set_tool)
	_hud.piece_selected.connect(_select_piece)
	_hud.level_changed.connect(_set_level)
	_hud.rotate_pressed.connect(_rotate)
	_hud.name_changed.connect(func(text: String) -> void: ArenaSession.arena.arena_name = text)
	_hud.new_pressed.connect(_on_new)
	_hud.save_pressed.connect(_on_save)
	_hud.load_requested.connect(_on_load_requested)
	_hud.play_pressed.connect(_on_play)
	_hud.exit_pressed.connect(_on_exit)
	_hud.issue_focused.connect(_focus_cell)
	_hud.size_changed.connect(_on_size_changed)
	_hud.delete_requested.connect(_on_delete_requested)
	_hud.venue_changed.connect(_on_venue_changed)


## Screen point to grid cell, against the floor plane of the working level - the
## same plane the pieces of that level are built up from.
func _cell_at(screen_position: Vector2) -> Vector3i:
	var cell_size: Vector3 = ArenaSession.catalog.cell_size
	var origin: Vector3 = _camera.project_ray_origin(screen_position)
	var direction: Vector3 = _camera.project_ray_normal(screen_position)
	var plane := Plane(Vector3.UP, float(level) * cell_size.y)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return _hover_cell
	var world: Vector3 = hit
	return Vector3i(
		int(round(world.x / cell_size.x)), level, int(round(world.z / cell_size.z)))


func _update_hover(screen_position: Vector2) -> void:
	var cell: Vector3i = _cell_at(screen_position)
	if cell == _hover_cell:
		return
	_hover_cell = cell
	_update_ghost()


func _update_ghost() -> void:
	if tool_mode != ArenaPalettePanel.Tool.PLACE or selected_piece == &"":
		_preview.hide_ghost()
		return
	_preview.show_ghost(selected_piece, _hover_cell, pending_rotation, _can_place())


## One source of truth for "can this go here": the model. The ghost asking the
## same question a second way is how a ghost ends up lying about what a click
## will do.
func _can_place() -> bool:
	return model.refusal_for(selected_piece, _hover_cell, pending_rotation, true) == &""


func _apply_tool(cell: Vector3i) -> void:
	match tool_mode:
		ArenaPalettePanel.Tool.PLACE:
			if selected_piece == &"":
				return
			var refusal: StringName = model.refusal_for(selected_piece, cell, pending_rotation)
			if refusal != &"":
				_hud.set_status(REFUSAL_TEXT.get(refusal, "That piece cannot go there."))
		ArenaPalettePanel.Tool.ERASE:
			if not (model.erase_at(cell) or model.remove_enemy_spawn(cell)):
				_hud.set_status("Nothing to erase there.")
		ArenaPalettePanel.Tool.PLAYER_SPAWN:
			model.set_player_spawn(cell)
		ArenaPalettePanel.Tool.ENEMY_SPAWN:
			if model.get_enemy_spawn_at(cell) != null:
				model.remove_enemy_spawn(cell)
			else:
				model.add_enemy_spawn(cell)


func _set_tool(new_tool: int) -> void:
	tool_mode = new_tool as ArenaPalettePanel.Tool
	_hud.select_tool(new_tool)
	_update_ghost()


func _select_piece(piece_id: StringName) -> void:
	selected_piece = piece_id
	_hud.select_piece(piece_id)
	if tool_mode != ArenaPalettePanel.Tool.PLACE:
		_set_tool(int(ArenaPalettePanel.Tool.PLACE))
	_update_ghost()


func _set_level(new_level: int) -> void:
	level = clampi(new_level, 0, model.arena.grid_size.y - 1)
	_preview.level = level
	_preview.rebuild()
	_hud.set_level(level)
	_update_ghost()


func _rotate() -> void:
	pending_rotation = posmod(pending_rotation + 1, 4)
	_hud.set_rotation_steps(pending_rotation)
	_update_ghost()


func _on_model_changed() -> void:
	ArenaSession.arena = model.arena
	_preview.rebuild()
	_hud.show_issues(ArenaSession.validate())
	_hud.set_venue_fit(_venue_fit_text())


## What the stands will have to do to fit what is built. Not a validation rule -
## a stretched venue is ugly, not broken - so it reads as a line under the list.
func _venue_fit_text() -> String:
	var footprint: Vector2 = _content_footprint()
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		return ""
	var theme: ArenaTheme = ArenaTheme.find(model.arena.theme_id)
	var stretch: float = theme.get_stretch(footprint)
	if stretch < VENUE_STRETCH_WARNING:
		return "Venue fits: %.0f x %.0f m." % [footprint.x, footprint.y]
	var suggested: Vector2 = theme.suggest_footprint(maxf(footprint.x, footprint.y))
	var cells: Vector3 = ArenaSession.catalog.cell_size
	return "Venue stretches %.1fx: the pit is %.1f:1 and this is %.1f:1. %d x %d cells would fit it." % [
		stretch, theme.pit_size.x / theme.pit_size.y, footprint.x / footprint.y,
		int(round(suggested.x / cells.x)), int(round(suggested.y / cells.z))]


## The built area in metres, which is what the venue is fitted to.
func _content_footprint() -> Vector2:
	if model.arena.placements.is_empty():
		return Vector2.ZERO
	var lowest: Vector3i = model.arena.placements[0].cell
	var highest: Vector3i = lowest
	for entry: PlacementEntry in model.arena.placements:
		lowest = lowest.min(entry.cell)
		highest = highest.max(entry.cell)
	var cells: Vector3 = ArenaSession.catalog.cell_size
	return Vector2(
		float(highest.x - lowest.x + 1) * cells.x, float(highest.z - lowest.z + 1) * cells.z)


## The first time a player opens the editor they get the controls unasked; after
## that it is on H, because a panel you have already read is in the way.
func _show_help_on_first_visit() -> void:
	if bool(SettingsManager.get_value("editor/help_seen", false)):
		return
	_hud.set_help_visible(true)
	SettingsManager.set_value("editor/help_seen", true)
	SettingsManager.save_settings()


## Growing the grid is always fine; shrinking it is refused while a piece would
## be left outside, rather than silently deleting someone's work.
func _on_size_changed(grid_size: Vector3i) -> void:
	if not ArenaSession.resize(grid_size):
		_hud.set_grid_size(model.arena.grid_size)
		_hud.set_status("Erase the pieces outside that size first.")
		return
	level = clampi(level, 0, model.arena.grid_size.y - 1)
	_hud.set_level(level)
	_camera.frame_grid(model.arena.grid_size, ArenaSession.catalog.cell_size)
	_on_model_changed()
	_hud.set_status("Grid is now %dx%dx%d." % [grid_size.x, grid_size.y, grid_size.z])


## The venue is arena data, not a global setting: two arenas can want different
## surroundings and the file remembers which.
func _on_venue_changed(theme_id: StringName) -> void:
	model.arena.theme_id = theme_id
	_hud.set_status("Venue: %s" % ArenaTheme.find(theme_id).display_name)


func _on_delete_requested(path: String) -> void:
	var was_current: bool = path == ArenaSession.current_path
	if ArenaSession.delete_arena(path) != OK:
		_hud.set_status("Could not delete %s" % path.get_file())
		return
	_hud.set_status("Deleted %s%s" % [
		path.get_file(), "  (still open here, unsaved)" if was_current else ""])
	_hud.open_load_panel(ArenaSession.list_arenas())


func _on_new() -> void:
	model.arena = ArenaSession.new_arena()
	_hud.set_arena_name(model.arena.arena_name)
	_hud.set_grid_size(model.arena.grid_size)
	_camera.frame_grid(model.arena.grid_size, ArenaSession.catalog.cell_size)
	_on_model_changed()
	_hud.set_status("New arena.")


## Saving an unfinished arena is allowed - the player has to be able to stop for
## the night mid-build. Only Play insists on a valid one.
func _on_save() -> void:
	var error: Error = ArenaSession.save()
	if error == OK:
		_hud.set_status("Saved to %s" % ArenaSession.current_path.get_file())
	else:
		_hud.set_status("Could not save (%d)." % error)


func _on_load_requested(path: String) -> void:
	if path == "":
		_hud.open_load_panel(ArenaSession.list_arenas())
		return
	if not ArenaSession.load_arena(path):
		_hud.set_status("Could not open %s" % path.get_file())
		return
	model.arena = ArenaSession.arena
	_hud.set_arena_name(model.arena.arena_name)
	_hud.set_grid_size(model.arena.grid_size)
	_hud.set_theme_id(model.arena.theme_id)
	_frame_content()
	_on_model_changed()
	_hud.set_status("Opened %s" % path.get_file())


## Playtesting saves first: coming back from a match to unsaved work that a crash
## could have eaten is not a trade the player agreed to.
func _on_play() -> void:
	ArenaSession.save()
	if not ArenaSession.playtest():
		_hud.set_status("Fix the errors before playing.")


## Leaving saves what was built, but an untouched arena is not work: writing
## "new_arena.tres" every time someone opens the editor and backs out would fill
## the folder with files nobody made.
func _on_exit() -> void:
	if not model.arena.placements.is_empty() or ArenaSession.current_path != "":
		ArenaSession.save()
	GameManager.return_to_menu()


## Frames the placed pieces, falling back to the whole grid for an empty arena.
func _frame_content() -> void:
	var catalog: PieceCatalog = ArenaSession.catalog
	if model.arena.placements.is_empty():
		_camera.frame_grid(model.arena.grid_size, catalog.cell_size)
		return
	var lowest: Vector3i = model.arena.placements[0].cell
	var highest: Vector3i = lowest
	for entry: PlacementEntry in model.arena.placements:
		lowest = lowest.min(entry.cell)
		highest = highest.max(entry.cell)
	_camera.frame_bounds(catalog.cell_to_world(lowest), catalog.cell_to_world(highest))


func _focus_cell(cell: Vector3i) -> void:
	_set_level(cell.y)
	_camera.look_at_cell(ArenaSession.catalog.cell_to_world(cell))
