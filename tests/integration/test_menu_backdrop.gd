extends GutTest
## La ciudad 3D detras del menu principal, y el wordmark encima.
##
## Las dos formas de romper esto son silenciosas y se ven igual desde el arbol de
## escenas: una ciudad que se construye entera y queda tapada por un Control
## opaco, y una camara que orbita mirando al centro vacio en vez de a las torres.
## En los dos casos el menu abre, no hay error en consola, y el fondo es negro.

const MENU_SCENE: String = "res://scenes/main/main_menu.tscn"
const LOGO_PATH: String = "res://assets/ui/mayhem_logo.png"

var _menu: Control


func before_each() -> void:
	_menu = add_child_autofree(load(MENU_SCENE).instantiate())
	await wait_frames(2)


func _backdrop() -> MenuBackdrop:
	return _menu.get_node("Backdrop") as MenuBackdrop


func test_the_menu_has_a_city_behind_it() -> void:
	var backdrop: MenuBackdrop = _backdrop()
	assert_not_null(backdrop, "el menu perdio su fondo")
	assert_gt(backdrop.skyline.get_tower_count(), 0, "la ciudad quedo vacia")


func test_the_city_is_the_same_one_the_arena_uses() -> void:
	# Si el menu se hiciera su propia ciudad, dejaria de prometer el lugar al que
	# se entra apenas alguna de las dos cambie.
	assert_true(_backdrop().skyline is CitySkyline)


func test_nothing_opaque_is_painted_over_the_city() -> void:
	# Un ColorRect a pantalla completa con alpha 1 construye la ciudad y despues
	# la tapa. Es el bug que no se nota escribiendolo.
	var background := _menu.get_node("Root/Background") as ColorRect
	assert_lt(background.color.a, 1.0,
		"el fondo del menu tapa la ciudad que el backdrop acaba de construir")


func test_the_camera_looks_out_at_the_towers_not_into_the_clearing() -> void:
	# La camara orbita el centro y las torres estan afuera del anillo. Mirando
	# para adentro se ve el claro vacio, que es cielo y nada mas.
	var backdrop: MenuBackdrop = _backdrop()
	var camera: Camera3D = backdrop.camera
	for turn: int in 8:
		backdrop._yaw = TAU * float(turn) / 8.0
		backdrop._place_camera()
		var radial: Vector3 = Vector3(camera.position.x, 0.0, camera.position.z).normalized()
		var forward: Vector3 = -camera.global_transform.basis.z
		forward = Vector3(forward.x, 0.0, forward.z).normalized()
		assert_almost_eq(forward.dot(radial), 1.0, 0.001,
			"a %d/8 de vuelta la camara no mira hacia afuera" % turn)


func test_the_camera_never_leaves_the_clearing() -> void:
	# Orbita para tener paralaje, pero el claro existe para que nunca se acerque
	# a una torre: adentro de una caja del skyline se ve el interior de la caja.
	var backdrop: MenuBackdrop = _backdrop()
	assert_lt(backdrop.orbit_radius, backdrop.clearing,
		"la orbita se sale del claro que la ciudad le dejo")


func test_the_wordmark_is_transparent() -> void:
	# El logo tal como vino de marca es opaco, con su propio navy de fondo. Sobre
	# la ciudad eso es un rectangulo tapando el skyline, asi que el que usa el
	# menu es el que `tools/make_menu_logo.py` despega del fondo.
	var image: Image = (load(LOGO_PATH) as Texture2D).get_image()
	assert_true(image.detect_alpha() != Image.ALPHA_NONE,
		"el wordmark del menu no tiene transparencia: seria una placa navy")
	assert_eq(image.get_pixel(0, 0).a, 0.0, "la esquina del wordmark tendria que ser fondo")


func test_the_menu_shows_the_wordmark_instead_of_typing_the_name() -> void:
	var logo := _menu.get_node_or_null("Root/Panel/Margin/Layout/Logo") as TextureRect
	assert_not_null(logo, "el menu no muestra el logo")
	assert_not_null(logo.texture)


func test_the_wordmark_actually_takes_up_room_on_screen() -> void:
	# Esta suite ya paso una vez en verde con el logo invisible: el nodo estaba,
	# con su textura puesta, midiendo cero de alto. Un TextureRect adentro de un
	# VBoxContainer no deduce su altura de la textura -`expand_mode` proporcional
	# calcula minimo cero cuando todavia no sabe el ancho-, asi que "existe y
	# tiene textura" no es lo mismo que "se ve".
	var logo := _menu.get_node("Root/Panel/Margin/Layout/Logo") as TextureRect
	assert_gt(logo.size.y, 32.0, "el logo esta en el arbol pero no ocupa alto")
	assert_gt(logo.size.x, 32.0, "el logo esta en el arbol pero no ocupa ancho")
