# Micro y preview — autoridad local 0.4

**Estado 0.4, 2026-09-14: autoridad e integración implementadas y exportadas.**
Coordinación completó `All` 196/196: matriz física 1522/1522, HUD 682/682,
cámara 8339/8339, integración y entradas nativas, además de fuente/EXE con GPU.
El arranque normal y las veinte capturas del artefacto están comprobados.
Vasquez cerró la revisión de fuentes, incluido el último tooling, y concedió
aprobación estructural al paquete. El helper de metadatos posterior pasó 247/247;
no se atribuyen esas comprobaciones al All, que ejecutó su versión de 235.
Los resultados focalizados del 10 de septiembre se conservan abajo como historia
del componente, no como sustituto del cierre global enlazado desde TOOLING.
Los resultados 0.1–0.3 conservados más abajo son históricos, no resultados 0.4.
Contrato vinculante completo: `docs\DEVELOPMENT_PLAN.md`, §4.3.

Entrenamiento micro de cuatro atletas y
preview experimental de diez cuerpos independientes, con un único foco humano
intercambiable entre compañeros HOME mediante cambio sin balón o pase efectivo.
El módulo de simulación no incluye escena principal, cámara, recogida de input,
HUD, modelos, animación ni sonido. La preview está autorizada para estudiar escala;
no acredita G3, los gates humanos de sensación/arte o rendimiento. No implementa
reglamento completo, sustituciones, XP, guardado, dificultad comercial ni red.

## Geometría y propiedad

`game\match\simulation\match_simulation.gd` es un `Node3D`. Añadirlo al árbol con
transformación global identidad; no mover, escalar ni reparentar sus cuerpos.
Posee un **World3D físico privado**: la presentación consume snapshots y no añade
colisiones duplicadas. Dos autoridades pueden coexistir sin compartir colisiones.
Los nodos físicos no son puntos de extensión de UI o animación.

Todas las unidades son **metros/segundos**; origen en el centro del suelo,
**X longitudinal**, **Z transversal**, **Y arriba**. `Vector2` de comandos significa
`(X, Z)`, no coordenadas de pantalla. Modelos de atletas: origen en los pies,
frente local `-Z`; usar `position` y `facing_yaw` del snapshot.

| Elemento | Colisión implementada |
|---|---|
| Pista | Líneas de juego X ±20, Z ±10: 40 × 20 m |
| Suelo | Caja 48 × 0,4 × 28 m, centro Y −0,2; superficie Y 0, con margen exterior |
| Balón | Esfera de radio 0,105 m, masa 0,43 kg; snapshot en su centro |
| Atletas | Cápsula radio 0,28 m, altura total 1,75 m; centro Y 0,875 respecto a pies |
| Aberturas | Planos X ±20; interior Z ±1,5; suelo Y 0, cara inferior del larguero Y 2 |
| Postes | Sección cuadrada 0,08 × 0,08 m; centros Z ±1,54, Y 1,04; altura 2,08 |
| Largueros | Centro Y 2,04; sección 0,08 × 0,08; longitud transversal 3,16 |
| Redes físicas | Cajas de 0,06 m, no tela simulada; fondo X ±21,5, laterales Z ±1,61, techo Y 2,08 |

Las constantes y máscaras están en `MatchTuning`: mundo `1`, atletas `2`, balón
`4`. No hay paredes de colisión en las bandas. El desplazamiento ordinario limita
X ±19,65/Z ±9,65; la colocación reglada puede situar al sacador fuera de la banda o
al portero sobre la línea de gol. Regresan andando, sin un salto al límite interior.
El área no añade un collider: reglas y dibujo comparten `PENALTY_RADIUS=6`,
`GOAL_POST_CENTER_Z=1.54`, `GOAL_POST_OUTER_Z=1.58` y
`PENALTY_STRAIGHT_LENGTH=3.16`; no es un rectángulo ni agranda la portería.

| ID estable | Equipo | Rol | Ataque | Spawn micro |
|---|---|---|---|---|
| `0 / HUMAN_ID` | `0 / HOME` | Campo, foco inicial | +X | (−2, 0, 0) |
| `1 / RIVAL_ID` | `1 / AWAY` | Campo IA | −X | (4, 0, 1,5) |
| `2 / HOME_KEEPER_ID` | HOME | Portero, seleccionable | +X | (−18,5, 0, 0) |
| `3 / AWAY_KEEPER_ID` | AWAY | Portero IA | −X | (18,5, 0, 0) |

`MatchSetup.Mode` define **`MICRO_1V1 = 0`** y **`PREVIEW_5V5 = 1`**.
`MatchSetup.new()` conserva el micro: intención IA `[0, 1, 2, 3]` y generadores
efectivos iniciales `[1, 2, 3]`.
`MatchSetup.preview_5v5()` devuelve el preset explícito de diez: conserva 0/2/3,
sitúa `1` en `(2, 0, 0)` y añade:

| Campo HOME, mirando +X | Campo AWAY, mirando −X |
|---|---|
| `4: (−8, 0, −6)` | `5: (8, 0, −6)` |
| `6: (−8, 0, 6)` | `7: (8, 0, 6)` |
| `8: (−13, 0, 0)` | `9: (13, 0, 0)` |

En preview solo 2/3 son porteros. El foco inicial es 0; la intención IA incluye
`[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]` y la IA efectiva inicial excluye 0.
El foco puede pasar a 2/4/6/8; en micro, 0 ↔ 2. `HUMAN_ID` conserva una
identidad/default compatible, **no indica el actor controlado vigente**.
El balón empieza en `(−1,45, 0,12, 0)`, sin
velocidad. Se conserva toda la escala física. `ACTOR_IDS` sigue significando los
cuatro IDs micro por compatibilidad; los consumidores enumeran `snapshot.actors`,
no ese catálogo. El modo nunca se deduce de la longitud de los diccionarios.

`MatchSetup.for_exercise(mode, exercise)` publica el catálogo fijo de doce valores:
`FREE_PLAY=0`, `KICK_IN=1`, los cuatro córners `2..5`, `GOAL_CLEARANCE=6`,
`DRIBBLE_CUT=7`, `DRIBBLE_PACE_CHANGE=8`, `DIRECT_FREE_KICK=9`, `PENALTY_6M=10`
y `ACCUMULATED_FREE_KICK=11`. Se copia/valida `training_exercise`.
`attack_direction(team_id) -> Vector3` deriva la orientación: los córners de
extremo negativo espejan X, atletas y frentes; no existe selector libre de extremos.
El ejercicio de sexta declara acumuladas iniciales `(0,6)`, sin crear seis faltas.

