extends GutTest
## Nothing on the HUD may sit on top of anything else.
##
## Overlap is not a cosmetic complaint: two readouts sharing pixels means one of them
## is unreadable exactly when the player needs it, and the handoff judges anything
## read mid-combat on legibility first.

## The design resolution, but the test runner's viewport is not it - clusters anchor
## to whatever they are actually given, so measurements come from the live viewport.
const DESIGN_SCREEN := Vector2(1920, 1080)

## The clusters that actually draw content, by the name the HUD scene gives them.
const CLUSTERS: Array[String] = [
	"WaveCluster", "TimerCluster", "CurrencyCluster",
	"VitalsCluster", "AbilityBar", "WeaponCluster",
	"SubtitleBox", "AnnounceLayer",
]

var _hud: CanvasLayer
var _player: Player


func before_each() -> void:
	_player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	_hud = add_child_autofree(load("res://scenes/ui/hud.tscn").instantiate())
	# Everything visible at once is the worst case, and the worst case is the one
	# that has to hold.
	_hud.get_node("Root/SubtitleBox").visible = true
	_hud.get_node("Root/AnnounceLayer").visible = true
	await wait_physics_frames(4)


func _rect(name: String) -> Rect2:
	var control: Control = _hud.get_node("Root/%s" % name)
	return Rect2(control.global_position, control.size)


func test_no_two_clusters_overlap() -> void:
	for i: int in CLUSTERS.size():
		for j: int in range(i + 1, CLUSTERS.size()):
			var a: Rect2 = _rect(CLUSTERS[i])
			var b: Rect2 = _rect(CLUSTERS[j])
			assert_false(a.intersects(b),
				"%s %s overlaps %s %s" % [CLUSTERS[i], a, CLUSTERS[j], b])


func _screen() -> Rect2:
	return get_tree().root.get_visible_rect()


func test_every_cluster_stays_on_screen() -> void:
	var screen: Rect2 = _screen()
	for name: String in CLUSTERS:
		var rect: Rect2 = _rect(name)
		assert_true(screen.encloses(rect), "%s %s runs off screen" % [name, rect])


## Rule 3 of the five: the centre belongs to the crosshair and the action.
func test_nothing_enters_the_no_ui_zone() -> void:
	var screen: Rect2 = _screen()
	var forbidden := Rect2(screen.position + (screen.size - Tokens.NO_UI_ZONE) * 0.5,
		Tokens.NO_UI_ZONE)
	for name: String in CLUSTERS:
		assert_false(_rect(name).intersects(forbidden),
			"%s enters the no-UI zone" % name)


func test_the_broadcast_bug_does_not_sit_on_the_wave_cluster() -> void:
	# The bug spans the full width by design; only its tag row draws content.
	var tag: Control = _hud.get_node("Root/BroadcastBug").get_child(0)
	var tag_rect := Rect2(tag.global_position, tag.size)
	for name: String in ["WaveCluster", "TimerCluster", "CurrencyCluster"]:
		assert_false(tag_rect.intersects(_rect(name)),
			"the LIVE tag overlaps %s" % name)
