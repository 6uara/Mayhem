class_name ShareCard
extends PanelContainer
## La run en una imagen para compartir: resultado, puntaje, los tres mejores
## momentos (RunHighlights), los trofeos y el codigo que la vuelve a jugar.
##
## La linea de texto que copia la pantalla de fin sirve para un chat; una imagen
## es lo que se pega en un post, en la pagina de itch o en el trailer. 1200x630
## es el tamaño de vista previa que usan casi todas las redes, asi que la
## tarjeta entra entera sin recorte.
##
## Se arma con `build(info)` y se dibuja a PNG con `save_png()`, en un
## SubViewport propio: la tarjeta no depende de la resolucion de la pantalla ni
## de lo que haya encima.

const CARD_SIZE: Vector2i = Vector2i(1200, 630)
const SHARE_DIR: String = "user://share"
const PADDING: int = 48

## `info`: `victory`, `score`, `reached` (texto: "ALL 10 WAVES" / "DIED ON WAVE
## 7"), `context` (arena, modo y tiempo en una linea), `code`, `highlights`
## (Array[Dictionary] de RunHighlights) y `trophies` (Array[String], etiquetas).
func build(info: Dictionary) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	custom_minimum_size = Vector2(CARD_SIZE)
	size = Vector2(CARD_SIZE)
	var victory: bool = bool(info.get("victory", false))
	var accent: Color = Tokens.REWARD if victory else Tokens.ENEMY
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.VOID
	style.border_color = accent
	style.border_width_left = 8
	style.set_content_margin_all(PADDING)
	add_theme_stylebox_override(&"panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP)
	add_child(column)

	var top := HBoxContainer.new()
	column.add_child(top)
	var brand := _label("MAYHEM", Tokens.SIZE_DISPLAY_SM, Tokens.MUTED)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	top.add_child(_label(String(info.get("context", "")).to_upper(), Tokens.SIZE_LABEL,
		Tokens.MUTED))

	var result := _label(String(info.get("reached", "")).to_upper(), Tokens.SIZE_ANNOUNCE,
		accent)
	result.name = "Result"
	column.add_child(result)
	var score := _label("%d PTS" % int(info.get("score", 0)), Tokens.SIZE_NUM_PRIMARY,
		Tokens.TEXT)
	score.name = "Score"
	column.add_child(score)

	var moments := HBoxContainer.new()
	moments.name = "Moments"
	moments.add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP)
	moments.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(moments)
	for highlight: Dictionary in info.get("highlights", []):
		moments.add_child(moment_box(highlight, true))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", Tokens.CLUSTER_GAP)
	column.add_child(bottom)
	var trophies: Array = info.get("trophies", [])
	var trophy_text: String = "  ".join(PackedStringArray(trophies))
	var trophy_label := _label(trophy_text, Tokens.SIZE_LABEL, Tokens.REWARD)
	trophy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(trophy_label)
	var code := _label("PLAY THIS RUN  %s" % String(info.get("code", "")), Tokens.SIZE_LABEL,
		Tokens.PLAYER)
	code.name = "Code"
	bottom.add_child(code)


## Una caja por momento: el titulo chico, el numero grande, el detalle abajo.
## Publica: la pantalla de fin usa la misma, chica; la tarjeta, `large`, porque
## en una vista previa de red social el numero es lo unico que se lee.
static func moment_box(highlight: Dictionary, large: bool = false) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Tokens.RAISED
	style.border_color = Tokens.PLAYER
	style.border_width_top = 3
	style.set_content_margin_all(Tokens.CLUSTER_GAP)
	panel.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 2)
	panel.add_child(box)
	box.add_child(_label(String(highlight.get("title", "")), Tokens.SIZE_LABEL, Tokens.PLAYER))
	box.add_child(_label(String(highlight.get("value", "")),
		Tokens.SIZE_NUM_PRIMARY if large else Tokens.SIZE_NUM_SECOND, Tokens.TEXT))
	var detail := _label(String(highlight.get("detail", "")), Tokens.SIZE_LABEL, Tokens.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	return panel


## Dibuja la tarjeta a un PNG en `user://share/` y devuelve la ruta, o "" si no
## se pudo. Asincrona: espera a que el SubViewport dibuje. `host` es cualquier
## nodo en el arbol, donde se cuelga el viewport mientras dura.
static func save_png(host: Node, info: Dictionary, file_stem: String) -> String:
	var viewport := SubViewport.new()
	viewport.size = CARD_SIZE
	viewport.transparent_bg = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card := ShareCard.new()
	viewport.add_child(card)
	host.add_child(viewport)
	card.build(info)
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHARE_DIR))
	var path: String = "%s/%s.png" % [SHARE_DIR, file_stem]
	if image.save_png(path) != OK:
		return ""
	return path


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label
