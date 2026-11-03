---
tags: [mayhem, playtest, guia]
estado: guia
actualizado: 2026-11-03
---

# Protocolo de playtest

Cómo se corre una sesión de prueba (G3 y G5 del [ciclo de release](ESTADO.md#7-ciclo-de-release))
y qué se mira después. El objetivo de la primera tanda no es "¿está balanceado?"
sino **"¿el jugador ve y entiende lo que el juego le pide?"**: el juego tiene
muchas capas encima de la pelea (tienda, raras, rating, reglas, contratos,
pedidos, estilo, gadgets) y ninguna se jugó con alguien que no lo conozca.

## Antes

- **Jugadores**: 5 a 8 por tanda, que no hayan visto el juego. Uno que ya lo
  jugó no sirve para la pregunta de legibilidad: ya sabe lo que tiene que mirar.
- **Build** exportado, no el editor (el editor corre con la consola de dev y otra
  performance). Anotar la versión (`application/config/version`).
- **Capas**: decidir de antemano qué se apaga en cada tanda (ver abajo). Mitad
  de los jugadores con todo, mitad con la capa apagada, si se quiere comparar.
- **Borrar `user://runs/`** de la máquina antes de empezar, o anotar la hora: el
  resumen lee la carpeta entera.
- **Ficha por jugador**: hora de inicio, capas, hardware, si usa mouse o joystick.

## Capas del show

`data/playtest/playtest_layers.tres` dice qué va encendido (todo, por defecto).
En un build exportado se pisa por línea de comandos, sin re-exportar:

```
Mayhem.exe -- --layers=-rating              # sin rating
Mayhem.exe -- --layers=-rules,-contracts    # sin nada de lo que ofrece el Host
Mayhem.exe -- --layers=none                 # la pelea pelada
```

Capas: `rating`, `rules`, `contracts`, `crowd_requests`. `-capa` apaga, `+capa`
enciende, `none` y `all` las cuatro. En un build de debug, la consola tiene
`layers` para verlas y cambiarlas. El log de cada run anota las apagadas
(`layers_off`), así que dos tandas no se mezclan en el resumen.

Qué se pregunta con cada una: si con la capa apagada las runs duran lo mismo, se
compra lo mismo y el jugador no la extraña en la entrevista, la capa no está
pagando lo que cuesta en atención.

## Durante

- **Observar en silencio.** No explicar, no ayudar, no contestar "¿qué hace
  esto?" (anotar la pregunta: es un dato). Solo intervenir si el jugador está
  trabado más de dos minutos en algo que no es el juego (un menú, un bug).
- **No pedir que piense en voz alta mientras pelea**: en un juego de acción le
  cambia los tiempos de reacción y el dato sale torcido. Lo que haya que
  preguntar, después.
- **Anotar lo que se ve, no lo que se interpreta**: "en la tienda leyó dos
  tarjetas y apretó el reloj" sirve; "se aburrió en la tienda" no.
- Momentos que vale la pena anotar con la hora:
  - primera vez que usa el gancho, el slide y la caída rápida;
  - primera vez que levanta un gadget, y si lo usa;
  - qué hace en la primera tienda y cuánto tarda;
  - si mira el rating (los ojos se van arriba a la derecha) o el cartel de un
    pedido del público;
  - cada muerte: qué estaba haciendo, si vio venir el golpe.
- Una run completa o 25 minutos, lo que llegue antes. Dos runs si hay tiempo: la
  segunda dice qué aprendió de la primera.

## Después: entrevista (5 minutos)

Preguntas abiertas primero, escalas después, para no darle las palabras.

1. Contame qué pasó en la run, como se lo contarías a un amigo.
2. ¿Qué te mató la última vez? ¿Lo viste venir?
3. ¿Qué compraste y por qué? ¿Hubo algo que no entendiste en la tienda?
4. ¿Qué era la barra de arriba a la derecha? (el rating; si no sabe, es un dato)
5. ¿Qué te pedía el público? ¿Lo intentaste?
6. ¿Qué cambiarías?

Escalas del 1 al 5: ¿qué tan divertido? ¿qué tan difícil? ¿qué tan claro era qué
hacer? ¿jugarías otra run?

**No preguntar "¿te gustó?"**: la respuesta es casi siempre sí y no dice nada. Lo
que la gente dice en una encuesta tiende a ser lo superficial o lo que cree que
uno quiere oír; lo que hizo frente a la pantalla es el dato.

## Los logs

Cada run escribe un JSON en `user://runs/` (`RunLogger`, formato 4). En Windows:
`%APPDATA%\Godot\app_userdata\Mayhem\runs\`. Juntar las carpetas de todas las
máquinas en una y correr:

```
python tools/summarize_runs.py <carpeta>
python tools/summarize_runs.py <carpeta> --by-layers     # una tabla por combinación de capas
```

Lo que contesta, y dónde está en el log:

| Pregunta | Campo |
|---|---|
| ¿En qué ola y de qué se muere? | `died_in_wave`, `killed_by`, `damage_by_cause` |
| ¿La ola es un pico o es la acumulación de las anteriores? | `waves[].damage_taken` contra `par_time` y `duration` |
| ¿Se usa la movilidad o se juega parado? | `waves[].movement` (`slide_s`, `air_s`, `still_s`, `avg_speed`, `grapples`, `fast_falls`) |
| ¿Se usan los gadgets? | `waves[].gadgets_used` |
| ¿La tienda se lee o se saltea? | `waves[].shop_seconds` (el tiempo en la tienda **antes** de esa ola) |
| ¿Se firman contratos? ¿Se cumplen los pedidos? | `waves[].contract`, `contract_paid`, `crowd_requests` |
| ¿El rating se mueve? | `waves[].rating_avg`, `rating_peak` |
| ¿Se retrocede disparando? | `waves[].retreat_avg`, `retreat_peak` |

Un sistema que no aparece en los logs —un contrato que nadie firma, un pedido que
nadie cumple, el gancho que se usa dos veces por run— es un sistema que el
jugador no vio. Eso se arregla con legibilidad antes que con números.

## Qué hacer con lo que vuelve

- Lo que se repite en tres o más jugadores es un hallazgo; lo de uno, una nota.
- Cada hallazgo va a [ESTADO.md](ESTADO.md) con su dato ("4 de 6 no firmaron
  ningún contrato; 3 no sabían qué era"), no como opinión.
- El balance (G4) se hace después y con los logs en la mano: los números que
  esperan playtest están listados en ESTADO, R3.
