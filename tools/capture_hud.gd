extends Node
## Saca una foto de la HUD en combate, con todo lo que puede estar en pantalla a
## la vez encendido. Para mirar el encuadre, la distribucion y los choques sin
## tener que jugar hasta que se den solos.
##
##   godot --path . --resolution 1920x1080 tools/capture_hud.tscn -- ruta.png
##
## Con render de verdad, no --headless: en headless el servidor es un dummy y la
## captura sale vacia. Mismo motivo y misma forma que tools/capture_menu.gd.
##
## Lo que muestra es el **peor caso**, no un momento tipico: subtitulo del Host,
## aviso de oleada, feed de recargos, vida baja, municion baja y las tres
## ranuras de utilidad ocupadas, todo junto. Si el encuadre aguanta esto,
## aguanta cualquier partida.

const HUD: String = "res://scenes/ui/hud.tscn"
const PLAYER: String = "res://scenes/player/player.tscn"


func _ready() -> void:
	var target: String = "user://hud.png"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = args[0]

	var player: Node = (load(PLAYER) as PackedScene).instantiate()
	var hud: Node = (load(HUD) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(player)
	get_tree().root.add_child.call_deferred(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	_populate()
	# El feed de recargos y el aviso de oleada se desvanecen solos, asi que la
	# foto se saca dentro de su ventana de vida.
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw

	var shot: Image = get_viewport().get_texture().get_image()
	var error: int = shot.save_png(target)
	print("captura: %s  %dx%d  error=%d" % [
		ProjectSettings.globalize_path(target), shot.get_width(), shot.get_height(), error])
	get_tree().quit()


## Llena la HUD por señal, que es la unica forma en que recibe datos.
func _populate() -> void:
	var wave := WaveData.new()
	wave.par_time = 60.0
	EventBus.wave_started.emit(6, wave)
	EventBus.currency_changed.emit(1840)
	EventBus.ammo_changed.emit(7, 90)
	EventBus.player_damaged.emit(68.0, 32.0)
	EventBus.kill_payout.emit(20, [KillBonusTracker.BONUS_SPIN,
		KillBonusTracker.BONUS_AIRBORNE], 55, Vector3.ZERO)
	EventBus.kill_payout.emit(10, [KillBonusTracker.BONUS_HEADSHOT,
		KillBonusTracker.BONUS_DOUBLE], 25, Vector3.ZERO)
	EventBus.currency_lost.emit(24, &"damage")
	NarratorManager.subtitle_shown.emit(
		"Seis oleadas y todavia respira. El publico esperaba menos.", 3.0, 1)
	TutorialHintManager.hint_shown.emit("MANTENE [E] PARA EL GANCHO", 3.0)
