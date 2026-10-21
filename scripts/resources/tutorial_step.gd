@tool
class_name TutorialStep
extends Resource
## Un paso del tutorial de arranque. Ver TutorialDirector.
##
## Hay dos clases de paso: los que piden hacer algo (`goal` no vacio) y terminan
## cuando el jugador lo hace, y los que solo muestran algo (`goal` vacio) y pasan
## solos despues de `duration`. Todo es dato: reordenar o reescribir el tutorial
## es tocar `data/tutorial/tutorial_steps.tres`.

## Lo que el jugador tiene que hacer para pasar el paso. Vacio = paso informativo.
## Los que entiende el director: move, jump, slide, fast_fall, grapple, fire, ads,
## reload.
@export var goal: StringName = &""
## Titulo corto: "MOVE", "DIVE", "COLORS".
@export var title: String = ""
## El texto. `{accion}` entre llaves se reemplaza por la tecla que tenga
## asignada esa accion del InputMap ahora mismo, asi que un rebind no lo deja
## mintiendo: "Grapple with {grapple}." -> "Grapple with E.".
@export_multiline var text: String = ""
## Segundos en pantalla de un paso informativo.
@export var duration: float = 5.0
## Tope de un paso de accion: pasado esto avanza igual. El tutorial no puede
## dejar a nadie trabado - una arena sin anclas, un jugador que no encuentra la
## tecla. Cero es sin tope.
@export var max_time: float = 25.0
## Grupo de nodos que tiene que existir en la arena para que el paso tenga
## sentido (`grapple_anchor` para el gancho). Si no hay ninguno, se saltea.
@export var requires_group: StringName = &""
## El hint de primera vez que este paso ya enseño (TutorialHintManager). Hacer el
## paso lo marca como visto, para que despues no se repita.
@export var teaches_hint: StringName = &""
