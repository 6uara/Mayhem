extends GutTest
## El set de iconos de UI y la convencion que lo busca.
##
## Lo que se prueba no es que los dibujos estén lindos, sino las dos cosas de las
## que depende el cableado: que **todo id que una pantalla puede pedir tenga
## archivo**, y que pedir uno que no existe devuelva null en vez de explotar.
## Esa segunda es la que permitio cablear los iconos con el set a medio dibujar.


# ------------------------------------------------------------- la cobertura

func test_every_kill_bonus_has_an_icon() -> void:
	for id: StringName in KillBonusTracker.BONUS_LABEL.keys():
		assert_not_null(IconSet.bonus(id), "falta el icono del bono %s" % id)


func test_every_trophy_has_an_icon() -> void:
	for id: StringName in RunRecord.TROPHY_INFO.keys():
		assert_not_null(IconSet.trophy(id), "falta el icono del trofeo %s" % id)


## Las 19 mejoras que hay en disco, no una lista escrita a mano: una mejora nueva
## sin icono tiene que hacer fallar esto.
func test_every_upgrade_has_an_icon() -> void:
	var dir: DirAccess = DirAccess.open("res://data/upgrades")
	assert_not_null(dir, "no se pudo leer data/upgrades")
	var checked: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var data := load("res://data/upgrades/%s" % file_name) as UpgradeData
		if data == null:
			continue
		checked += 1
		assert_not_null(IconSet.upgrade(data.id), "falta el icono de %s" % data.id)
	assert_gt(checked, 0, "no se reviso ninguna mejora")


## Los ocho arquetipos, contra los `.tres` que existen y no contra una lista.
func test_every_enemy_archetype_has_an_icon() -> void:
	var dir: DirAccess = DirAccess.open("res://data/enemies")
	assert_not_null(dir)
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/%s" % file_name) as EnemyData
		if data == null:
			continue
		assert_not_null(IconSet.enemy(data.id), "falta el icono de %s" % data.id)


func test_the_economy_icons_exist() -> void:
	for id: StringName in [&"currency_lost", &"health_gain", &"ammo", &"time",
			&"wave", &"enemies_left"]:
		assert_not_null(IconSet.econ(id), "falta el icono de economia %s" % id)


# ------------------------------------------------------------- el contrato

## Devolver null es parte del contrato, no una falla: la pantalla cae en el texto
## que ya mostraba.
func test_a_missing_icon_is_null_and_not_an_error() -> void:
	assert_null(IconSet.get_icon(IconSet.TROPHY, &"no_existe"))
	assert_false(IconSet.has(IconSet.BONUS, &"no_existe"))


func test_a_missing_group_is_null_too() -> void:
	assert_null(IconSet.get_icon(&"no_existe", &"tampoco"))


## Dos pedidos del mismo icono devuelven el mismo objeto: sin cache, cada fila de
## la tabla vuelve a pegarle al disco.
func test_the_same_icon_is_only_resolved_once() -> void:
	var first: Texture2D = IconSet.trophy(RunRecord.CHAMPION)
	var second: Texture2D = IconSet.trophy(RunRecord.CHAMPION)
	assert_eq(first, second)


# ------------------------------------------------------------- lo que dibujan

## Un icono en blanco es un archivo que existe y no se ve, que es peor que uno
## que falta: el que falta cae en el texto y este deja un hueco.
func test_no_icon_is_blank() -> void:
	for id: StringName in RunRecord.TROPHY_INFO.keys():
		var image: Image = IconSet.trophy(id).get_image()
		assert_gt(_opaque_fraction(image), 0.01, "%s se importo vacio" % id)


## Y ninguno es un cuadrado lleno: eso seria un icono que no se distingue de
## cualquier otro a tamaño de ficha.
func test_no_icon_is_a_solid_block() -> void:
	for id: StringName in KillBonusTracker.BONUS_LABEL.keys():
		var image: Image = IconSet.bonus(id).get_image()
		assert_lt(_opaque_fraction(image), 0.9, "%s cubre casi todo el cuadro" % id)


## `MayhemIcon` tiñe la textura con `color`, asi que un archivo que trae color
## propio no se puede repintar - y todas las pantallas lo repintan.
func test_the_icons_are_drawn_white_so_the_ui_can_tint_them() -> void:
	for id: StringName in [RunRecord.CHAMPION, RunRecord.TYCOON, RunRecord.BLITZ]:
		var image: Image = IconSet.trophy(id).get_image()
		for y: int in range(0, image.get_height(), 8):
			for x: int in range(0, image.get_width(), 8):
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a < 0.9:
					continue
				assert_almost_eq(pixel.r, 1.0, 0.06, "%s no es blanco puro" % id)
				assert_almost_eq(pixel.g, 1.0, 0.06, "%s no es blanco puro" % id)
				assert_almost_eq(pixel.b, 1.0, 0.06, "%s no es blanco puro" % id)
				return


func _opaque_fraction(image: Image) -> float:
	var opaque: int = 0
	# De a cuatro pixeles: es una medicion de cobertura, no un conteo exacto, y
	# recorrer 256x256 enteros por icono multiplica el tiempo del test por nada.
	for y: int in range(0, image.get_height(), 4):
		for x: int in range(0, image.get_width(), 4):
			if image.get_pixel(x, y).a > 0.5:
				opaque += 1
	var sampled: int = int(ceil(image.get_height() / 4.0)) * int(ceil(image.get_width() / 4.0))
	return float(opaque) / float(sampled)