## API estable para integración

Precargar scripts por ruta `res://match/simulation/...`; no se necesita abrir el
editor para registrar sus `class_name`.

| Método de `MatchSimulation` | Contrato |
|---|---|
| `start(setup: MatchSetup = null) -> Error` | Valida y reinicia sesión. Juego libre/regates entran en `PLAYING`; ejercicios de saque recorren `RESTART_PAUSE/STOPPED`. `null` conserva micro libre |
| `reset(setup: MatchSetup = null) -> Error` | Mismas reglas de modo; reinicia foco a 0, marcador, reloj, secuencias, velocidades, posesión, contactos, cooldowns y decisiones; queda `READY`, físicamente inmóvil |
| `submit_human_command(command: PlayerCommand) -> Error` | Entrada de integración; solo admite `snapshot.selected_actor_id`, otro ID devuelve `ERR_UNAUTHORIZED` |
| `submit_command(command: PlayerCommand) -> Error` | Entrada pública para drills; la IA comparte aceptación/validación interna durante el tick, no elude reglas físicas |
| `set_paused(paused: bool) -> Error` | Idempotente; congela física, atletas, IA, reloj y ticks; restaura fase y vuelo al continuar |
| `set_ai_actor_ids(ids: Array[int]) -> Error` | Sustituye la intención IA completa, incluido el seleccionado si se desea; copia/ordena sin reiniciar ni cambiar foco |
| `get_snapshot() -> MatchSnapshot` | Copia desacoplada; modificarla no modifica el partido |
| `query_human_launch(request: PlayerCommand) -> MatchLaunch.Solution` | Consulta pura del seleccionado: no consume secuencia, cambia `last_error`, emite eventos ni crea otro mundo; preparación puede devolver `OK` con `executable=false` |

`PlayerCommand.new(actor_id, sequence)`:

- `sequence`: entero estrictamente creciente por actor, de 0 a 2147483647.
  `start/reset` y el saque canónico posterior a gol reinician el contador a −1.
  Bandas, córners, meta y faltas **conservan** secuencias, incluso al recolocar.
  El cambio de foco **no** lo reinicia: el nuevo humano continúa desde
  `actor(selected_actor_id).last_command_sequence + 1`, incluida su última IA.
- `move`, `aim`: vectores finitos de longitud ≤1. `SHOOT` neutro usa orientación;
  el pase/cambio neutro usa el compañero más cercano según las reglas siguientes.
  `sprint`, `close_control`: booleanos; control cercano prevalece sobre sprint.
- `action`: **una** de `NONE=0`, `PASS=1`, `SHOOT=2`, `TACKLE=3`,
  `SWITCH_TEAMMATE=4`, **`DRIBBLE=5`, `KEEPER_THROW=6`,
  `CHOOSE_RESTART_SPOT=7`**. La integración emite el
  tiro al soltar la carga; sin posesión, el botón contextual emite `TACKLE`, no ambos.
  El botón de pase emite `SWITCH_TEAMMATE` cuando el seleccionado no posee el balón,
  incluso si otro compañero lo posee. No se transforma un cambio tardío en pase.
- `shot_charge`: 0–1, transforma la potencia en 9–28 m/s por defecto.
  `shot_lift`: 0–1 opcional, componente vertical hasta 6 m/s dentro de esa velocidad.
  La recogida/normalización del tiempo mantenido pertenece al adaptador de input.
- `target_actor_id`: −1 o compañero distinto para `PASS`/`KEEPER_THROW`; los demás
  requieren −1. `restart_spot_choice` es `DEFAULT`, `TEN_METRE` u `OFFENCE_SPOT`,
  y solo es significativo con `CHOOSE_RESTART_SPOT`. Pase neutro sin receptor explícito: compañero más cercano **al
  controlado**, por distancia planar/ID; apunta físicamente hacia él, aunque quede
  detrás del frente. Pase con `aim`: cono de `pass_assist_degrees` (35° por defecto)
  desde **el balón**, por menor ángulo/distancia/ID. Un receptor explícito no se
  sustituye por otro ni fuerza giro fuera del cono cuando hay `aim`. Sin receptor
  efectivo, el pase es libre, el evento lleva −1 y no transfiere foco.

HOME no seleccionado no puede finalizar mediante `submit_command`: equipo y foco
vigentes deciden la guarda, no una marca «comando IA». Se revalidan tiro y pase sin
receptor, conducción y control dirigidos a la boca de gol. Se mantienen tiros del
humano y AWAY; no se anulan goles físicos accidentales a posteriori.

Enviar intención continua a cada tick, sin reutilizar secuencias. Una acción
aceptada se conserva aunque lleguen movimientos nuevos antes del siguiente tick;
otra acción pendiente devuelve `ERR_BUSY`. Solo hay un hueco por actor, no una cola
ilimitada. Movimiento sin renovar caduca a 0,25 s y frena. Las acciones físicas
tienen cooldown y se comprueban de nuevo en el instante de contacto; cambiar foco
sin balón no tiene cooldown físico.

Las negativas devuelven un `Error` concreto y rellenan `last_error`; la señal
`command_rejected(actor_id, code, message)` permite diagnosticarlas sin silenciarlas.
Un input/setup inválido no altera parcialmente el partido. **Todas** las entradas
públicas mutadoras, incluidos ambos métodos de comandos, devuelven `ERR_BUSY`
durante tick/evento o un callback de rechazo. Leer snapshots sí está permitido;
las mutaciones se difieren. Un rechazo anidado devuelve su error sin reemitir
`command_rejected` ni sobrescribir el mensaje exterior, evitando recursión.

