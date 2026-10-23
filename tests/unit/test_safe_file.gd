extends GutTest
## SafeFile: un guardado cortado a la mitad no puede llevarse puesto el archivo
## que ya habia.

const DIR: String = "user://test_safe_file"
const PATH: String = DIR + "/data.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_clean()


func after_each() -> void:
	_clean()


func test_a_write_replaces_the_file_and_leaves_no_temporary() -> void:
	_write_raw(PATH, "viejo")
	assert_eq(SafeFile.write_text(PATH, "nuevo"), OK)
	assert_eq(FileAccess.get_file_as_string(PATH), "nuevo")
	assert_false(FileAccess.file_exists(PATH + SafeFile.TEMP_SUFFIX), "el temporal no queda")


## El corte entre borrar el viejo y mover el nuevo: lo unico entero es el temporal.
func test_recover_promotes_a_temporary_when_the_file_is_gone() -> void:
	_write_raw(PATH + SafeFile.TEMP_SUFFIX, "completo")
	SafeFile.recover(PATH)
	assert_eq(FileAccess.get_file_as_string(PATH), "completo")
	assert_false(FileAccess.file_exists(PATH + SafeFile.TEMP_SUFFIX))


## El corte antes del rename: el temporal puede estar a medias y el original es
## el que vale.
func test_recover_keeps_the_original_over_a_half_written_temporary() -> void:
	_write_raw(PATH, "original")
	_write_raw(PATH + SafeFile.TEMP_SUFFIX, "a med")
	SafeFile.recover(PATH)
	assert_eq(FileAccess.get_file_as_string(PATH), "original")
	assert_false(FileAccess.file_exists(PATH + SafeFile.TEMP_SUFFIX), "y el temporal se tira")


func test_a_config_file_goes_through_the_same_door() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "fov", 104.0)
	var path: String = DIR + "/settings.cfg"
	assert_eq(SafeFile.save_config(config, path), OK)
	var loaded := ConfigFile.new()
	assert_eq(loaded.load(path), OK)
	assert_eq(float(loaded.get_value("video", "fov")), 104.0)
	assert_false(FileAccess.file_exists(path + SafeFile.TEMP_SUFFIX))


## Un recurso se escribe aparte y no al lado: un `x.tmp.tres` en la carpeta de
## arenas apareceria en la lista de arenas del jugador.
func test_a_resource_is_staged_out_of_the_folder_listing() -> void:
	var path: String = DIR + "/thing.tres"
	var resource := Resource.new()
	assert_eq(SafeFile.save_resource(resource, path), OK)
	assert_true(FileAccess.file_exists(path))
	for file_name: String in DirAccess.get_files_at(DIR):
		assert_false(file_name.contains("tmp"), "nada a medio guardar en la carpeta")
	assert_eq(DirAccess.get_files_at(DIR.path_join(SafeFile.STAGING_DIR)).size(), 0,
		"y la carpeta de preparacion queda vacia")


func _write_raw(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	var staging: String = DIR.path_join(SafeFile.STAGING_DIR)
	for file_name: String in DirAccess.get_files_at(staging):
		DirAccess.remove_absolute(staging.path_join(file_name))
	DirAccess.remove_absolute(staging)
	for file_name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file_name))
