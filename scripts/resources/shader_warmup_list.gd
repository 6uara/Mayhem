@tool
class_name ShaderWarmupList
extends Resource
## Lo que ShaderWarmup dibuja una vez detras de la transicion, antes de que el
## jugador vea la arena. Ver ShaderWarmup.

## Escenas de efectos y objetos que aparecen recien en la pelea: la explosion, los
## impactos, la muerte de un enemigo, los charcos, los gadgets. Se dibujan como
## copia visual (sin scripts), asi que una explosion de aca no hace daño.
@export var scenes: Array[PackedScene] = []
## Ademas, el modelo de cada arquetipo de `data/enemies/`. Los enemigos ya salen
## del pool prewarmeados, pero quedan invisibles hasta la primera puerta, y
## lo invisible no compila su pipeline.
@export var include_enemy_models: bool = true
## Cuantos frames se dejan dibujar. Dos alcanzan para que el driver arme los
## pipelines; mas es tiempo de carga sin ganancia.
@export_range(1, 8) var frames: int = 2