El snapshot expone `mode: MatchSetup.Mode`, **`selected_actor_id: int`**,
**`ai_intent_actor_ids: Array[int]`** (preferencia completa) y
`ai_actor_ids: Array[int]` (intención menos seleccionado). Ambas listas son
ordenadas y desacopladas. Exactamente el actor HOME seleccionado tiene
`ActorSnapshot.human_controlled = true`. Expone además `tick`, `phase`,
`resume_phase`, `score: Vector2i` (HOME, AWAY),
`seconds_remaining`, `phase_seconds_remaining`, `ball_position`, `ball_velocity`,
`ball_rotation: Quaternion`, `ball_angular_velocity`, `ball_owner_id` (−1 libre),
`last_touch_actor_id` y `actors`. Cada actor incluye ID/equipo/rol/control humano,
dirección de ataque, spawn, posición, velocidad, frente, yaw, control cercano,
cooldown, última secuencia y tick de comando. `actor(id)` devuelve null si no existe.
Se añaden `restart` no nulo, `accumulated_fouls`, `human_control_context`,
`human_allowed_actions`, `selected_can_move`, historial `last_touch_tick` y
`last_pass_*`, `period_state`, `extended_restart_id`, `extended_kick_event_id` y
`training_exercise`. Cada actor publica `ball_contact_reachable`, `ball_in_hands`
y `gesture_kind/started_tick/duration_ticks/direction/contact_position`.
`copy()` desacopla también DTOs anidados y arrays de acciones/actores.

**Corrección G10:** `MatchRuleTypes.RestartState.launch_contact_id: int = -1`
identifica el episodio del golpeo que puso ese saque en juego. Se asigna antes de
registrar el contacto/emitir `PASS` o `SHOT`, viaja en `snapshot.restart` y
`event.restart`, y lo conserva `RestartState.copy()`. Una nueva reanudación lo
restablece a −1. Los serializers de consumidores deben incluir este entero;
no se deriva de `stage_started_tick`, `last_pass_tick` ni `last_touch_tick`.

Señales tipadas con `MatchEvent`:
`goal_scored`, `pass_made`, `shot_taken`, `save_made`, `restarted`, `match_ended`,
`ball_contact`; `event_raised` incluye además recepción, resultado de tackle y
`MatchEvent.Kind.FOCUS_CHANGED=9`, **`RESTART_CHANGED=10`, `DRIBBLE=11`, `FOUL=12`**.
No hay setter público de selección ni señal
de foco adicional: se usa este evento tipado.
El evento trae ID monotónico por arranque, tick, tipo, actor/equipo/receptor,
posición/velocidad, marcador, éxito, motivo y carga. La presentación escucha eventos
y snapshots; **no decide** contactos, goles o finalización.
Los eventos incluyen copia de `restart`, `launch_kind`, `gesture_kind`,
`foul_verdict`, `contact_id` y `contact_point`. Un lanzamiento de manos es
`PASS` con `launch_kind=KEEPER_THROW`, no otro pase inventado por presentación.

### Cambio sin balón y pase con foco

`SWITCH_TEAMMATE` busca compañeros HOME, incluido el portero. Neutro: distancia
planar al controlado/ID. Con `aim`: ángulo/distancia/ID dentro del mismo cono de
35°, pero su origen es **el actor**, no el balón. No tiene radio máximo artificial.
Sin candidato devuelve `ERR_UNAVAILABLE` sin aceptar movimiento ni secuencia.
Si adquiere posesión antes de resolver, rechaza la acción sin pase ni cambio.

Una patada `PASS` efectiva del seleccionado con receptor HOME emite **PASS antes
de FOCUS_CHANGED**, en el mismo tick. El evento de foco lleva `actor_id` antiguo,
`target_actor_id` nuevo y motivo `&"pass"` o `&"off_ball_switch"`. Todos los
observadores, incluido el de PASS, ya leen selección/control humano/IA efectiva
actualizados atómicamente. No transfiere al encolar, perder contacto, rechazar por
cooldown, pasar libre, recibir/interceptar el balón ni por pases de IA.

Se resuelve primero la acción pendiente del seleccionado, antes de cualquier
otro ID. Al transferir se limpian movimiento/apuntado/flags y acción pendiente de
antiguo y nuevo, también si el receptor tenía una acción IA con ID inferior.
No reinicia secuencias, cooldowns, posiciones, velocidades o posesión; la patada
normal deja el balón libre. El antiguo frena con comando neutro y recupera IA
solo si figuraba en la intención. **Foco no garantiza recepción ni teletransporta
el balón**: siguen vigentes orientación, alcance, velocidad y colisiones.

Pausa explícita y celebración conservan foco; el saque canónico tras gol vuelve
a 0. Los saques localizados HOME ceden foco al sacador con `restart_taker`;
los AWAY nunca toman el foco humano. `FINISHED` conserva foco sin nuevas acciones.
Start/reset vuelven al default antes de adjudicar el ejercicio. El portero seleccionado no
genera comandos IA ni devuelve pases automáticamente: recibe/bloquea físicamente
con sus reglas existentes y acepta comandos humanos normales. Al perder foco
recupera IA solo según intención. Meta usa el nuevo lanzamiento de manos; no se
añaden estiradas o un sistema completo de control especializado de portero.

### Cambios de IA durante el entrenamiento

**Cambio de API intencional:** `MatchSetup.ai_actor_ids` y `set_ai_actor_ids`
representan ahora intención completa, no el conjunto efectivo. Admiten 0 y el
seleccionado. No reconstruir intención desde `snapshot.ai_actor_ids`.

`set_ai_actor_ids` acepta todos los estados inicializados, incluidos `READY`,
`PAUSED`, pausas de gol/fuera y `FINISHED`. Devuelve `ERR_UNCONFIGURED` antes de
inicializar, `ERR_BUSY` durante tick/entrega/rechazo y `ERR_INVALID_PARAMETER`
por duplicados o ID ausente en el modo. Los rechazos son atómicos,
con `last_error` y `command_rejected(-1, code, message)`.

Vacío apaga todos los generadores. Un cambio no retira cuerpos ni colisiones,
no altera balón, marcador, reloj, fase, velocidades, secuencias aceptadas o
cooldowns. Neutraliza movimiento, apuntado y acción pendiente de los actores
**no seleccionados** cuyo generador cambia; los deshabilitados **frenan normalmente**, no se congelan ni
teletransportan. Los habilitados deciden con una secuencia nueva. Repetir el mismo
conjunto es idempotente y no borra acciones de actores intactos. Cambiar únicamente
la preferencia latente del seleccionado no cancela su movimiento ni acción humana.
Cada subconjunto es exacto: un handoff no añade, elimina ni infiere preferencias.
`submit_command` sigue admitiendo drills para actores sin IA: se apaga la decisión
autónoma, no el contacto, recepción o posesión física.

