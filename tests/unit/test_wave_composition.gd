extends GutTest
## Cómo están armadas las oleadas, que es donde vive la mitad del diseño de
## enemigos que no está en ningún `.gd`.
##
## Las dos cosas que se prueban acá fallan en silencio y son las dos peores:
##
##   1. Un arquetipo construido, probado y documentado que **ninguna oleada
##      spawnea**. Pasó con el Bomber: existía en todos lados menos en el juego.
##   2. Tres grupos con `delay` casi igual. No es dificultad, es ruido - el
##      jugador no puede atribuir lo que le pasó a ninguna decisión suya.
##
## Ver PLAN_ENEMY_BEHAVIOR.md §2.1 y §5.2.

const WAVE_COUNT: int = 10
## Cuántos segundos tienen que separar dos picos tardíos de la misma ola.
##
## "Tardío" es lo que llega después de la apertura: los grupos de apertura (los
## primeros segundos) son la ola arrancando y sí pueden encimarse, porque son el
## fondo sobre el que después pasa todo lo demás.
const LATE_GROUP_DELAY: float = 10.0
const MIN_PEAK_SEPARATION: float = 4.0


func _waves() -> Array[WaveData]:
	var waves: Array[WaveData] = []
	for index: int in range(1, WAVE_COUNT + 1):
		var wave: WaveData = load("res://data/waves/wave_%02d.tres" % index)
		assert_not_null(wave, "existe la oleada %d" % index)
		if wave != null:
			waves.append(wave)
	return waves


## Arquetipos que existen en el repo y a propósito **no** se spawnean.
##
## El Elite sale del pool mientras se lo reworkea. Su problema no es de números:
## es el único arquetipo cuya pregunta al jugador se superpone con la del Rusher
## -viene de frente y pega fuerte- y el `CombatDirector` lo deja en evidencia,
## porque pide el mismo puesto que el melee básico y no aporta un ángulo nuevo.
## Las olas de élite mientras tanto son olas de masa.
##
## La lista es la excepción **nombrada**: sacar un arquetipo tiene que costar una
## línea acá y no el silencio de un test que se dejó de correr.
const BENCHED: Array[StringName] = [&"elite"]


## Todo arquetipo con `.tres` propio tiene que aparecer en alguna ola, salvo los
## que estén en el banco. Es la prueba que faltaba cuando el Bomber existía en el
## repo y no en el juego.
func test_every_archetype_is_actually_spawned_by_some_wave() -> void:
	var spawned: Dictionary = {}
	for wave: WaveData in _waves():
		for group: SpawnGroup in wave.spawn_groups:
			if group != null and group.enemy_data != null:
				spawned[group.enemy_data.id] = true

	for path: String in _archetype_paths():
		var data: EnemyData = load(path)
		if BENCHED.has(data.id):
			assert_false(spawned.has(data.id),
				"%s está en el banco: si volvió al juego, sacalo de BENCHED" % data.id)
			continue
		assert_true(spawned.has(data.id),
			"%s no aparece en ninguna oleada: está construido y el juego no lo usa" % data.id)


## Un arquetipo nuevo se presenta con lo más chico que va a mostrar nunca. La
## primera vez que lo ves, lo ves en una situación donde equivocarte no te mata -
## y eso, medido, es que ningún grupo posterior del mismo arquetipo sea **más
## chico** que el de su debut.
func test_no_archetype_debuts_bigger_than_it_ever_appears_again() -> void:
	var debut: Dictionary = {}
	var smallest: Dictionary = {}
	for wave: WaveData in _waves():
		for group: SpawnGroup in wave.spawn_groups:
			if group == null or group.enemy_data == null:
				continue
			var id: StringName = group.enemy_data.id
			if not debut.has(id):
				debut[id] = group.count
				smallest[id] = group.count
			smallest[id] = mini(int(smallest[id]), group.count)

	for id: StringName in debut:
		assert_eq(int(debut[id]), int(smallest[id]),
			"%s se presenta de a %d y después aparece de a %d: el debut tiene que ser el más chico"
				% [id, int(debut[id]), int(smallest[id])])


## Y los tres especialistas -los que traen una mecánica nueva y no sólo otra
## silueta- debutan de a uno o dos. Aprender qué es una espoleta mientras hay tres
## contando no es aprender, es pagar.
func test_the_specialists_debut_alone_or_in_pairs() -> void:
	var specialists: Array[StringName] = [&"bomber", &"flyer", &"environmental"]
	var seen: Dictionary = {}
	for wave: WaveData in _waves():
		for group: SpawnGroup in wave.spawn_groups:
			if group == null or group.enemy_data == null:
				continue
			var id: StringName = group.enemy_data.id
			if seen.has(id) or not specialists.has(id):
				continue
			seen[id] = true
			assert_lte(group.count, 2,
				"%s debuta de a %d" % [id, group.count])
	for id: StringName in specialists:
		assert_true(seen.has(id), "%s tiene que debutar en alguna ola" % id)


## Los picos tardíos se escalonan. Tres grupos llegando en la misma ventana de
## cuatro segundos no son tres decisiones, son ninguna.
func test_late_groups_do_not_all_land_at_once() -> void:
	for wave: WaveData in _waves():
		var late: Array[float] = []
		for group: SpawnGroup in wave.spawn_groups:
			if group != null and group.delay >= LATE_GROUP_DELAY:
				late.append(group.delay)
		late.sort()
		for index: int in range(1, late.size()):
			assert_gte(late[index] - late[index - 1], MIN_PEAK_SEPARATION,
				"oleada %d: dos picos a %.1fs y %.1fs se pisan"
					% [wave.wave_index + 1, late[index - 1], late[index]])


## Techo por rol y no por cantidad total: lo que satura no es cuántos enemigos
## hay sino cuántos piden lo mismo al mismo tiempo.
func test_no_wave_asks_the_same_question_too_many_times() -> void:
	var caps: Dictionary = {
		&"environmental": 3,
		&"flyer": 3,
		&"bomber": 3,
	}
	for wave: WaveData in _waves():
		for group: SpawnGroup in wave.spawn_groups:
			if group == null or group.enemy_data == null:
				continue
			var cap: int = int(caps.get(group.enemy_data.id, 99))
			assert_lte(group.count, cap,
				"oleada %d: %d %s a la vez" % [wave.wave_index + 1, group.count,
					group.enemy_data.id])


func _archetype_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://data/enemies")
	if dir == null:
		return paths
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			paths.append("res://data/enemies/%s" % file)
	return paths
