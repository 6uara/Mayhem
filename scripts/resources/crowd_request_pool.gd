@tool
class_name CrowdRequestPool
extends Resource
## Los pedidos que el publico puede hacer, y cada cuanto. Ver CrowdRequests.

@export var requests: Array[CrowdRequest] = []
## Primera oleada (1-based) en la que el publico pide cosas. La primera se juega
## sin pedidos: es la que enseña que existen los bonos.
@export var from_wave: int = 2
## Espera desde que arranca la oleada hasta el primer pedido.
@export var first_delay: float = 15.0
## Espera entre que termina un pedido y empieza el siguiente.
@export var min_interval: float = 20.0
@export var max_interval: float = 35.0