Los grupos que el consumidor deriva de equipo/rol, **sin excluir al seleccionado**,
son: rivales `[1, 3]` / `[1, 3, 5, 7, 9]`, campos locales `[0]` / `[0, 4, 6, 8]` y
portero local `[2]`, respectivamente micro/preview. La intención permite
también grupos parciales, sin añadir una segunda autoridad en la UI.

Gol, salidas y faltas conservan modo e intención; el efectivo se recalcula según
el foco confirmado, sin inferir preferencias. Para reiniciar mediante
`start/reset(setup)`, el host mantiene su propia copia del setup y actualiza
`setup.ai_actor_ids` desde **`snapshot.ai_intent_actor_ids`, solo tras `OK`**. Pasar `null` vuelve a
micro; aplicar una factoría canónica vuelve deliberadamente a los defaults del
modo. Ningún ajuste se guarda en disco.

### Reanudaciones, contactos y periodo 0.4

`MatchRuleTypes` contiene únicamente enums/DTOs; `MatchRules` de Hudson es puro.
La autoridad obtiene cruce/contactos, pide decisión/colocación/acciones/restricciones
y es la única que mueve cuerpos, cuenta faltas, cambia fases o concede goles.
`first_crossing.goal_team_id=-1` no descarta gol: todo primer borde detectado pasa
a `boundary_decision`, que conoce la orientación del snapshot. El core asigna
los IDs definitivos de reanudación. Una decisión `NONE` con motivo terminal
`extended_kick_expired` finaliza sin inventar otro saque.
`MatchLaunch.resolve(state, command, tuning)` se usa tanto para consulta como para
la patada/lanzamiento: origen real, receptor asistido, vector, velocidad y potencia.
La ejecución revalida el estado nuevo, no aplica una predicción antigua.

- `RESTART_PAUSE` contiene `STOPPED → PLACEMENT → READY → IN_PLAY`.
  Colocación mínima de **60 ticks**, sin ACK de cámara; solo sacador y atletas
  que incumplen posiciones. No cambia spawns ni secuencias. Foco HOME al sacador;
  AWAY conserva el humano anterior. Propio listo permite apuntar sin caminar;
  rival listo permite defensa/cambio, con desplazamiento restringido por reglas.
- Plazo `ready_tick + 240`, comprobado **antes** de resolver acciones. Penalti de
  6 m usa −1: sin cuatro segundos. Elección legal de sexta no renueva plazo ni
  inicia otra colocación cronometrada. Vencimientos se adjudican por tipo mediante
  `expiry_decision`, incluidos indirectos; no vuelven al centro.
- Cuando reglas recorta un desplazamiento, el adaptador físico conserva además
  los 2 mm de tolerancia de penetración ya configurados en Jolt. No relaja los
  5 m: evita gastar la tolerancia reglamentaria antes de la integración float32
  y dejar un defensor microscópicamente fuera de posición, bloqueando el saque.
- Al ejecutar se reanuda el rigid body **antes** de aplicar velocidad. Orden:
  `PASS → FOCUS_CHANGED → RESTART_CHANGED(taken)`, cuando hay receptor efectivo.
  El snapshot ya es atómico. Meta mantiene un anclaje autoritativo de manos
  (`keeper_hand_height/forward`), no un hueso visual; entra en juego al liberar
  dentro del área, sin esperar a que salga de ella.
- En meta, colocar físicamente el balón en manos asigna también `ball_owner_id`
  al portero desde **PLACEMENT**, antes de publicar `RESTART_CHANGED(placement)`.
  `actor.ball_in_hands` implica siempre dueño coincidente en el snapshot actual,
  incluida pausa. STOPPED todavía no atribuye manos/posesión; READY conserva
  al dueño, y liberar/reset limpia ese contexto. La colocación no registra
  último toque, pase ni parada. Presentación mantiene su guardia `hands_owner`.
- Último toque procede de contacto nativo del balón o de un golpe/control físico
  aplicado, no de asignar posesión por cercanía. Se identifican episodios; un
  callback repetido no es otro toque. Poste/suelo no levantan restricciones de
  gol directo. El lugar del contacto CCD se ordena respecto al primer cruce.
  Los contactos atleta–atleta se obtienen de `move_and_slide`, con normal,
  velocidades anteriores al impacto y ventana de entrada.
- G10 distingue identidad, no una gracia de un tick: un contacto nuevo del
  sacador sin otro jugador produce indirecto aunque llegue en el mismo tick
  o en t+1. Solo `contact_id == restart.launch_contact_id` representa el episodio
  original. En extensión, un episodio nuevo termina sin abrir otro saque.
  El collector enlaza el episodio original mediante la esfera y la cápsula
  reales, con consulta de intersección en su espacio nativo y la tolerancia
  de penetración existente. El enlace se retira al separarse las formas, no al
  vencer un plazo; una nueva época nativa obtiene otra identidad. Las muestras
  repetidas del mismo episodio conservan deduplicación. La protección física
  CCD de salida de cápsula no se usa para eximir un contacto ya observado.
- Faltas cuentan únicamente cuando `RuleDecision.counts_as_accumulated_foul`.
  Penalti, indirecto y vencimiento no incrementan acumuladas. Persisten en
  gol/saques/pausa; solo otra sesión las reinicia, salvo semilla declarada del
  ejercicio. Las decisiones de contacto se deduplican.
- Periodo de 120 s efectivos. Solo penalti/sexta pendiente o todavía en desenlace
  puede usar `EXTENDED_KICK`, reloj cero e IDs estables. Parada/rebote del portero
  defensor no finaliza por sí solo; gol, fuera, detención física o toque posterior
  de otro atleta sí. No hay ataque adicional ni reposición ordinaria. Un
  lanzamiento ya detenido durante regulación no queda pendiente indefinidamente.
- `DRIBBLE`: enganche lateral o cambio de ritmo adelantado/neutro; atrás puro se
  rechaza. Impulso real, recuperación y cooldown; el balón queda disputable,
  incluso antes de que el ejecutante pueda recuperarlo. El gesto se publica
  desde el contacto autoritativo, sin usar animación como física.
  Para HOME no seleccionado, la autoridad comprueba además si la velocidad
  real desde el balón apunta a la boca de gol, incluida la inercia del enganche.
  Lo comprueba al aceptar y de nuevo al ejecutar: girar durante la espera no
  elude la política pasadora. Rechazar no libera posesión, impulso ni recuperación.
  Conserva los regates legales, los remates humanos/AWAY y los goles accidentales.

