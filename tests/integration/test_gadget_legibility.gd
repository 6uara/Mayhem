extends GutTest
## Lo que el playtest no entendia de los gadgets: que es lo que levantaste, a
## donde va a caer, hasta donde llega y que le hizo a cada enemigo. Cada una de
## esas preguntas tiene su señal en pantalla, y aca se fija que llegue.

const DATA_DIR: String = "res://data/utilities"
const IDS: Array[StringName] = [&"stun_grenade", &"slow_field", &"temp_wall", &"medkit"]


func _data(id: StringName) -> UtilityData:
	return load("%s/%s.tres" % [DATA_DIR, id]) as UtilityData


func after_each() -> void:
	ObjectPool.release_all()


# --------------------------------------------------------------------- datos

func test_every_gadget_says_what_it_does() -> void:
	for id: StringName in IDS:
		var data: UtilityData = _data(id)
		assert_false(data.summary.is_empty(), "%s tiene descripcion" % id)
		assert_true(data.describe().begins_with(data.summary), "%s la usa" % id)


## Los numeros salen de los campos, no del texto: cambiar el balance no deja la
## descripcion mintiendo.
func test_the_description_carries_the_live_numbers() -> void:
	var stun: UtilityData = _data(&"stun_grenade")
	assert_string_contains(stun.describe(), String.num(stun.effect_duration, 1).trim_suffix(".0"))
	var medkit: UtilityData = _data(&"medkit")
	assert_string_contains(medkit.describe(), str(roundi(medkit.heal_amount)))


## Cada gadget en su color, y ninguno el de la ley: la granada era el cyan de lo
## usable y el campo lento el violeta del gancho.
func test_gadget_colours_are_their_own() -> void:
	var law: Array[Color] = [Tokens.WORLD_TRAVERSAL, Tokens.WORLD_HAZARD, Tokens.WORLD_PICKUP,
		Tokens.SPAWN, Tokens.WORLD_GRAPPLE]
	var seen: Array[Color] = []
	for id: StringName in IDS:
		var colour: Color = _data(id).accent_color
		assert_false(seen.has(colour), "%s repite color" % id)
		assert_false(law.has(colour), "%s usa un color de la ley" % id)
		seen.append(colour)
	assert_true(_data(&"stun_grenade").accent_color.is_equal_approx(Tokens.GADGET_STUN))
	assert_true(_data(&"slow_field").accent_color.is_equal_approx(Tokens.GADGET_SLOW))
	assert_true(_data(&"temp_wall").accent_color.is_equal_approx(Tokens.GADGET_BARRIER))
	assert_true(_data(&"medkit").accent_color.is_equal_approx(Tokens.GADGET_MEDKIT))


# ----------------------------------------------------------------------- HUD

func test_picking_one_up_says_what_it_is() -> void:
	var player: Player = add_child_autofree(load("res://scenes/player/player.tscn").instantiate())
	var hud: CanvasLayer = add_child_autofree(load("res://scenes/ui/hud.tscn").instantiate())
	await wait_physics_frames(3)
	player.utility.add_charge(&"stun_grenade")
	EventBus.crowd_drop_collected.emit(&"stun_grenade")
	var title: Label = hud.get_node("Root/AnnounceLayer/Title")
	var tag: Label = hud.get_node("Root/AnnounceLayer/TagPill/Tag")
	var detail: Label = hud.get_node("Root/AnnounceLayer/Detail")
	assert_eq(title.text, "STUN GRENADE", "el nombre, como titulo")
	assert_string_contains(tag.text, "GADGET")
	assert_true(detail.visible)
	assert_string_contains(detail.text, _data(&"stun_grenade").summary, "y lo que hace")


