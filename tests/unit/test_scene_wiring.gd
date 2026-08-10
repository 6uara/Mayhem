extends GutTest
## Guards the hand-authored .tscn wiring: exported node references resolve, and the
## dummy's hitboxes reach a HealthComponent. These break silently in the editor.
##
## Node-path exports resolve when the node enters the tree, not at instantiate(),
## so every scene under test has to be added to the tree first.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const DUMMY_SCENE: String = "res://scenes/enemies/target_dummy.tscn"


func _instance(path: String) -> Node:
	return add_child_autofree(load(path).instantiate())


func test_player_exports_resolve() -> void:
	var player: Player = _instance(PLAYER_SCENE)
	assert_not_null(player.head, "head")
	assert_not_null(player.camera, "camera")
	assert_not_null(player.weapon, "weapon")
	assert_not_null(player.recoil, "recoil")
	assert_not_null(player.health, "health")
	assert_not_null(player.stats, "stats")


func test_weapon_exports_resolve() -> void:
	var player: Player = _instance(PLAYER_SCENE)
	var weapon: WeaponComponent = player.weapon
	assert_not_null(weapon.data, "data")
	assert_not_null(weapon.aim_node, "aim_node")
	assert_not_null(weapon.muzzle, "muzzle")
	assert_not_null(weapon.recoil, "recoil")
	assert_not_null(weapon.stats, "stats")
	assert_not_null(weapon.body, "body")


func test_recoil_component_has_camera_rig() -> void:
	var player: Player = _instance(PLAYER_SCENE)
	assert_not_null(player.recoil.camera_rig, "camera_rig")


func test_dummy_hitboxes_reach_health() -> void:
	var dummy: Node = _instance(DUMMY_SCENE)
	for name: String in ["BodyHitbox", "HeadHitbox"]:
		var hitbox: HitboxComponent = dummy.get_node(name)
		assert_not_null(hitbox.health_component, "%s health_component" % name)


func test_rifle_data_is_complete() -> void:
	var rifle: WeaponData = load("res://data/weapons/rifle_ak.tres")
	assert_not_null(rifle.projectile_scene, "projectile_scene")
	assert_not_null(rifle.recoil_pattern, "recoil_pattern")
	assert_gt(rifle.recoil_pattern.points.size(), 0, "pattern has points")


func test_weapon_audio_hooks_are_wired() -> void:
	var player: Player = _instance(PLAYER_SCENE)
	var weapon: WeaponComponent = player.weapon
	assert_not_null(weapon.fire_sound, "fire_sound")
	assert_not_null(weapon.reload_sound, "reload_sound")
	assert_not_null(weapon.empty_sound, "empty_sound")


## Every weapon owns its own voice.
##
## Four guns sharing one sample are, to the ear, one gun with four fire rates - and
## section 6 puts roughly half of gunplay feel in the audio. This is the kind of
## regression that reintroduces itself quietly when a new weapon is copy-pasted from
## an old one, and nothing else in the build would notice.
func test_no_two_weapons_share_a_voice() -> void:
	var player: Player = _instance(PLAYER_SCENE)
	for slot: StringName in [&"fire_sound", &"reload_sound", &"empty_sound"]:
		var seen: Array[AudioStream] = []
		for weapon: WeaponComponent in player.weapon_holder.get_all():
			var stream: AudioStream = weapon.get(slot)
			assert_not_null(stream, "%s %s" % [weapon.name, slot])
			assert_false(seen.has(stream),
				"%s reuses another weapon's %s" % [weapon.name, slot])
			seen.push_back(stream)


func test_impact_audio_hooks_are_wired() -> void:
	var impact: ImpactEffect = _instance("res://scenes/vfx/impact_effect.tscn")
	assert_not_null(impact.fallback_material, "fallback_material")
	assert_not_null(impact.fallback_material.impact_sound, "fallback_material.impact_sound")


func test_reticle_audio_hooks_are_wired() -> void:
	# Crosshair and hitmarker are one Reticle now: the ADS sights are drawn by the
	# same system, so they inherit its outline, colours and hit states.
	var hud: CanvasLayer = _instance("res://scenes/ui/hud.tscn")
	var reticle: Reticle = hud.get_node("Root/Reticle")
	assert_not_null(reticle.body_sound, "body_sound")
	assert_not_null(reticle.headshot_sound, "headshot_sound")
	assert_not_null(reticle.kill_sound, "kill_sound")