Tuning de faltas acordado: `foul_challenge_window_ticks=18` (entero 1–60),
`foul_min_closing_speed=0.8` (0.1–4.0 m/s) y
`foul_reckless_closing_speed=9.5` (2.0–20.0 m/s, estrictamente mayor que el mínimo).
Se exportan, validan y copian al iniciar; cambiar el recurso del caller no cambia
la sesión activa. La velocidad relativa sobre la normal usa las velocidades de
ambos atletas **antes** de sus desplazamientos y choques, no los ceros posteriores
al `slide` del ID menor. Ball-first exige un toque físico dentro de esa misma
ventana de desafío; ni posesión antigua ni roce ordinario fabrican una falta.
Los límites son escalares para aceptar exactamente el mínimo 0.1 sin redondearlo
al guardarlo en un `Vector2`.

Para ejecución:
`tackle_contact_window_ticks`, `dribble_*`, `keeper_hand_*`, `keeper_throw_*`,
`allied_goal_exclusion_*`, `extended_ball_stop_*`. Son parámetros validados de
heurística/contacto, **no cifras presentadas como normativa FIFA**.

## Física y simplificaciones deliberadas

- Balón `RigidBody3D`, CCD real de Jolt, gravedad, restitución, fricción de material
  y resistencia de rodadura. No se mueve por animación ni se teletransporta a un pie.
  Posesión es una etiqueta de contacto: recepción a ≤0,68 m, control por aceleración
  acotada y pérdida al superar 1,05 m o altura legal. Recepción frena brevemente con
  fuerza mayor; campo ≤12 m/s y portero ≤14 m/s. Una patada ignora únicamente su
  propio atleta durante el despeje del pie; otros cuerpos siguen colisionando.
- `MatchTuning` es un Resource validado, copiado al iniciar/reiniciar: velocidades,
  aceleraciones, frenada, control, tiros, pases, IA, reloj y pausas son ajustables.
  No hay cambios de balance a mitad del tick.
- El perfil nativo de creación reduce tolerancias de penetración/CCD de Jolt a la
  escala del balón y permite hasta 400 rad/s para rodadura real. Se aplica al crear
  **ese** espacio/cuerpos y se restauran inmediatamente los valores del proceso.
  No escribe `project.godot`, no llama a `ProjectSettings.save` y no cambia otros
  espacios ya creados. Los setters de tolerancia por espacio no están soportados
  por Jolt; no se sustituyen contactos por rebotes programados.
- Rival: recuperación, conducción, protección del lado de su portería y tiro.
  Porteros: colocación lateral, intercepción corta basada en velocidad actual,
  recogida cercana, parada corporal y devolución IA tras 0,6 s si no están
  seleccionados. Todos usan los mismos
  comandos/cooldowns; no hay teletransporte, lectura de inputs futuros, estiradas,
  red ni llamadas a modelos.
- En preview, cada equipo elige un perseguidor entre sus campos con generador
  habilitado por distancia al balón y después ID; nunca se automatiza al humano.
  Las decisiones de campos se coordinan en el mismo tick. Con posesión amiga,
  el resto apoya/cubre manteniendo carriles derivados de sus spawns, no persigue
  a su propio poseedor. Amenazas se buscan entre rivales; cada portero distribuye
  legalmente. La política HOME prioriza al humano y alternativas; la adjudicación
  y la ejecución no dependen de la elección visual de receptor.
- Gol: cruce barrido de la **esfera completa**, dentro de postes y bajo larguero;
  prevalece el primer borde cruzado. El extremo determina el equipo, incluso en
  propia puerta. `GOAL_PAUSE` bloquea acciones y reloj, pero deja el balón rebotar
  en la red; no vuelve a puntuar. Pausa explícita congela también ese vuelo y
  continuar restaura su velocidad lineal y angular, no solo la fase.
- Solo el gol mantiene el saque canónico con campo 0/1 del equipo que encajó,
  foco 0 y spawns del modo/orientación. Las salidas reales usan banda, córner o meta
  localizada. Los fixtures legados con balón inicialmente en el margen reciben
  una reanudación explícita, sin fabricar un gol o historial de toque inicial.
- En reset/saque, los cuerpos se recolocan como teletransporte físico antes de
  reactivar movimiento cinemático: no barren sus posiciones anteriores empujando
  el balón o desplazando otros atletas al empezar el nuevo drill.
- `FINISHED` se emite una vez, conserva foco y queda congelado sin reset terminal.
  Sin tarjetas, ventaja, regla completa de devolución/posesión del portero, descanso,
  sustituciones, recompensas ni almacenamiento. Repetibilidad local no es lockstep
  determinista entre máquinas.

`MatchSetup` permite drills reproducibles **solo mediante start/reset** para
composición y poses: exactamente las cuatro o diez posiciones/orientaciones del
modo explícito, IA válida para ese modo y posición/velocidades iniciales del balón.
`copy()` conserva y desacopla todos esos campos. Se validan finitud, límites,
solapamientos y colocación fuera de postes/red antes de destruir o crear cuerpos;
modo desconocido o diccionarios incoherentes devuelven `ERR_INVALID_PARAMETER`.
La IA está activa por defecto; una lista vacía permite aislar el escenario físico.

## Prueba nativa sin presentación

**Validación focalizada autorizada.** `--fixed-fps 60` mantiene el paso de física
de 60 Hz y desactiva la sincronización con tiempo real; no demuestra FPS renderizados
ni sensación de mando. Los comandos completos se documentan para coordinación;
este pase correctivo ejecutó solo los selectores y la suite pura indicados abajo.

Desde la raíz del repositorio, sin GUI/editor, inventario de instalador ni runner
de bootstrap:

