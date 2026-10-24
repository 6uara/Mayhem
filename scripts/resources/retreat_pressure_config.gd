@tool
class_name RetreatPressureConfig
extends Resource
## Los numeros de la presion de retirada. Ver `RetreatPressure` y CombatDirector.
##
## Retroceder disparando es la forma mas barata de pelear contra una horda que
## viene de frente: el jugador camina hacia atras casi tan rapido como corre un
## Rusher y los tiradores le apuntan a donde esta, no a donde va. Nada de esto lo
## prohibe. Lo que hace es que la horda **lea** el patron y lo conteste como lo
## contestaria una jauria: cortando el camino, tirando adelante y apurando el paso.
## Cada respuesta escala con cuanto se sostiene la retirada y se apaga sola en
## cuanto el jugador cambia de patron.

@export_group("Medicion")
## Velocidad hacia atras, en m/s, por debajo de la cual no se acumula nada. Un
## paso atras para esquivar un salto no es un patron.
@export var min_retreat_speed: float = 2.5
## Velocidad hacia atras a la que la presion sube a ritmo completo. Entre las dos
## sube proporcional.
@export var full_retreat_speed: float = 6.0
## Segundos de retirada a ritmo completo para llegar de 0 a 1.
@export var rise_time: float = 3.0
## Segundos para bajar de 1 a 0 sin retroceder. Mas corto que la subida a
## proposito: cambiar de patron tiene que pagar enseguida.
@export var fall_time: float = 1.5
## Presion por debajo de la cual la horda no reacciona. Entre esto y 1 la
## respuesta crece suave.
@export_range(0.0, 0.95) var onset: float = 0.3

@export_group("Escala por oleada")
## Que fraccion de la respuesta hay en la primera oleada, que es de aprender.
@export_range(0.0, 1.0) var first_wave_strength: float = 0.4
## Primera oleada (1-based) con la respuesta completa.
@export var full_strength_wave: int = 6

@export_group("Corte de camino")
## Cuantos cuerpo a cuerpo y bombas, como mucho, dejan de perseguir y van a donde
## el jugador va a estar.
@export var max_interceptors: int = 2
## Segundos de retirada que se adelanta el punto de corte.
@export var interception_lead_time: float = 1.2

@export_group("Tiro")
## Fraccion de la retirada que adelantan los tiradores, con la respuesta completa.
## Solo la componente hacia atras: moverse de costado se sigue esquivando igual.
@export_range(0.0, 1.0) var ranged_lead_fraction: float = 0.8
## Lo mismo para el salto del Rusher, que se compromete al despegar.
@export_range(0.0, 1.0) var leap_lead_fraction: float = 0.6
## Lo que suman los frascos a su propio adelanto, con la respuesta completa.
@export_range(0.0, 1.0) var flask_lead_bonus: float = 0.35

@export_group("Persecucion")
## Cuanto mas rapido corren los cuerpo a cuerpo detras de alguien que retrocede,
## con la respuesta completa. Chico a proposito: el jugador camina a 7.5 y el
## Rusher a 7.2, alcanza con que la distancia deje de crecer.
@export_range(0.0, 0.5) var pursuit_speed_bonus: float = 0.12

@export_group("Puertas")
## Cuanto mas probable es, con la respuesta completa, que un grupo salga por la
## puerta que queda hacia donde el jugador retrocede, entre las que el grupo nombra.
@export var door_ahead_weight: float = 3.0
