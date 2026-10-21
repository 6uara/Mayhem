extends Node
## Saca una foto de la tienda en su estado mas cargado: regla para elegir,
## contrato, rara, arma y mejoras ya compradas. Para mirar el layout sin jugar
## hasta la oleada cinco. Saca las dos paginas: `ruta.png` y `ruta_next.png`.
##
##   godot --path . --resolution 1920x1080 tools/capture_shop.tscn -- ruta.png
##
## Con render de verdad, no --headless (ver capture_menu.gd).

const SHOP: String = "res://scenes/ui/shop_screen.tscn"


func _ready() -> void:
	var target: String = "user://shop.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = args[0]

	WaveManager.current_index = 4
	EconomyManager.currency = 1240
	for id: String in ["move_speed", "move_speed", "max_health", "grapple_range", "nanoweave"]:
		UpgradeManager.add_upgrade(load("res://data/upgrades/%s.tres" % id))
	BroadcastRules.enabled = true
	BroadcastRules.pool.contract_chance = 1.0
	BroadcastRules.prepare_offer(4, null)

	var screen: Node = (load(SHOP) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	# Forzar una rara en la oferta: es el caso que agrega la quinta carta.
	screen.shop.catalog.rare_offer_chance = 1.0
	screen.shop.catalog.weapon_offer_chance = 1.0
	screen.open({"kills": 312, "completion_bonus": 150, "speed_bonus": 90,
		"no_damage_bonus": 0, "contract_bonus": 120, "show_bonus": 45, "damage_loss": 60}, 4, 71.4)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw

	_save(target)
	# El segundo paso: regla y contrato.
	screen.show_page(1)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_save(target.get_basename() + "_next.png")
	get_tree().quit()


func _save(path: String) -> void:
	var shot: Image = get_viewport().get_texture().get_image()
	var error: int = shot.save_png(path)
	print("captura: %s  %dx%d  error=%d" % [
		ProjectSettings.globalize_path(path), shot.get_width(), shot.get_height(), error])
