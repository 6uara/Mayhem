class_name IconSet
extends RefCounted
## Los iconos de UI dibujados a mano, buscados por el mismo id que usa el resto
## del juego.
##
## Por que por convencion y no por una tabla: el id de un trofeo, de un bono o de
## una mejora ya existe -en `RunRecord`, en `KillBonusTracker`, en el `.tres` de
## la mejora- y el archivo se llama igual a proposito (ver
## docs/HANDOFF_ICONOGRAPHY.md §4). Una tabla `id -> ruta` seria una tercera
## copia de esos nombres, y la que se olvidaria de actualizar.
##
## Devolver `null` es parte del contrato, no una falla: un id sin archivo cae en
## el texto que la pantalla ya mostraba. Eso es lo que permitio cablear esto con
## el set a medio dibujar, y lo que va a permitir agregar un bono nuevo sin
## esperar a que exista su icono.

const ROOT: String = "res://ui/icons"

## Los grupos que existen. El grupo es tambien el prefijo del archivo:
## `trophy/trophy_champion.svg`.
const TROPHY: StringName = &"trophy"
const BONUS: StringName = &"bonus"
const UPGRADE: StringName = &"upgrade"
const ENEMY: StringName = &"enemy"
const ECON: StringName = &"econ"

## Cache de lo ya resuelto, incluidos los que no existen.
##
## Guardar tambien los ausentes es el punto: sin eso, cada fila de la tabla que
## muestra un trofeo sin icono vuelve a pegarle al disco para volver a no
## encontrarlo.
static var _cache: Dictionary = {}


## El icono de `id` dentro de `group`, o null si no hay archivo.
static func get_icon(group: StringName, id: StringName) -> Texture2D:
	var key: String = "%s/%s" % [group, id]
	if _cache.has(key):
		return _cache[key]
	var path: String = "%s/%s/%s_%s.svg" % [ROOT, group, group, id]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_cache[key] = texture
	return texture


static func trophy(id: StringName) -> Texture2D:
	return get_icon(TROPHY, id)


static func bonus(id: StringName) -> Texture2D:
	return get_icon(BONUS, id)


static func upgrade(id: StringName) -> Texture2D:
	return get_icon(UPGRADE, id)


static func enemy(id: StringName) -> Texture2D:
	return get_icon(ENEMY, id)


static func econ(id: StringName) -> Texture2D:
	return get_icon(ECON, id)


## Un `MayhemIcon` ya armado con esta textura y este color, del tamaño pedido.
##
## Existe para que las pantallas no tengan que repetir las cuatro lineas de
## siempre, y para que todas pasen por `MayhemIcon` en vez de meter un
## `TextureRect` suelto: el dia que un icono se reemplace por geometria otra vez,
## el punto de uso no se entera.
static func make(group: StringName, id: StringName, tint: Color,
		box: float) -> MayhemIcon:
	var icon := MayhemIcon.new()
	icon.texture = get_icon(group, id)
	icon.color = tint
	icon.custom_minimum_size = Vector2(box, box)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## Si hay archivo para este id. Lo usan las pantallas que tienen algo que mostrar
## en su lugar - una ficha de texto - y necesitan saber cual de las dos poner.
static func has(group: StringName, id: StringName) -> bool:
	return get_icon(group, id) != null