```powershell
$godot = "$env:LOCALAPPDATA\Programs\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path .\game --script res://tests/test_match_simulation.gd --check-only
& $godot --headless --path .\game --script res://tests/test_match_simulation.gd --fixed-fps 60
& $godot --headless --path .\game --script res://tests/test_match_preview.gd --check-only
& $godot --headless --path .\game --script res://tests/test_match_preview.gd --fixed-fps 60
& $godot --headless --path .\game --script res://tests/test_match_gameplay_rules.gd --check-only
& $godot --headless --path .\game --script res://tests/test_match_gameplay_rules.gd --fixed-fps 60
& $godot --headless --path .\game --script res://tests/test_match_rules.gd --fixed-fps 60
# Corrección focalizada, conservando el orden canónico y ambos modos:
& $godot --headless --path .\game --script res://tests/test_match_gameplay_rules.gd --fixed-fps 60 -- --groups=expiry_and_choices,opponent_ready,seventh_foul,extensions,extended_expiry
# Solo con host/input/HUD/cámara ya compuestos:
& $godot --headless --path .\game --script res://tests/test_match_player_control.gd --fixed-fps 60
```

Nueva batería: `game\tests\test_match_gameplay_rules.gd`, marker JSON
`FUTSAL_GAMEPLAY_RULES_TESTS`. El watchdog ya no limita a 120 s un recorrido
que contiene más pasos físicos que esos segundos en tiempo real: detecta 30 s
sin progreso de la corrutina o 240 pasos adicionales a su presupuesto pendiente.
Publica pasos pedidos/reales, selección y diagnóstico; fallo incompleto termina
con `FUTSAL_GAMEPLAY_RULES_TESTS_INCOMPLETE`/código 2. `--groups=...` rechaza
grupos desconocidos/duplicados; sin selector se conserva toda la cobertura.
`--probe-watchdog` simula deliberadamente una corrutina detenida y debe producir
JSON `complete=false`, `ok=false` y código 2, nunca una aprobación del juego.
Emite escenarios, checks con
nombres semánticos únicos y negativas exactas por actor/código/mensaje. Recorre
start/catálogo/comandos/contactos físicos/ticks; no setters de estado, teleports
de driver ni contadores ficticios. Incluye ambos modos, espejo, plazos, manos,
regates interceptables, colisiones limpias/tardías/imprudentes, semilla + séptima
real y desenlace de extensión. El addendum de faltas añade límites inclusivos,
NaN/infinito/orden, copias exportadas y rechazo atómico por `start/reset`, además
de contacto suave, desafío vencido, cola de la ventana de 18 ticks y toque
histórico. Las colisiones se conducen después de mutar el recurso del caller
para comprobar también el aislamiento de la configuración activa. El caso
imprudente enfrenta dos atletas en movimiento; no baja el umbral para aprobar.
Los selectores de contactos/faltas se contrastaron con Jolt nativo en este pase;
eso no calibra por sí solo dificultad, sensación ni reglamento completo.
El vencimiento de sexta extendida reutiliza los ticks **de eventos físicos**
observados en la séptima falta de regulación y repite los mismos comandos con
un reloj inicial más corto; comprueba final único sin indirecto posterior. No
ajusta tiempo, fase o contador privados para alcanzar esa situación.

**Revisión independiente G10:** Bishop modifica `match_rules.gd` y
`test_match_rules.gd`, sin aportación del autor original, conforme a la asignación
de coordinación. La suite pura conserva sus casos y añade
`g10_episode_identity`: original frente a nuevo en t y t+1, callback original
retrasado, ID ausente, copia desacoplada y extensión, en micro/preview y espejo.
La suite pura pasó **329/329 checks**, incluidos **122 casos negativos**;
marker `FUTSAL_MATCH_RULES_TESTS`.
La suite de autoridad añade salida real de manos con solapamiento/pausa/separación
medidos por consultas nativas y fortalece la recaptura con un contacto real de
cápsula contra balón elevado: nuevo ID → indirecto. Los JSON de escenarios
incluyen `launch_contact_id` y el episodio nativo posterior, cuando se observen.
No se atribuye el límite t+1 a una colisión observada: se verifica mediante la
entrada pura de producción; manos continuas y nueva colisión de cápsula sí
formaron parte del selector nativo de contactos.

**Corrección nativa focalizada, 2026-09-10:** el bloqueo READY se debía a un
defensor situado unos `5e-8 m` más allá de la tolerancia después de integrar.
El margen físico corrige el origen, sin aceptar lanzamientos ilegales ni
convertir rechazos inesperados en esperados. La colección sobre la línea de
gol podía terminar legítimamente en gol: la prueba de detención hace ahora
intervenir al portero mediante comandos legales dentro del área, y conserva
otro caso explícito donde toque/parada no borra un gol físico. El fixture de
séptima aparta de esa trayectoria al compañero 9; catálogo y diez colliders
permanecen sin cambios. IA y adjudicación de goles no se modificaron.

