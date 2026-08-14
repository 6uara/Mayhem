---
tags: [mayhem, coop, red]
---

# Coop P2P

**Vive solo en `feat/coop-p2p`.** No es parte del entregable: el juego que se
entrega es el single player de `develop`. Esta rama sigue a `develop` con merges
regulares para que la versión coop no se quede vieja en términos de juego, pero
nada de lo que hay acá vuelve al entregable.

## La idea que sostiene todo

El single player no es un caso especial en ningún lado. Sin peer asignado Godot
reporta `unique_id 1` y todo nodo contesta `true` a `is_multiplayer_authority()`,
así que una partida solitaria es simplemente **una sesión de uno que nunca abrió
un socket**. Por eso los scripts de partida preguntan `NetworkManager.is_host()`
en vez de preguntar si el modo red está encendido: hay un solo camino de código
y el modo que más se juega es el que más se ejercita.

`NetworkManager` (autoload) es el único script que toca ENet o
`multiplayer.multiplayer_peer`. Cambiar el transporte —Steam P2P es el candidato
obvio— es tocar ese archivo y nada más.

## Qué anda hoy

| Pieza | Dónde | Qué hace |
| --- | --- | --- |
| Sesión y roster | `scripts/autoload/network_manager.gd` | Hostear/unirse, hasta 4, nombres saneados, host manda el roster |
| Lobby | `scripts/ui/coop_panel.gd` | Crear o unirse desde el menú |
| Cuerpos | `scripts/systems/player_spawn_controller.gd` | Un cuerpo por peer; el cliente avisa cuando su arena cargó |
| Enemigos | `scripts/systems/enemy_replicator.gd` | El host los simula; los clientes reciben snapshots a 20/s e interpolan |
| Disparo del cliente | `EnemyReplicator.report_hit()` | El cliente raycastea local y **pide** el impacto; el host lo resuelve |
| Plata | `EventBus.kill_credited` | La recompensa sigue al que disparó, no a quien simula |
| Ataques enemigos | `EnemyReplicator.broadcast_projectile()` / `broadcast_melee()` | El cliente ve el disparo, oye el golpe y ve el telegrafiado |
| Caídas | `Player._report_downed()` | Morir te pasa a la cámara de un compañero, no a game over |
| Revivir | `Player.revive_from_host()` | El corte entre oleadas levanta a los caídos |
| Tienda | `MatchDirector._open_break()` | Todos compran a la vez y la oleada arranca cuando el último está listo |
| Victoria | `MatchDirector._declare_victory()` | La declara el host; cada peer puntúa su propia billetera |

### El corte entre oleadas

Es el momento donde más se nota que hay cuatro personas y no una:

1. El host detecta la oleada limpia y difunde `_open_break`.
2. Cada peer calcula **su** liquidación: los kills que cobró y el daño que
   recibió son suyos, así que se computan en la máquina que los tiene.
3. El host levanta a los caídos. Se revive en el lugar donde cayeron: la arena
   está vacía en ese momento, y un teleport tendría que ponerse de acuerdo sobre
   un destino entre cuatro máquinas que sincronizan esa posición desde distintas.
4. Cada uno compra. Salir de la tienda no te devuelve a la arena: fija tu compra
   y muestra cuántos faltan.
5. Cuando entró el último —o cuando vence el plazo, por si alguien se colgó— el
   host llama a todos de vuelta y arranca la oleada siguiente.

## Probarlo sin dos personas

Dos arneses headless que se hablan entre sí:

```bash
godot --headless --path . -s res://tools/net_smoke_wave_host.gd &
sleep 2
godot --headless --path . -s res://tools/net_smoke_wave_client.gd
```

Lo que hay que leer en las trazas:

- `sim` y `puppets`: los dos lados coinciden en cuántos enemigos hay y difieren
  en quién los posee.
- `money`: se mueve del lado que disparó. Si el host cobra los kills del cliente,
  la atribución se rompió.
- `shop`: ambos entran al corte juntos y salen en el mismo tick.
- `downed`: vuelve a `false` al abrir la tienda. Eso es el revive.

## Lo que falta

- **Pickups y utilidades tiradas** no están replicados: cada peer ve las suyas.
  Es el siguiente en la fila — dos jugadores pueden levantar la misma munición.
- **Sin reconexión.** Si se cae el host, la partida termina.
- **Las voces del narrador** las dispara cada máquina por su cuenta, así que
  cuatro personas pueden escuchar comentarios distintos.
- **Sin anti-cheat**, y a propósito: el movimiento es autoritativo del cliente y
  esto es un juego para amigos. El único límite es `MAX_REPORTED_DAMAGE`, que
  existe para que un valor corrupto no borre una oleada entera.
