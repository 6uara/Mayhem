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
	_screen._apply_tool(Vector3i(3, 0, 3))
	assert_eq(ArenaSession.arena.placements.size(), 1)


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