| Ejecución focalizada | Resultado nativo | Evidencia bajo `tools\godot\runtime\` |
|---|---|---|
| Vencimientos, rival READY, séptima y extensión | 282/282; exit 0; 10 400 pasos; 8.309 s reales | `bishop-core-final-72bb0b35427248ff9ccfb42fe045dda3` |
| Catálogo, vencimientos, continuidad/separación, faltas e independencia de mundos | 742/742; exit 0; 7 690 pasos; 6.217 s reales | `bishop-core-neighbors-a866007615284d3b814b491189804a7f` |
| Reglas puras/G10 | 329/329; exit 0 | `bishop-rules-recheck-897e5df807e74831a71dfdb8a75e4850` |
| Corrutina deliberadamente detenida | exit 2; incompleto; 2 pasos pedidos, 244 reales | `bishop-watchdog-probe-66d673d24f9f46d2967015d70ace746b` |
| Dueño de manos, pausa/reset y reinicios/contactos relacionados | 260/260; exit 0; stderr vacío | `bishop-hands-core-a5319d10395b4f569e8d03d83eb1aedd` |
| Runner de cámara sin modificar, escena principal real | 8278/8278; exit 0; errores `hands_owner`: 219 → 0; stderr vacío | `bishop-hands-actual-camera-483469986c524364a443131e89ced72c` |

Los recorridos positivos tienen stderr vacío; los físicos no contienen
rechazos inesperados ni pendientes. Cada carpeta conserva reporte JSON y logs
sin sobrescribir evidencia previa. No sumar sus checks como casos únicos:
hay verificaciones comunes entre selectores. La cámara se ejecutó headless para
comprobar su consumo de snapshots; no acredita legibilidad visual, FPS o sensación.
All/export/GUI no formaron parte de ese pase focalizado de autoridad.

Regresiones conservadas: matrices de 24 contactos y 50 tiros; F01–F12 íntegros,
adaptando F11 a banda localizada y entrada J real. Las pruebas de tiro IA
retenido pasan a un actor AWAY; HOME conserva recuperación/pase en lugar de
exigir una finalización ahora prohibida. No existe un flag de reglas antiguas.
Los conteos y la evidencia 0.1–0.3 siguientes siguen siendo históricos; la
validación focalizada anterior no sustituye el cierre completo de 0.4.

**Archivos de este pase:** `match_rule_types.gd`, `match_launch.gd`,
`player_command.gd`, `match_event.gd`, `match_setup.gd`, `match_snapshot.gd`,
`match_tuning.gd`, `match_actor.gd`, `match_ball.gd`, `match_simulation.gd` bajo
`game\match\simulation`; los cuatro runners citados y estas secciones.
`match_ai.gd` sigue siendo de Hudson. La revisión G10 de `match_rules.gd` y
`test_match_rules.gd` corresponde exclusivamente a Bishop; las otras partes
aprobadas de reglas no se reescriben. Host, input, cámara, HUD, arena, atleta,
tooling y exportación no se modificaron en este pase de autoridad.

### Evidencia histórica anterior a 0.4

El segundo comando termina con `FUTSAL_MATCH_TESTS` (JSON) y código 0 solo si pasa.
`--fixed-fps 60` acelera la ejecución manteniendo pasos de 1/60 s: **no mide FPS
renderizados**. Ambos runners tienen watchdog de 120 s reales, sin framework externo.

La batería adicional termina con `FUTSAL_PREVIEW_TESTS` y código 0 solo tras
completar sus comprobaciones. Ambos JSON incluyen las comprobaciones ejecutadas.
Un cierre anticipado (`--quit-after 2`) se verificó en ambos con código 2 y
`FUTSAL_MATCH_TESTS_INCOMPLETE` / `FUTSAL_PREVIEW_TESTS_INCOMPLETE`, sin informe de éxito.

**Foco/pase, 2026-09-10, ejecución histórica de Bishop:** micro **335/335**, con 27 negativas
esperadas, **24/24 trayectorias distintas y 50/50 tiros**; preview/foco **492/492**,
con 93 negativas esperadas (incluyen llamadas realmente rechazadas dentro de
callbacks). Ambos código **0**, sin errores/warnings. Parse individual **11/11**:
nueve scripts de simulación y dos runners. Cierres incompletos **2/2**, código **2**.

Evidencia persistente, ignorada por Git:
`build\test-results\bishop-focus-20260910\summary.json` contiene rutas ejecutadas,
códigos de salida, hashes SHA-256 de los once scripts y referencias a los logs.
Los informes nativos completos son `test_match_simulation.json` y
`test_match_preview.json` en ese directorio; los logs homónimos `.log` conservan
stdout/diagnósticos y `.incomplete.log` los cierres anticipados. Cada script tiene
su `.parse.log`. No se ejecutaron GUI, exportación, host ni suite global.

La ampliación atraviesa start/comandos/ticks físicos/eventos: candidatos desde
actor frente a balón, ambos lados del cono, distancia/ID, micro 0 ↔ 2 sin radio,
compañero poseedor, patada y receptor real, intercepción, pase libre/explícito,
pérdida física de contacto entre cola y tick, cooldown, rechazo contextual,
orden 0 → 8 y 8 → 0 con acciones pendientes canceladas, secuencias IA/humano,
intención vacía/parcial/latente, copias, reentrada, pausas, gol/fuera/reinicio y fin.
La devolución del portero controlado se prueba con pase **manual**, conservando
drills separados de devolución **IA no seleccionada**, cerca y a distancia de saque.
El antiguo campo 0 recupera, conduce y dispara como IA real sin tratarse como rival.
No se considera calidad jugable acreditada por el número de atletas o checks.

**Histórico de preview anterior al foco: 250/250**, con 29 negativas esperadas.
Incluye 10/4/10 repetido y eliminación real de colisiones, rebotes contra cada uno
de los seis cuerpos añadidos, poses de reset sin barridos residuales, copias
inmutables, toggles/grupos/parciales en todas las fases, acciones retenidas,
secuencias/cooldowns, selección y recepción de pase, distribución a nuevos campos,
gol/fuera y un perseguidor físico por equipo con apoyos en carriles separados.
La regresión micro se repitió sin cambiar su composición: **322/322**, con sus
**24/24 trayectorias y 50/50 tiros**. Parse individual de esa entrega: **11/11** (nueve
scripts de simulación y ambos runners), sin errores ni warnings.
Es evidencia de autoridad/colisiones, no de diez vistas, menú, proporciones
aprobadas, tacto, arte o rendimiento renderizado.

La batería instancia autoridades reales y atraviesa sus APIs: movimiento,
recepción, pase/devolución, carga/loft, tackle, IA, pausa física, reset, fin,
aislamiento de mundos, validación y goles propios/ajenos. La matriz física contiene
**24 setups distintos** (10 de suelo, 8 postes, 4 larguero, 2 red); la matriz de
**50 tiros ejecutados mediante comandos** combina diez cargas con cinco líneas
(incluidos 20 tiros a postes). Registra configuraciones, contactos reales, velocidad,
altura mínima y goles; comprueba unicidad de parámetros, no solo de etiquetas.
Estas pruebas técnicas no sustituyen la revisión independiente ni los tres
evaluadores con mando, cámara/arte aprobados o perfil de rendimiento de G1/G2.

**Histórico G1 anterior al foco:** Godot 4.7.2 estándar/Jolt 60 Hz, 322/322 comprobaciones,
24/24 trayectorias, 50/50 tiros y 27 negativas esperadas identificadas como tales.
Parse tipado individual de los nueve scripts de simulación y el runner: 10/10,
sin errores ni warnings. Los conteos de matrices son subconjuntos, no pruebas
adicionales que se sumen a 322.

La ampliación cubre la restauración física del vuelo y giro en `GOAL_PAUSE` tras
pausa explícita, contacto real con la red al continuar y balón todavía congelado
al retomar `RESTART_PAUSE`. Antes de corregir la rama de resume, las nuevas
aserciones reprodujeron dos fallos (320/322); después, 322/322.

Coordinación repitió el 322/322 y reprodujo independientemente esos mismos dos
fallos al revertir solo la condición de resume en una copia privada, leída del
disco antes de ejecutar, sin cambiar las aserciones. Las matrices siguieron
24/24 y 50/50: por sí solas no cubrían esa transición de pausa. Evidencia:
`tools\godot\runtime\core-resume-independent-1084eae341fa4905aad90b7e5e6b05cf`.

Coordinación repitió la batería inicial de forma independiente: 315/315, 24/24 y 50/50,
sin errores de motor. Evidencia:
`tools\godot\runtime\core-independent-01a178a28ce9444fab6ccd8eaf2d80fb\result.json`.

También comprobó sensibilidad usando copias privadas de producción, con los tests
sin modificar y cada mutación leída del disco antes de ejecutar. Eliminar la llamada
de `_physics_process` a `_check_boundaries` produjo 51 fallos (264/315).
Desactivar únicamente los colliders de postes produjo 28 fallos (287/315), con
trayectorias 16/24 y tiros 30/50. Tras restaurar los nueve scripts byte por byte,
volvió el 315/315; las copias temporales se eliminaron. Informes y diffs:
`tools\godot\runtime\g1-sensitivity-de65c803a7974a5084d5302d6b930c5c`.
Esto comprueba esas regresiones concretas, no exhaustividad ni sensación humana.

**Propiedad de esta entrega:** nueve archivos bajo `game\match\simulation\`:
`match_simulation.gd`, `match_actor.gd`, `match_ball.gd`, `match_ai.gd`,
`match_tuning.gd`, `match_setup.gd`, `player_command.gd`, `match_snapshot.gd`,
`match_event.gd`; además `game\tests\test_match_simulation.gd` y este documento.
La entrega original de la autoridad no cambió bootstrap, tooling ni escena principal.

**Delta de preview:** `match_setup.gd`, `match_snapshot.gd`, `match_simulation.gd`,
`match_ai.gd` y `match_actor.gd` bajo ese directorio; fingerprint acoplado de
`test_match_simulation.gd`, nuevo `game\tests\test_match_preview.gd` y las secciones
de simulación de este documento. No modifica host, input, HUD, cámara ni arte.
El consumidor debe solicitar el preset explícito, reconciliar vistas por IDs del
snapshot, dejar receptor −1 en pases preview y conservar la IA confirmada en su
setup de reinicio. Esa integración y su validación pertenecen al host, no a los
runners de autoridad de esta entrega.

**Delta de foco/pase:** `player_command.gd`, `match_event.gd`, `match_setup.gd`,
`match_snapshot.gd`, `match_simulation.gd` y `match_ai.gd` bajo
`game\match\simulation\`; los dos runners existentes y estas secciones de contrato.
Sin archivos/markers de test nuevos. Consumidores: enrutar al seleccionado y su
secuencia vigente; escuchar `FOCUS_CHANGED`, leer foco también al reiniciar,
usar intención completa para menú/reinicio y distinguir switch de pase por
posesión del seleccionado. Host/input/cámara/HUD y su validación pertenecen a
sus integradores; estas pruebas no afirman que esa migración esté terminada.

## Escena jugable integrada

`res://match/match.tscn` es ahora la escena principal de `0.1.0-g1`.
Su anfitrión, `match.gd`, conecta la autoridad real con HUD, representación
provisional de cuatro atletas, balón, pista y cámara lateral amortiguada.
No hay audio ni arte final aprobado.

