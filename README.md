# Galactic Surge

Shooter espacial vertical 2D desarrollado en **Godot 4.7.2** (GDScript) como proyecto del curso universitario DDJI2.

Oleadas de naves enemigas bajan desde la parte superior de la pantalla en formaciones. Dispara hacia arriba, esquivá los proyectiles enemigos, recogé power-ups y derrotá al jefe final.

## Características

- Movimiento horizontal y disparo con cadencia controlada y sobrecalentamiento.
- Oleadas con dificultad creciente y enemigos con comportamientos distintos.
- Arsenal con armas seleccionables: Blaster, Misil y Láser.
- Power-ups y botín que caen al destruir enemigos.
- Jefe final de varias fases, con enfurecimiento al bajar su vida.
- Modo cooperativo local (dos jugadores en el mismo equipo).
- Multijugador en red (LAN) mediante ENet: un jugador hospeda y el otro se une por IP y puerto.
- Remapeo de teclas desde el menú de ajustes.
- Gráficos vectoriales dibujados por código y tema visual neón retro-arcade.

## Controles

| Acción | Tecla |
|---|---|
| Mover a la izquierda | `A` (J2: `←`) |
| Mover a la derecha | `D` (J2: `→`) |
| Disparar | `Espacio` (J2: `Shift`) |
| Pausa | `Escape` |
| Seleccionar arma 1-4 | `1` `2` `3` `4` |
| Arma anterior / siguiente | `Q` / `E` |

Todas las teclas pueden cambiarse en **Ajustes > Controles**.

## Requisitos

- [Godot 4.7.2](https://godotengine.org/download/) (la versión del proyecto está fijada en `project.godot`).
- Renderer **GL Compatibility** (configurado en el proyecto).

## Cómo ejecutar

1. Clonar el repositorio:
   ```bash
   git clone https://github.com/Frank-0511/galactic-surge.git
   ```
2. Abrir Godot 4.7.2 y elegir **Importar**, luego seleccionar el archivo `project.godot` de la carpeta clonada.
3. Presionar **Play** (la escena principal es `features/main/main.tscn`).

## Multijugador en red

- **Hospedar:** en el panel de red del menú principal, elegir **Host** e indicar un puerto entre 1024 y 65535.
- **Unirse:** en el mismo panel, elegir **Join**, ingresar la IP del anfitrión y el mismo puerto.

Los puertos reservados y fuera de rango son rechazados antes de abrir la conexión.

Para jugar en LAN: ambos equipos en la misma red, el anfitrión inicia **Host** (por ejemplo, puerto 7777), comparte su IP local y el segundo jugador usa **Join** con esa IP y el mismo puerto. El anfitrión controla a J1 y el cliente a J2; el host decide la partida y sincroniza el resto. Si el cliente se desconecta, la partida del host continúa en solitario; si el host se pierde, el cliente vuelve al menú con un aviso. El firewall del anfitrión debe permitir UDP en ese puerto. Sin red, el botón **Coop local** permite jugar de a dos en el mismo teclado.

## Versión web

Jugable en el navegador, sin instalar nada: https://frank0511.itch.io/galactic-surge (un jugador y coop local; el panel de red y el botón Salir no se muestran en web; en pantallas táctiles aparecen joystick virtual, disparo y pausa).

Para exportar el build HTML5 por tu cuenta, usar el preset **Web** de *Proyecto > Exportar* en el editor. El navegador necesita servir el build por HTTP; no funciona abriendo `index.html` directamente desde el disco.

## Estructura del proyecto

```
game/
├── project.godot   # Configuración del motor, entrada y tema
├── core/           # Utilidades transversales: math, layout, settings, session, physics
├── features/       # Una carpeta por feature: escenas, scripts y recursos juntos
├── tests/          # Contratos headless agrupados por dominio
├── assets/         # Audio, fuentes, shaders y tema visual
└── addons/         # Addons de terceros
```

Convenciones de código: nombres en inglés, archivos y funciones en `snake_case`, nodos y clases en `PascalCase`, señales en tiempo pasado (`enemy_died`).

## Tests

La suite de contratos corre en modo headless desde Godot y valida el comportamiento por dominio (balance, enemigos, oleadas, armas, UI, red y coop). Los scripts viven en `tests/`. Ejecutar una suite:

```bash
godot --headless --path game --script res://tests/<dominio>/<suite>.gd
```

Cada suite termina con código 0 si pasa. `tests/net/etapa_20_two_process_test.gd` levanta un host y un cliente reales sobre ENet en localhost (puerto 7791).

## Créditos de audio

- Música: *8-bit Epic Space Shooter Music* por HydroGene, licencia CC0.
- Efectos: *8-Bit Sound Effect Pack Vol. 001* por @Shades, https://soundcloud.com/noshades

## Licencia

Todos los derechos reservados. Ver [LICENSE](LICENSE).
