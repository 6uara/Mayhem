class_name SemanticOutline
extends RefCounted
## Pone el borde de "esto importa" (semantic_outline.gdshader) sobre un objeto del
## juego, en el color de lo que significa.
##
## Va como overlay de la malla y no como un nodo aparte: sigue a la malla en todo
## -se mueve, gira, se esconde- sin que nadie tenga que acordarse. Si la malla ya
## tiene un overlay (el brillo de un TelegraphComponent en modo overlay), el borde
## se encadena detras de el (`next_pass`) en vez de pisarlo.
##
## Cada objeto lo pide siempre, pero el borde solo se cuelga mientras `enabled`
## (el estilo Claridad, ver VisualStyle). Colgado con ancho 0 seguiria costando un
## draw call por malla, y la ola 10 esta limitada por la CPU.

const SHADER: Shader = preload("res://assets/shaders/semantic_outline.gdshader")
const META: StringName = &"semantic_outline"
const GROUP: StringName = &"semantic_outline"
## Un objeto puede pedir su borde y tenerlo apagado hasta que importe (la puerta
## de spawn: solo mientras salen enemigos). Ver `set_active()`.
const META_ACTIVE: StringName = &"semantic_outline_active"

## Si los bordes se cuelgan. Lo maneja VisualStyle con `set_enabled()`.
static var enabled: bool = false


## El borde de `geometry`, creado si no tenia. Llamarlo de nuevo con otro color
## solo cambia el color: es lo que pasa cuando un telegraph rearma sus materiales.
static func attach(geometry: GeometryInstance3D, color: Color) -> ShaderMaterial:
	if geometry == null:
		return null
	var material: ShaderMaterial = geometry.get_meta(META) as ShaderMaterial \
		if geometry.has_meta(META) else null
	if material == null:
		material = ShaderMaterial.new()
		material.shader = SHADER
		geometry.set_meta(META, material)
		geometry.add_to_group(GROUP)
	material.set_shader_parameter(&"outline_color", color)
	_sync(geometry, material)
	return material


## Prende o apaga el borde de un objeto que ya lo pidio, sin soltarlo: la puerta
## de spawn lo prende al anunciar enemigos y lo apaga al cerrarse.
static func set_active(geometry: GeometryInstance3D, active: bool) -> void:
	if geometry == null or not geometry.has_meta(META):
		return
	geometry.set_meta(META_ACTIVE, active)
	_sync(geometry, geometry.get_meta(META) as ShaderMaterial)


## El borde sobre cada malla de un modelo (el `root` incluido): un modelo de Meshy
## llega como varias piezas, y cada una delinea la suya.
static func attach_all(root: Node, color: Color) -> void:
	if root == null:
		return
	var geometry := root as GeometryInstance3D
	if geometry != null:
		attach(geometry, color)
	for child: Node in root.get_children():
		attach_all(child, color)


## Cuelga o descuelga todos los bordes ya pedidos.
static func set_enabled(value: bool, tree: SceneTree) -> void:
	enabled = value
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		var geometry := node as GeometryInstance3D
		_sync(geometry, geometry.get_meta(META) as ShaderMaterial)


## Colgado si el estilo lo pide y el objeto no lo tiene apagado.
static func _sync(geometry: GeometryInstance3D, material: ShaderMaterial) -> void:
	if enabled and bool(geometry.get_meta(META_ACTIVE, true)):
		_chain(geometry, material)
	else:
		_unchain(geometry, material)


## Si el borde esta colgado de `geometry`. Para las pruebas.
static func is_chained(geometry: GeometryInstance3D) -> bool:
	if not geometry.has_meta(META):
		return false
	var outline: Material = geometry.get_meta(META)
	var link: Material = geometry.material_overlay
	while link != null:
		if link == outline:
			return true
		link = link.next_pass
	return false


## La cadena se rearma cada vez: un telegraph que reconstruye su brillo pone un
## overlay nuevo sin el borde detras.
static func _chain(geometry: GeometryInstance3D, outline: ShaderMaterial) -> void:
	var top: Material = geometry.material_overlay
	if top == null or top == outline:
		geometry.material_overlay = outline
		return
	while top.next_pass != null and top.next_pass != outline:
		top = top.next_pass
	top.next_pass = outline


static func _unchain(geometry: GeometryInstance3D, outline: ShaderMaterial) -> void:
	if geometry.material_overlay == outline:
		geometry.material_overlay = null
		return
	var link: Material = geometry.material_overlay
	while link != null:
		if link.next_pass == outline:
			link.next_pass = null
			return
		link = link.next_pass
