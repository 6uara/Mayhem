extends GutTest
## The in-game editor screen, instantiated for real.
##
## Exists because a signal named like one of Control's own took the whole screen
## down to a blue void and nothing caught it: every other test drives the model
## directly, and the model was fine.

const EDITOR_SCENE: String = "res://scenes/main/arena_editor.tscn"

var _screen: ArenaEditorScreen


func before_each() -> void:
	ArenaSession.new_arena()
	var scene := load(EDITOR_SCENE) as PackedScene
	_screen = scene.instantiate() as ArenaEditorScreen
	add_child_autofree(_screen)


func test_the_editor_scene_comes_up_with_its_parts() -> void:
	assert_not_null(_screen, "the root script has to compile for this to be non-null")
	assert_not_null(_screen.get_node_or_null("UI/HUD") as ArenaEditorHUD)
	assert_not_null(_screen.get_node_or_null("Camera") as ArenaEditorCamera)
	assert_not_null(_screen.model, "and it holds a model to edit")


func test_it_starts_on_a_piece_so_the_first_click_builds() -> void:
	assert_ne(_screen.selected_piece, &"")
	assert_eq(_screen.tool_mode, ArenaPalettePanel.Tool.PLACE)


func test_a_click_through_the_tool_places_a_piece() -> void:
	# La arena nueva ya viene con el piso puesto, asi que primero hay que hacer
	# lugar: lo que se prueba aca es que el click llega al modelo.
	_screen.model.erase_at(Vector3i(3, 0, 3))
	var before: int = ArenaSession.arena.placements.size()
	_screen._select_piece(&"floor_1x1")
	_screen._apply_tool(Vector3i(3, 0, 3))
	assert_eq(ArenaSession.arena.placements.size(), before + 1)


func test_the_editor_opens_with_a_floor_to_build_on() -> void:
	assert_true(_screen.model.has_flat_ground(Vector3i(0, 0, 0)))
	assert_true(_screen.model.has_flat_ground(Vector3i(31, 0, 31)),
		"el piso llega hasta la esquina opuesta")


func test_the_editor_does_not_open_with_the_keyboard_trapped() -> void:
	var hud: ArenaEditorHUD = _screen.get_node("UI/HUD")
	assert_false(hud.is_typing(), "nada tiene el foco hasta que alguien lo pida")
	assert_false(hud.is_modal_open())


func test_naming_happens_in_a_panel_that_closes() -> void:
	var hud: ArenaEditorHUD = _screen.get_node("UI/HUD")
	hud.open_save_panel()
	assert_true(hud.is_modal_open(), "el panel se lleva los clicks mientras esta abierto")
	assert_true(hud.is_typing(), "y el teclado, porque hay algo que escribir")
	assert_true(_screen._on_escape(), "ESC lo cierra")
	assert_false(hud.is_modal_open())
	assert_false(hud.is_typing(), "y devuelve el teclado al mapa")


func test_a_drag_erases_every_cell_it_crosses_as_one_edit() -> void:
	_screen._set_tool(int(ArenaPalettePanel.Tool.ERASE))
	var before: int = ArenaSession.arena.placements.size()
	_screen._begin_stroke()
	for x: int in 6:
		_screen._paint(Vector3i(x * 3, 0, 0))
	_screen._end_stroke()
	assert_lt(ArenaSession.arena.placements.size(), before, "el arrastre borro varias")
	assert_true(_screen.model.undo())
	assert_eq(ArenaSession.arena.placements.size(), before,
		"y Z devuelve el trazo entero, no la ultima celda")


func test_passing_twice_over_a_cell_in_one_drag_only_acts_once() -> void:
	_screen._select_piece(&"floor_1x1")
	_screen.model.erase_at(Vector3i(3, 0, 3))
	var before: int = ArenaSession.arena.placements.size()
	_screen._begin_stroke()
	_screen._paint(Vector3i(3, 0, 3))
	_screen._paint(Vector3i(3, 0, 3))
	_screen._end_stroke()
	assert_eq(ArenaSession.arena.placements.size(), before + 1)


func test_moving_a_piece_takes_two_clicks_and_esc_puts_it_back() -> void:
	_screen.model.erase_at(Vector3i(3, 0, 3))
	_screen._set_tool(int(ArenaPalettePanel.Tool.MOVE))
	_screen._apply_tool(Vector3i(0, 0, 0))
	assert_true(_screen._has_move_origin, "el primer click la levanta")
	assert_true(_screen._on_escape(), "ESC la devuelve donde estaba")
	assert_false(_screen._has_move_origin)
	assert_true(_screen.model.has_flat_ground(Vector3i(0, 0, 0)), "nunca se fue")


func test_the_venue_picker_writes_the_arena() -> void:
	_screen._on_venue_changed(&"default")
	assert_eq(ArenaSession.arena.theme_id, &"default")


func test_the_play_screen_lists_what_can_be_played() -> void:
	var scene := load("res://scenes/ui/arena_select.tscn") as PackedScene
	var select := scene.instantiate() as ArenaSelect
	add_child_autofree(select)
	select.open()
	var rows: Node = select.get_node("Panel/Margin/Layout/Scroll/Rows")
	assert_eq(rows.get_child_count(), ArenaSession.list_playable().size())
	assert_true(select.visible)
	select.close()
	assert_false(select.visible)
