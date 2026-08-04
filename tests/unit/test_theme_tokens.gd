extends GutTest
## Guards the design handoff's contract: the token autoload is reachable, the fonts
## it names actually exist and load, and Archivo's variable axes are present.
##
## The whole broadcast look depends on Archivo at wdth 125 - if that axis is missing
## the game silently renders in the default width and looks like a different project.


func test_tokens_autoload_is_registered() -> void:
	assert_not_null(Tokens, "Tokens autoload")
	assert_eq(Tokens.PLAYER, Color("#35E0D4"), "PLAYER accent")
	assert_eq(Tokens.ENEMY, Color("#FF3B54"), "ENEMY accent")
	assert_eq(Tokens.REWARD, Color("#FFB020"), "REWARD accent")
	assert_eq(Tokens.HAZARD, Color("#C6FF3D"), "HAZARD accent")


func test_every_named_font_exists_and_loads() -> void:
	for path: String in [Tokens.FONT_DISPLAY, Tokens.FONT_UI,
			Tokens.FONT_UI_SEMI, Tokens.FONT_MONO]:
		assert_true(ResourceLoader.exists(path), "missing font: %s" % path)
		var font: Font = load(path)
		assert_not_null(font, "failed to load: %s" % path)


func test_archivo_exposes_the_width_and_weight_axes() -> void:
	var font: FontFile = load(Tokens.FONT_DISPLAY)
	assert_not_null(font, "Archivo loaded")
	var axes: Dictionary = font.get_supported_variation_list()
	# Axis tags are hashed ints; look them up by tag rather than guessing the order.
	var wdth: int = TextServerManager.get_primary_interface().name_to_tag("width")
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("weight")
	assert_true(axes.has(wdth), "Archivo must expose the width axis - the broadcast look needs wdth 125")
	assert_true(axes.has(wght), "Archivo must expose the weight axis")


func test_mono_is_tabular_enough_for_live_numbers() -> void:
	# Plex Mono is chosen so ammo/timer digits do not jitter as values change.
	var font: FontFile = load(Tokens.FONT_MONO)
	var sizes: Array[float] = []
	for digit: String in ["0", "1", "7", "8"]:
		sizes.push_back(font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Tokens.SIZE_NUM_PRIMARY).x)
	for width: float in sizes:
		assert_almost_eq(width, sizes[0], 0.5, "every digit must advance the same width")


func test_no_ui_zone_and_margins_match_the_spec() -> void:
	assert_eq(Tokens.NO_UI_ZONE, Vector2(900, 500), "the centre belongs to the crosshair")
	assert_eq(Tokens.SCREEN_MARGIN, 48)
	assert_eq(Tokens.SUBTITLE_Y, -210)


func test_every_accent_is_paired_with_a_shape() -> void:
	# Colour is never the only signal (CLAUDE.md 5 / brief rule 5).
	for key: String in ["player", "enemy", "reward", "hazard"]:
		assert_true(Tokens.SHAPE_FOR.has(key), "no shape paired with %s" % key)
