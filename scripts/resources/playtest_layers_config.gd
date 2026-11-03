@tool
class_name PlaytestLayersConfig
extends Resource
## Que capas del show van encendidas. Para el playtest, no para el jugador.
##
## El juego apila cuatro sistemas encima de la pelea: el rating, las reglas de la
## casa, los contratos y los pedidos del publico. Cada uno tiene tests, pero
## ninguno se jugo con alguien que no conozca el juego, y la pregunta del
## playtest no es solo "esta bien balanceado" sino "esto se ve mientras se
## pelea, o es ruido". Apagar una capa y jugar una tanda sin ella es la forma
## mas barata de contestarla. Ver docs/PLAYTEST.md.
##
## Se pisa por linea de comandos sin re-exportar (ver PlaytestLayers).

## El rating de la transmision: el medidor, el multiplicador de estilo, el pico
## y el retiro del patrocinador.
@export var rating: bool = true
## Las reglas de la casa que el Host ofrece en la tienda.
@export var rules: bool = true
## Los contratos opcionales que el Host ofrece en la tienda.
@export var contracts: bool = true
## Los pedidos del publico durante la oleada.
@export var crowd_requests: bool = true