## Una descripcion larga no puede ensanchar el cartel: corrido hacia un costado
## es como se veia antes de que la descripcion bajara a su propia linea.
func test_a_long_description_wraps_instead_of_widening_the_banner() -> void:
	var hud: CanvasLayer = add_child_autofree(load("res://scenes/ui/hud.tscn").instantiate())
	await wait_process_frames(2)
	var layer: Control = hud.get_node("Root/AnnounceLayer")
	var width: float = layer.size.x
	hud.call(&"announce", "GADGET", "SLOW FIELD", Tokens.GADGET_SLOW,
		"Leaves a pool that slows enemies inside it to half speed - 6 s, and some more words to be long")
	await wait_process_frames(2)
	assert_almost_eq(layer.size.x, width, 1.0)

	hud.call(&"announce", "WAVE 2", "", Tokens.REWARD)
	assert_false((hud.get_node("Root/AnnounceLayer/Detail") as Label).visible,
		"el aviso de oleada no arrastra la descripcion del gadget")


# ------------------------------------------------------------------ apuntado

func test_the_aim_preview_lands_where_the_gadget_would() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = PhysicsLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
	var aim: Node3D = add_child_autofree(Node3D.new())
	aim.position = Vector3(0.0, 1.6, 0.0)
	var utility := UtilityComponent.new()
	utility.aim_node = aim
	utility.slots = [_data(&"stun_grenade"), null, null] as Array[UtilityData]
	add_child_autofree(utility)
	await wait_physics_frames(2)
	var arc: PackedVector3Array = utility.predict_arc(0)
	assert_gt(arc.size(), 2, "hay arco")
	var landing: Vector3 = arc[arc.size() - 1]
	assert_almost_eq(landing.y, 0.0, 0.05, "termina en el piso")
	assert_lt(landing.z, -1.0, "adelante, hacia donde se mira")


# ------------------------------------------------------------------ enemigos

func _enemy() -> Enemy:
	var enemy: Enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	add_child_autofree(enemy)
	await wait_physics_frames(1)
	enemy.setup(load("res://data/enemies/rusher.tres"), Vector3.ZERO)
	enemy.set_physics_process(false)
	await wait_physics_frames(1)
	return enemy


func test_a_stunned_enemy_shows_it_and_stops_showing_it() -> void:
	var enemy: Enemy = await _enemy()
	enemy.apply_stun(0.3)
	assert_true(enemy._status_marks.is_stunned(), "aturdido")
	assert_true(enemy._status_marks.get_node("StunSparks").visible, "con chispas")
	await wait_seconds(0.5)
	assert_false(enemy._status_marks.get_node("StunSparks").visible, "y se le pasa")


func test_a_slowed_enemy_wears_the_slow_colour() -> void:
	var enemy: Enemy = await _enemy()
	var outline := enemy._model_meshes[0].material_overlay as ShaderMaterial
	enemy.apply_slow(0.45)
	assert_eq(outline.get_shader_parameter(&"outline_color"), Tokens.GADGET_SLOW)
	enemy.clear_slow()
	assert_eq(outline.get_shader_parameter(&"outline_color"), enemy.data.body_color,
		"al salir vuelve a su color")


## Un cuerpo del pool no hereda las chispas del enemigo anterior.
func test_pooled_enemies_start_clean() -> void:
	var enemy: Enemy = await _enemy()
	enemy.apply_stun(5.0)
	enemy.setup(load("res://data/enemies/ranger.tres"), Vector3.ZERO)
	assert_false(enemy._status_marks.is_stunned())
	assert_false(enemy._status_marks.get_node("StunSparks").visible)


# --------------------------------------------------------------- duraciones

func test_lasting_effects_blink_before_they_end() -> void:
	assert_true(ThrownUtility.ending_blink_visible(Tokens.GADGET_ENDING_BLINK + 1.0),
		"lejos del final, quieto")
	var states: Dictionary = {}
	var time: float = Tokens.GADGET_ENDING_BLINK - 0.01
	while time > 0.0:
		states[ThrownUtility.ending_blink_visible(time)] = true
		time -= 0.05
	assert_eq(states.size(), 2, "cerca del final, prende y apaga")
