@tool
class_name FeedbackConfig
extends Resource
## A donde manda al jugador el boton "Open form", y como se llaman las
## categorias que puede elegir.
##
## La URL vive en un `.tres` y no en el script por una razon practica: el
## formulario se va a mudar - de un Google Form a otro, de itch a Steam - y
## mudarlo no puede pedir una recompilacion ni un parche del ejecutable.

## Formulario web al que lleva "Open form". Vacio esconde el boton, que es lo
## correcto mientras no haya formulario todavia.
@export var form_url: String = ""
## Las categorias, en orden. La primera es la que aparece elegida.
@export var categories: Array[String] = ["Bug", "Balance", "Idea", "Other"]
