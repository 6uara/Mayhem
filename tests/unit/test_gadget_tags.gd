extends GutTest
## Cada gadget lleva una palabra corta al lado de su tecla en la barra del HUD.
## Si un .tres nuevo llega sin ella, la ranura vuelve a ser una tecla con un
## icono y nadie sabe qué tira cada una.

const HudScript := preload("res://scripts/ui/hud.gd")
const UTILITIES_DIR := "res://data/utilities/"
## Lo que entra debajo de una ranura de `Tokens.SLOT_SIZE` junto a la tecla.
const MAX_TAG_LENGTH := 5


func test_every_gadget_has_a_short_tag() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(UTILITIES_DIR)
	var checked: int = 0
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var data := load(UTILITIES_DIR + file) as UtilityData
		assert_not_null(data, file)
		if data == null:
			continue
		assert_false(data.tag.is_empty(), "%s has no tag" % file)
		assert_lte(data.tag.length(), MAX_TAG_LENGTH, "%s tag is too long" % file)
		checked += 1
	assert_gt(checked, 0, "no gadgets found")


func test_the_slot_reads_the_key_and_the_tag() -> void:
	var data := UtilityData.new()
	data.tag = "stun"
	assert_eq(HudScript._utility_keybind_text("Q", data), "Q · STUN")


func test_a_slot_without_tag_keeps_the_key_alone() -> void:
	assert_eq(HudScript._utility_keybind_text("X", UtilityData.new()), "X")
	assert_eq(HudScript._utility_keybind_text("C", null), "C")