La recogida de input tiene prioridad física −10, la autoridad 0 y el consumo de
snapshots +10: una acción humana aceptada se resuelve en el mismo tick antes de
una pausa diferida. La animación consume esos resultados, no concede contactos.
`start_match(setup)`, `restart_match()`, `set_match_paused(bool)` y `quit_match()`
son las operaciones del anfitrión; `get_snapshot()` y `get_simulation()` exponen
el contrato tipado. No modificar los nodos físicos desde presentación.

WASD/stick mueve; Shift/RT acelera; Ctrl/LT controla de cerca; J/A pasa o contiene
sin balón; K/B carga el tiro hasta 0,8 s y lo ejecuta al soltar, o intenta un robo
sin posesión. Sin stick, el pase apunta al portero; con stick, mantiene el apuntado
y el cono de asistencia del core. Esc/Start abre/cierra pausa; el menú ofrece
continuar, reiniciar y salir con teclado, mando o ratón.

Pausa, reinicio, pérdida de foco y desconexión del mando activo cancelan intenciones
retenidas; hay que devolver los controles a neutro para continuar. La pérdida de
posesión cancela una carga. No hay editor de bindings en pantalla todavía.

Prueba del punto de entrada productivo:

```powershell
& $godot --headless --path .\game --script res://tests/test_match_integration.gd --fixed-fps 60
```

Coordinación repitió inicialmente **170/170**, con eventos nativos de teclado, ejes y botones.
El test instancia la escena principal configurada y recorre movimiento,
pases/devolución, tiro, robo, pausa, carga cancelada, gol, fuera, resultado y cámara.
No es una medición de mando físico ni FPS renderizados.

Las observaciones técnicas de QA dieron lugar a **180/180** comprobaciones:
se inyecta la señal de conexión del motor para probar desconexión del mando activo
y de otro, cancelación de carga, reconexión sin reanudación automática y cambio a
teclado. No se afirma haber desenchufado un dispositivo físico.
El informe final se emite al finalizar el `SceneTree`; una aserción fallida de salida
devuelve código 1 aunque el anfitrión haya pedido salir con 0, y un cierre prematuro
no produce un informe de éxito.

Coordinación verificó esos casos en copias privadas: forzar una aserción final
a falso produjo 179/180 y código 1; eliminar únicamente la conexión de producción
a `Input.joy_connection_changed` produjo cinco fallos (170/175, pues no se alcanzó
el tramo de salida). Ambas mutaciones se leyeron del disco antes de ejecutar.
Un cierre forzado tras un frame también devolvió fallo explícito; restaurar las
copias recuperó 180/180 y después se eliminaron. Evidencia:
`tools\godot\runtime\integration-review-fixes-4450466bad0f4090a05eae737cd84270`.

El diagnóstico `game\diagnostics\match_smoke.gd` solo se activa con `--smoke-test`,
después del arranque normal exitoso, recibiendo sus mismos objetos de autoridad y
HUD. No sustituye la escena principal ni crea una autoridad falsa. Permite
comprobar ese recorrido también en el ejecutable exportado; los comandos y
evidencias vigentes de exportación están en `docs\TOOLING.md`.
