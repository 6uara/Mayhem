extends Node
## Saca una foto del menu principal y la guarda. Para mirar el encuadre del
## fondo 3D sin abrir el juego a mano.
##
##   godot --path . --resolution 1600x900 tools/capture_menu.tscn -- ruta.png [codex=N]
##
## Con `codex=N` la foto es del codex abierto en la pestaña N (desde 0), encima
## del menu: para mirar una pestaña nueva sin navegar a mano.
##
## Con render de verdad, no --headless: en headless el servidor es un dummy y la
## captura sale vacia. Y como escena, no con `-s`, porque `-s` pide un MainLoop.
##
## El menu se agrega al root en vez de reemplazar la escena: `change_scene_to_file`
## libera a este nodo -que *es* la escena actual- y lo que sigue al await se
## queda sin arbol.

const MENU: String = "res://scenes/main/main_menu.tscn"


func _ready() -> void:
	var target: String = "user://menu.png"
	var codex_tab: int = -1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("codex="):
			codex_tab = argument.trim_prefix("codex=").to_int()
		else:
			target = argument

	# Diferido: en `_ready` el root todavia esta armando sus hijos.
	get_tree().root.add_child.call_deferred((load(MENU) as PackedScene).instantiate())
	if codex_tab >= 0:
		var codex := CodexPanel.new()
		get_tree().root.add_child.call_deferred(codex)
		await get_tree().process_frame
		codex.open()
		codex.show_section(codex_tab)
	# Tiempo para que la ciudad se siembre y la camara derive un poco.
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw

	var shot: Image = get_viewport().get_texture().get_image()
	var error: int = shot.save_png(target)
	print("captura: %s  %dx%d  error=%d" % [
		ProjectSettings.globalize_path(target), shot.get_width(), shot.get_height(), error])
	get_tree().quit()
