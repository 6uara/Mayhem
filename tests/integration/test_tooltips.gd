extends GutTest
## Every button a player can reach says what it does, unless its label already
## does. The failure this guards against is quiet: a new button lands without a
## tooltip, looks fine, and the player is left to guess what "Skip" skips.

## Labels that need no explanation. A button whose text is not here and has no
## tooltip fails - add the tooltip, or add the label here if it truly is obvious.
const SELF_EXPLANATORY: Array[String] = [
	"Back", "Quit", "Resume", "Options", "Credits", "Main Menu", "Play",
]

const SCENES: Array[String] = [
	"res://scenes/main/main_menu.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/settings_screen.tscn",
	"res://scenes/ui/feedback_panel.tscn",
	"res://scenes/ui/score_entry_panel.tscn",
	"res://scenes/ui/arena_select.tscn",
	"res://scenes/ui/match_overlay.tscn",
	"res://scenes/ui/shop_screen.tscn",
	"res://scenes/ui/leaderboard_panel.tscn",
	"res://scenes/ui/credits_panel.tscn",
]

const SettingsGuard = preload("res://tests/settings_guard.gd")

var _guard: SettingsGuard = SettingsGuard.new()


func before_each() -> void:
	_guard.take()


func after_each() -> void:
	_guard.restore()


func _buttons(node: Node, out: Array[BaseButton]) -> void:
	var button := node as BaseButton
	if button != null:
		out.append(button)
	for child: Node in node.get_children():
		_buttons(child, out)


func test_every_menu_button_explains_itself() -> void:
	for path: String in SCENES:
		var scene: Node = add_child_autofree((load(path) as PackedScene).instantiate())
		await wait_physics_frames(1)
		var found: Array[BaseButton] = []
		_buttons(scene, found)
		for base: BaseButton in found:
			# Toggles, pickers and dropdowns in a settings row are explained by
			# the row's label; only plain buttons with a caption are checked here.
			var button := base as Button
			if button == null or button is CheckButton or button is OptionButton \
					or button is ColorPickerButton:
				continue
			var caption: String = button.text.strip_edges()
			if caption == "" or SELF_EXPLANATORY.has(caption):
				continue
			assert_ne(button.tooltip_text.strip_edges(), "",
				"%s: '%s' (%s) has no tooltip" % [path.get_file(), caption, button.name])
		scene.queue_free()
		await wait_physics_frames(1)


## A tooltip keyed to a setting that no longer exists would never show, and
## nothing else would notice.
func test_every_settings_tooltip_names_a_real_setting() -> void:
	for key: String in SettingsScreen.TOOLTIPS:
		assert_true(SettingsManager.DEFAULTS.has(key), "'%s' is not a setting" % key)


## Quitting from the pause menu throws the run away; that has to be said before
## the click, not discovered after it.
func test_quitting_mid_run_warns_that_the_run_is_lost() -> void:
	var menu: Node = add_child_autofree(
		(load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate())
	var quit: Button = menu.get_node("Root/Panel/Margin/Layout/MenuButton")
	assert_string_contains(quit.tooltip_text, "won't be recorded")


func test_the_theme_styles_tooltips() -> void:
	var theme: Theme = load("res://ui/mayhem_theme.tres")
	assert_true(theme.has_stylebox(&"panel", &"TooltipPanel"),
		"the engine's grey default would show up in the middle of this UI")
	assert_true(theme.has_color(&"font_color", &"TooltipLabel"))
