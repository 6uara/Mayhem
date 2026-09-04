@tool
extends EditorPlugin
## Wires the two MAYHEM tools into the editor: the Arena Editor dock plus its 3D
## viewport interaction, and the Balance Editor bottom panel.

const ArenaEditorDockScript := preload("res://addons/mayhem_tools/arena_editor/ui/editor_dock.gd")
const BalanceDockScript := preload("res://addons/mayhem_tools/balance_editor/ui/balance_dock.gd")
const ArenaPreviewScript := preload("res://addons/mayhem_tools/arena_editor/ui/arena_preview.gd")

## The game scene loads arenas by itself now, so Play just runs the game with
## the arena path in project settings for `ArenaHost` to pick up.
const PLAYTEST_SCENE: String = "res://scenes/main/game.tscn"
const PLAYTEST_ARENA_PATH: String = "res://data/arenas/_playtest.tres"
const PREVIEW_NODE_NAME: String = "__ArenaEditorPreview"

var _dock: ArenaEditorDock
var _balance_dock: Control
var _preview: ArenaPreview
var _hover_cell: Vector3i = Vector3i.ZERO


func _enter_tree() -> void:
	_dock = ArenaEditorDockScript.new()
	_dock.arena_changed.connect(_refresh_preview)
	_dock.focus_requested.connect(_on_focus_requested)
	_dock.play_requested.connect(_on_play_requested)
	_dock.build_mode_changed.connect(_on_build_mode_changed)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	_balance_dock = BalanceDockScript.new()
	add_control_to_bottom_panel(_balance_dock, "Balance")

	scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	_destroy_preview()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	if _balance_dock != null:
		remove_control_from_bottom_panel(_balance_dock)
		_balance_dock.queue_free()


func _handles(object: Object) -> bool:
	return object is Node3D


## Turns viewport input into grid edits: hover ghosts, left click applies the
## active tool, R rotates what comes next.
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	# With build mode off the plugin is a panel, not an input handler: whoever is
	# authoring a scene keeps their click, their R and a tree with nothing of
	# ours in it.
	if _dock == null or _dock.catalog == null or not _dock.is_build_mode():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	_ensure_preview()

	if event is InputEventMouseMotion:
		var cell: Vector3i = _cell_under_mouse(camera, (event as InputEventMouseMotion).position)
		if cell != _hover_cell:
			_hover_cell = cell
			_update_ghost()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_R:
		_dock.rotate_pending()
		_update_ghost()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dock.apply_tool_at(_cell_under_mouse(camera, button.position))
		# Consumed either way, press and release.
		#
		# Letting a refused placement fall through handed the click to the 3D
		# editor, which selected a mesh inside the preview - and from then on
		# every click dragged that selection's gizmo instead of building, which
		# reads exactly like the tool freezing. In build mode the viewport
		# belongs to the tool; a refusal is a message, not a fallthrough.
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


# Private

## The cell under the cursor on the working level's floor plane - the same plane
## the pieces of that level are built up from.
func _cell_under_mouse(camera: Camera3D, screen_position: Vector2) -> Vector3i:
	var cell_size: Vector3 = _dock.catalog.cell_size
	var level: int = _dock.get_level()
	var plane_y: float = float(level) * cell_size.y
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var plane := Plane(Vector3.UP, plane_y)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return _hover_cell
	var world: Vector3 = hit
	return Vector3i(
		int(round(world.x / cell_size.x)),
		level,
		int(round(world.z / cell_size.z)))


func _update_ghost() -> void:
	if _preview == null:
		return
	if _dock.get_tool() == ArenaPalettePanel.Tool.PLACE:
		_preview.show_ghost(_dock.get_selected_piece(), _hover_cell, _dock.pending_rotation,
			_dock.can_place_at(_hover_cell))
	else:
		_preview.hide_ghost()


func _on_build_mode_changed(enabled: bool) -> void:
	if enabled:
		_refresh_preview()
		return
	_destroy_preview()


func _refresh_preview() -> void:
	if _dock == null or not _dock.is_build_mode():
		return
	_ensure_preview()
	if _preview == null:
		return
	_preview.level = _dock.get_level()
	_preview.rebuild()


## The preview lives in the edited scene so it draws in the 3D viewport, but it
## is never owned by it: nothing the editor writes to disk knows it existed.
func _ensure_preview() -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null or not (root is Node3D):
		return
	if _preview != null and _preview.get_parent() == root:
		return
	_destroy_preview()
	_preview = ArenaPreviewScript.new()
	_preview.name = PREVIEW_NODE_NAME
	_preview.model = _dock.model
	_preview.level = _dock.get_level()
	root.add_child(_preview)
	_preview.rebuild()


func _destroy_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


func _on_scene_changed(_scene_root: Node) -> void:
	_destroy_preview()
	_refresh_preview()


## Focus is the editor's own: parking a marker at the cell and selecting it lets
## the designer press F, instead of the plugin fighting the viewport camera.
func _on_focus_requested(cell: Vector3i) -> void:
	_dock.set_build_mode(true)  # Going to a cell only means something with the preview up.
	_ensure_preview()
	if _preview == null:
		return
	var marker: Node3D = _preview.get_node_or_null("IssueMarker") as Node3D
	if marker == null:
		marker = Marker3D.new()
		marker.name = "IssueMarker"
		_preview.add_child(marker)
	marker.position = _dock.catalog.cell_to_world(cell)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(marker)


func _on_play_requested() -> void:
	if not _dock.save_arena(PLAYTEST_ARENA_PATH):
		return
	ProjectSettings.set_setting(ArenaHost.ARENA_PATH_SETTING, PLAYTEST_ARENA_PATH)
	ProjectSettings.save()
	EditorInterface.play_custom_scene(PLAYTEST_SCENE)
