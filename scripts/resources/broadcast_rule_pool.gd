@tool
class_name BroadcastRulePool
extends Resource
## Las reglas de transmision que el Host puede sortear, los contratos que puede
## ofrecer, y desde cuando.

@export var rules: Array[BroadcastRule] = []
## Primera oleada (1-based) que puede traer una regla. Las primeras se juegan
## limpias: primero se aprende el juego, despues se lo cambia.
@export var from_wave: int = 3
## Las oleadas elite se juegan sin regla: ya son el pico de la tanda.
@export var skip_elite_waves: bool = true
## Cuantas reglas ofrece el Host en la tienda para que el jugador elija una. Con
## 1 no hay eleccion: la regla se anuncia, como antes de que hubiera ofertas.
@export_range(1, 4) var offer_size: int = 2

@export_group("Contratos")
## Restricciones opcionales que se firman en la tienda a cambio de plata.
@export var contracts: Array[BroadcastRule] = []
## Primera oleada (1-based) que puede traer un contrato.
@export var contracts_from_wave: int = 2
## Probabilidad de que una visita a la tienda traiga un contrato.
@export_range(0.0, 1.0) var contract_chance: float = 0.6
## Las elite si pueden traer contrato: no cambia la oleada, es una apuesta que el
## jugador elige hacer sobre el pico de la tanda.
@export var contracts_on_elite_waves: bool = true
