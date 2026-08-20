---
tags: [mayhem, coop, red]
---

# Coop P2P

**Mergeado a `develop`** (2026-08-20). Vivió en `feat/coop-p2p` hasta que el
trabajo del playtest hizo que mantener dos ramas costara más que juntarlas: tres
de los arreglos pedidos tocaban archivos que coop ya había reescrito.

El single player sigue siendo el entregable, y sigue sin ser un caso especial en
ningún lado — ver abajo.

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
| Disparo del cliente | `EnemyReplicator.report_hit()` | El cliente raycastea local y **pide** el impacto; el host lo resuelve. Dos entradas: `Projectile._on_hit()` para las armas con bala, y `WeaponComponent._resolve_hitscan()` para las que resuelven en el gatillo |
| Plata | `EventBus.kill_credited` | La recompensa sigue al que disparó, no a quien simula |
| Ataques enemigos | `EnemyReplicator.broadcast_projectile()` / `broadcast_melee()` | El cliente ve el disparo, oye el golpe y ve el telegrafiado |
| Munición | `scripts/systems/ammo_pickup.gd` | La caja es del host: la pide el que la pisa, y desaparece para todos |
| Utilidades | `UtilityComponent._request_throw()` | El arco sale de tu mano al instante; el host vuela la copia que aturde |
| Paredes | `UtilityComponent.broadcast_landing()` | La pared queda parada en el mismo lugar en las cuatro máquinas |
| Caídas | `Player._report_downed()` | Morir te pasa a la cámara de un compañero, no a game over |
| Revivir | `Player.revive_from_host()` | El corte entre oleadas levanta a los caídos |

> **Una sola regla, dos caminos.** Nadie llama `HitboxComponent.take_hit()` derecho salvo el
> propio `EnemyReplicator`. Cuando develop paso las armas a hitscan aparecio un segundo lugar
> que aplicaba daño -`WeaponComponent._resolve_hitscan()`- y que no sabia nada de la red: un
> cliente hubiera matado su propia copia del enemigo mientras el de verdad seguia caminando.
> Va desviado por `report_hit()` igual que la bala. Si mañana aparece un arma nueva, la
> pregunta a hacerse es la misma: ¿esta pidiendo el impacto, o aplicandolo?
| Tienda | `MatchDirector._open_break()` | Todos compran a la vez y la oleada arranca cuando el último está listo |
| Victoria | `MatchDirector._declare_victory()` | La declara el host; cada peer puntúa su propia billetera |
| El Host (la voz) | `NarratorManager.say_shared()` | Una transmisión para los cuatro, misma línea y mismo momento |
| Caída del host | `MatchOverlay._on_host_disconnected()` | La corrida se frena y el cliente ve por qué, en vez de una arena congelada |

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

Los dos se hacen invulnerables y disparan solos, así que la oleada se limpia y
la corrida llega al corte entre oleadas. Antes se quedaban quietos, morían en la
primera oleada y todo el flujo de tienda/revivir quedaba sin probar.

Lo que hay que leer en las trazas:

- `sim` y `puppets`: los dos lados coinciden en cuántos enemigos hay y difieren
  en quién los posee.
- `money`: se mueve del lado que disparó. Si el host cobra los kills del cliente,
  la atribución se rompió.
- `shop`: ambos entran al corte juntos y salen en el mismo tick.
- `downed`: vuelve a `false` al abrir la tienda. Eso es el revive.

## Jugar desde casas distintas

Lo que el juego abre es un socket ENet en el puerto 27015, y la IP que muestra el
lobby es la de tu red local. Eso alcanza para dos personas en la misma casa y no
alcanza para nada más: desde otra casa esa IP no es alcanzable, y el intento
termina en "El host no respondió" sin decir por qué. Es exactamente lo que pasó
en el playtest.

La forma barata de arreglarlo **no toca el juego**: una VPN de malla hace que las
dos máquinas se vean como si estuvieran en la misma red, y a partir de ahí todo
lo de arriba funciona sin cambiar una línea.

### Con Tailscale (gratis para uso personal)

1. Los dos instalan Tailscale (`tailscale.com/download`) e inician sesión.
2. Uno invita al otro a su tailnet (en la consola web, *Users → Invite*). Tienen
   que estar en la misma tailnet o no se ven.
3. El host abre la partida en el lobby de coop. La fila de IP va a decir
   **TU IP (VPN)** y mostrar una dirección `100.x.x.x`: esa es la que funciona
   desde otra casa. Si dice **TU IP (LAN)**, Tailscale no está corriendo.
4. El otro pega esa IP en DIRECCION y entra.

El firewall de Windows puede seguir molestando: si el cliente no entra, dejale
pasar `Mayhem.exe`. ZeroTier funciona igual y reparte IPs del mismo rango, así
que el juego también las reconoce.

Latencia: Tailscale conecta directo entre las dos máquinas cuando puede, así que
el ping es prácticamente el de la conexión entre ustedes. Cuando no puede, cae a
un relay y suma bastante.

### Por qué no está resuelto adentro del juego

Se puede, y el código está listo para eso: `NetworkManager` es el único archivo
que toca ENet, así que cambiar el transporte es tocar ese archivo y nada más. Las
dos opciones reales:

- **Steam P2P** (`SteamMultiplayerPeer`): sin configuración para el jugador,
  relay incluido, invitaciones nativas. Cuesta los USD 100 de Steamworks y que el
  juego salga en Steam. Es el candidato obvio si eso pasa.
- **Hole punching con servidor de encuentro** (Noray/netfox): conserva ENet y no
  depende de Steam, pero hay que mantener un VPS y no cubre NAT simétrico sin
  sumarle un relay.

Ninguna de las dos se hizo todavía a propósito: primero conviene jugar con ping
real y ver qué hay que ajustar. Lo que casi seguro va a pedir tuning es
`EnemyReplicator.SEND_RATE` (20/s) y `INTERP_SPEED`, elegidos sin latencia de por
medio.

## Lo que falta

- **Sin reconexión ni migración de host.** Si se cae el host, la partida
  termina: el cliente ve un panel de fin de sesión y vuelve al menú o arranca
  una corrida solo. Que otro peer tome la posta significa mover la simulación
  entera de máquina a mitad de oleada, y eso es un proyecto aparte, no un
  pendiente.
- **Dos líneas del Host siguen siendo personales a propósito**: el aviso de vida
  baja (habla de *tu* vida) y el comentario de compra (en el corte compran los
  cuatro a la vez; difundirlo serían cuatro voces encimadas).
- **Sin anti-cheat**, y a propósito: el movimiento es autoritativo del cliente y
  esto es un juego para amigos. El único límite es `MAX_REPORTED_DAMAGE`, que
  existe para que un valor corrupto no borre una oleada entera.
