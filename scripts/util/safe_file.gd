class_name SafeFile
extends RefCounted
## Escrituras que no pueden dejar un archivo a medias. Utilidad estatica, como
## PhysicsLayers.
##
## Abrir un archivo con `FileAccess.WRITE` lo trunca en el acto: si el juego se
## cierra, se cuelga o se corta la luz entre ese momento y el ultimo byte, lo que
## queda es un JSON roto, y los cargadores -con razon- lo descartan entero. Eso es
## la tabla de puntajes, las opciones o la maestria de armas de alguien, perdidas
## por guardar una fila.
##
## Lo que hace esto: escribir todo al lado (`<archivo>.tmp`) y recien con el
## contenido entero en disco reemplazar el original con un rename. Si algo se
## corta antes del rename, el original sigue intacto; si se corta en el medio,
## `recover()` encuentra el temporal completo y lo pone en su lugar.
##
## No es un fsync: protege contra el proceso que muere, no contra el disco que
## miente. Para lo que guarda este juego alcanza.

const TEMP_SUFFIX: String = ".tmp"
## Donde se escriben los recursos antes de moverlos. Una carpeta y no un sufijo:
## ResourceSaver elige el formato por la extension, asi que un `.tres.tmp` no se
## puede guardar, y un `x.tmp.tres` en la misma carpeta apareceria en cualquier
## listado de `.tres` (la lista de arenas del jugador, por ejemplo).
const STAGING_DIR: String = ".staging"


## Texto entero o nada. Devuelve OK o el error que impidio guardar; con error, el
## archivo anterior queda como estaba.
static func write_text(path: String, text: String) -> Error:
	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temp)
		return error
	return _replace(temp, path)


## Lo mismo para un ConfigFile.
static func save_config(config: ConfigFile, path: String) -> Error:
	var temp: String = path + TEMP_SUFFIX
	var error: Error = config.save(temp)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return error
	return _replace(temp, path)


## Lo mismo para un recurso: se guarda en `STAGING_DIR`, al lado del destino, con
## el mismo nombre, y se mueve.
static func save_resource(resource: Resource, path: String) -> Error:
	var staging: String = path.get_base_dir().path_join(STAGING_DIR)
	if not DirAccess.dir_exists_absolute(staging):
		var made: Error = DirAccess.make_dir_recursive_absolute(staging)
		if made != OK:
			return made
	var temp: String = staging.path_join(path.get_file())
	var error: Error = ResourceSaver.save(resource, temp)
	if error != OK:
		DirAccess.remove_absolute(temp)
		return error
	return _replace(temp, path)


## Antes de leer `path`. Si falta y quedo un temporal, el corte fue entre borrar
## el viejo y mover el nuevo: el temporal esta completo y es el que vale.
##
## Si estan los dos, el temporal es de una escritura que no llego al rename y
## puede estar a medias: el original es el bueno, y el temporal se tira.
static func recover(path: String) -> void:
	var temp: String = path + TEMP_SUFFIX
	if not FileAccess.file_exists(temp):
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(temp)
		return
	if DirAccess.rename_absolute(temp, path) != OK:
		push_warning("SafeFile: no se pudo recuperar %s desde %s" % [path, temp])


static func _replace(temp: String, path: String) -> Error:
	var error: Error = DirAccess.rename_absolute(temp, path)
	if error != OK:
		push_error("SafeFile: no se pudo reemplazar %s (%d)" % [path, error])
		DirAccess.remove_absolute(temp)
	return error
