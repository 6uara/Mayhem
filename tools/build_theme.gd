extends SceneTree
## Builds res://ui/mayhem_theme.tres from the design tokens and saves it.
##
## The theme is generated rather than hand-authored so it can never drift from
## theme_tokens.gd - every size and colour below is read from Tokens, and re-running
## this after a token change is the whole update process.
##
##     godot --headless --path . -s tools/build_theme.gd
##
## Type variations map the handoff's type roles onto Label/Button, so a cluster just
## sets theme_type_variation = &"NumPrimary" instead of overriding fonts by hand.

const OUTPUT_PATH: String = "res://ui/mayhem_theme.tres"


func _initialize() -> void:
	var theme := Theme.new()
	var sans: Font = load(Tokens.FONT_UI)
	var sans_semi: Font = load(Tokens.FONT_UI_SEMI)
	var mono: Font = load(Tokens.FONT_MONO)
	var display: Font = _archivo(125.0, 800.0)
	var display_small: Font = _archivo(118.0, 700.0)

	theme.default_font = sans
	theme.default_font_size = Tokens.SIZE_LABEL

	# --- type roles -------------------------------------------------------------
	_label_variation(theme, &"Announce", display, Tokens.SIZE_ANNOUNCE, Tokens.TEXT)
	_label_variation(theme, &"DisplaySmall", display_small, Tokens.SIZE_DISPLAY_SM, Tokens.REWARD)
	_label_variation(theme, &"NumPrimary", mono, Tokens.SIZE_NUM_PRIMARY, Tokens.TEXT)
	_label_variation(theme, &"NumCluster", mono, Tokens.SIZE_NUM_CLUSTER, Tokens.TEXT)
	_label_variation(theme, &"NumSecond", mono, Tokens.SIZE_NUM_SECOND, Tokens.MUTED)
	_label_variation(theme, &"Subtitle", sans, Tokens.SIZE_SUBTITLE, Tokens.TEXT)
	# Labels are always MUTED - they name a value, they are never the value.
	_label_variation(theme, &"HUDLabel", sans_semi, Tokens.SIZE_LABEL, Tokens.MUTED)
	_label_variation(theme, &"Keybind", mono, Tokens.SIZE_KEYBIND, Tokens.MUTED)

	# --- base Label -------------------------------------------------------------
	theme.set_font("font", "Label", sans)
	theme.set_font_size("font_size", "Label", Tokens.SIZE_LABEL)
	theme.set_color("font_color", "Label", Tokens.TEXT)

	# --- panels -----------------------------------------------------------------
	theme.set_stylebox("panel", "PanelContainer", _panel())
	theme.set_type_variation(&"HUDPanel", &"PanelContainer")
	theme.set_stylebox("panel", "HUDPanel", _panel())
	theme.set_type_variation(&"SubtitlePanel", &"PanelContainer")
	theme.set_stylebox("panel", "SubtitlePanel", _subtitle_panel())
	theme.set_type_variation(&"AbilitySlot", &"PanelContainer")
	theme.set_stylebox("panel", "AbilitySlot", _slot(false))
	theme.set_type_variation(&"AbilitySlotReady", &"PanelContainer")
	theme.set_stylebox("panel", "AbilitySlotReady", _slot(true))

	# --- buttons ----------------------------------------------------------------
	_buttons(theme, sans_semi)

	var error: int = ResourceSaver.save(theme, OUTPUT_PATH)
	if error != OK:
		push_error("build_theme: save failed (%d)" % error)
		quit(1)
		return
	print("Built %s" % OUTPUT_PATH)
	quit()


## Archivo is variable; the broadcast look is its width axis pushed to 125.
func _archivo(width: float, weight: float) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = load(Tokens.FONT_DISPLAY)
	var server: TextServer = TextServerManager.get_primary_interface()
	variation.variation_opentype = {
		server.name_to_tag("width"): width,
		server.name_to_tag("weight"): weight,
	}
	return variation


func _label_variation(theme: Theme, name: StringName, font: Font, font_size: int,
		tint: Color) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, font_size)
	theme.set_color("font_color", name, tint)
	# Every panel sits over gameplay, so text carries its own shadow for contrast.
	theme.set_color("font_shadow_color", name, Color(Tokens.VOID, 0.55))
	theme.set_constant("shadow_offset_x", name, 0)
	theme.set_constant("shadow_offset_y", name, 1)


func _panel() -> ChamferStyleBox:
	var box := ChamferStyleBox.new()
	box.fill_color = Tokens.BASE
	box.fill_alpha = Tokens.PANEL_ALPHA
	box.border_color = Tokens.LINE
	box.border_width = 1.0
	box.chamfer = Tokens.CHAMFER
	box.content_margin_left = Tokens.PANEL_PADDING
	box.content_margin_right = Tokens.PANEL_PADDING
	box.content_margin_top = Tokens.ROW_GAP
	box.content_margin_bottom = Tokens.ROW_GAP
	return box


func _subtitle_panel() -> ChamferStyleBox:
	var box := ChamferStyleBox.new()
	box.fill_color = Tokens.VOID
	box.fill_alpha = Tokens.SUBTITLE_ALPHA
	box.border_width = 0.0
	box.chamfer = 0.0
	# The amber rail is the Host's signature; tier 2 recolours it to HAZARD.
	box.rail_width = 3.0
	box.rail_color = Tokens.REWARD
	box.rail_side = SIDE_LEFT
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box


func _slot(is_ready: bool) -> ChamferStyleBox:
	var box := ChamferStyleBox.new()
	box.fill_color = Tokens.BASE
	box.fill_alpha = Tokens.PANEL_ALPHA
	box.border_color = Tokens.PLAYER if is_ready else Tokens.LINE
	box.border_width = 1.0
	box.chamfer = Tokens.CHAMFER
	return box


func _buttons(theme: Theme, font: Font) -> void:
	theme.set_font("font", "Button", font)
	theme.set_font_size("font_size", "Button", 16)
	theme.set_color("font_color", "Button", Tokens.TEXT)
	theme.set_color("font_hover_color", "Button", Tokens.PLAYER)
	theme.set_color("font_disabled_color", "Button", Tokens.DIM)

	var normal := ChamferStyleBox.new()
	normal.fill_color = Tokens.RAISED
	normal.fill_alpha = 1.0
	normal.border_color = Tokens.LINE
	normal.border_width = 2.0
	normal.chamfer = Tokens.CHAMFER
	for margin: String in ["left", "right"]:
		normal.set("content_margin_" + margin, 24)
	for margin: String in ["top", "bottom"]:
		normal.set("content_margin_" + margin, 12)

	var hover: ChamferStyleBox = normal.duplicate()
	hover.border_color = Tokens.PLAYER

	# Focus is a ring, never a fill - identical in menus and the shop.
	var focus: ChamferStyleBox = normal.duplicate()
	focus.fill_alpha = 0.0
	focus.border_color = Tokens.PLAYER
	focus.border_width = Tokens.FOCUS_RING_WIDTH

	var disabled: ChamferStyleBox = normal.duplicate()
	disabled.border_color = Tokens.LINE
	disabled.fill_alpha = 0.4

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", hover)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("disabled", "Button", disabled)
