@tool
class_name CrowdRequest
extends Resource
## Un pedido del publico: "¡queremos un 360!". Tantas kills con un bono de estilo
## en tanto tiempo, y si se cumple, el publico paga.
##
## Existe porque los bonos de estilo eran pasivos: pagaban si pasaban, pero nada
## le pedia al jugador ir a buscar uno en particular. Un pedido convierte un bono
## en una meta de veinte segundos, y le da al show una voz mas que la del Host.

@export var id: StringName = &""
## Lo que grita la tribuna. Corto: va en el chip de la HUD.
@export var title: String = ""
## El id del bono de KillBonusTracker que cuenta (`airborne`, `spin`...).
@export var bonus_id: StringName = &""
## Cuantas kills con ese bono hacen falta.
@export var goal: int = 1
## Segundos para cumplirlo.
@export var time_limit: float = 20.0

@export_group("Premio")
## Puntos de rating que suma cumplirlo.
@export var reward_rating: float = 15.0
## Plata que paga, en la fila "Show" del desglose de la oleada.
@export var reward_currency: int = 60
## Si ademas el publico tira un regalo en el acto.
@export var throws_gift: bool = true
