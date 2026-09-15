# MVP — Fútbol sala con calidad de juego y visual primero

**Estado: contrato de producto y objetivos, actualizado el 14 de septiembre de 2026.** Stack y
dirección artística integrados. **Godot 4.7.2 estándar, templates Windows y
bootstrap debug exportado: verificados**, incluida comprobación independiente de
coordinación; informe identificado en `docs\DEVELOPMENT_PLAN.md`.
La corrección MCP de Windows está migrada, probada con concurrencia real y aceptada
formalmente por Vasquez. Evidencia y operación en `docs\TOOLING.md`.
El usuario autorizó comenzar G1: `MatchSimulation`, el HUD y la escena principal
con controles y cámara están integrados. El contrato
ejecutable y las simplificaciones de entrenamiento están en `docs\MICRO_SLICE.md`.
El usuario autorizó una **preview experimental 5v5 y un menú de desarrollo**
para evaluar escala y corregir la presentación de G1; alcance en §2.1, ya
implementado y comprobado en fuente y ejecutable. La base de trabajo es
**su captura real de G1**.
Su comentario «la referencia visual no es mala» no aprueba una referencia
dream-loop A-G2/A-G3, ni concede puntuación artística, aceptación humana o FPS.
Una petición posterior autoriza cambiar de jugador con la tecla de pase y
controlar al receptor tras un pase; contrato en §2.2, **implementado y revisado
en 0.3.0-preview**. Las previews 0.2.0 y 0.3.0 se conservan como referencias.
La jugabilidad de §2.3 está implementada y exportada en **0.4.0-preview**:
fuente, ejecutable, GPU, arranque normal y veinte capturas nativas comprobados.
Vasquez cerró la revisión de fuentes y aprobó técnicamente la estructura del
paquete; evidencia en TOOLING. No equivale a completar el MVP de carrera, editor y Partido rápido
ni concede aceptación humana, artística o de rendimiento.

## 1. Norte del producto y decisiones propuestas

Un juego de fútbol sala **single player**, de partidos cortos, con balón creíble,
control inmediato, compañeros útiles y una presentación especialmente cuidada.
La espectacularidad viene de animaciones, contactos, goles, cámara, sonido y luz;
nunca de perder el control, ocultar el balón o sustituir gameplay por cinemáticas.

| Aspecto | Default propuesto |
|---|---|
| Plataforma inicial | PC Windows; mando primero y teclado/ratón funcionales |
| Cámara | 3D, tercera persona elevada tipo retransmisión, siguiendo la acción con anticipación |
| Sensación | Arcade-sim: respuesta ágil, física legible, asistencia limitada y configurable |
| Duración | Dos tiempos de 3 minutos efectivos; objetivo orientativo de 8–10 minutos reales |
| Contenido visual | Una cancha cubierta excelente, un rig de atleta reutilizable y animaciones de calidad |
| Control del equipo | Un futbolista seleccionado; compañeros y portero dirigidos por IA |
| Modos | Carrera local sencilla y Partido rápido independiente |
| Dificultad | Fácil, media y difícil, elegidas antes de empezar |
| Red | Fuera del MVP; posteriormente cliente-servidor, no peer-to-peer ni lockstep determinista |

Stack elegido: **Godot 4.7.2, Forward+, GDScript tipado y Jolt a 60 Hz**;
autoría en **Blender 4.5.13 LTS**, intercambio explícito `.glb`.
`docs\STACK_DECISION.md` recoge la recomendación de Bishop y sus límites;
`docs\ART_DIRECTION.md`, la dirección de Lambert. La elección se reevalúa tras
G1/G2 si no permite alcanzar sensación y arte; no demuestra calidad por sí misma.

## 2. Primero una micro vertical slice, después el juego completo

1. **Micro slice:** 1 jugador de campo humano contra 1 jugador de campo IA, con
   1 portero IA por lado: cuatro atletas activos. Es un banco de prueba deliberado,
   no el formato final ni una reducción de la plantilla del producto.
2. Probar movimiento, inercia, posesión, contacto pie-balón, pase al portero y devolución,
   disparo, parada, gol, recuperación del balón y cámara. HUD técnico mínimo y reinicio.
3. Validar primero el tacto del juego y luego su traducción visual en motor: suelo,
   atleta, equipación, luz, materiales, animación y audio de impactos representativos.
4. **Solo tras superar ambos gates:** promover el partido 5v5 de G3 y su reglamento; después añadir
   editor, plantilla, XP, menús de modos, Partido rápido y sus tres dificultades.
   La excepción experimental de §2.1 no equivale a superar esos gates.

La referencia visual **A-G2 muestra cuatro atletas** y la **A-G3, diez**.
Cada una requiere aprobación propia y coincidencia de cámara, resolución, acción
y número de atletas con su captura. No comparar la micro slice con una imagen 5v5
y dar por superado el Tier 1 de dream-loop.

No producir menús completos, sistemas de progresión o múltiples assets para esconder
una micro slice que no sea divertida. Se permite preparar contratos y casos de prueba
en paralelo, no construir esos sistemas saltándose el gate.

### 2.1. Base validada 0.2.0: preview 5v5 y menú de desarrollo

**Petición del usuario, 2026-09-10:** corregir la sensación extraña del parqué
al moverse cámara/jugador, mejorar luces, sombras, definición de atletas y sprint,
y añadir 5v5 para juzgar visualmente las proporciones de la cancha.
Esta autorización sustituye la prohibición previa de adelantar cualquier 5v5
**solo para este experimento**, no para promover G3 ni abrir G4.
Los límites de humano fijo y la semántica de IA de esta base quedan sustituidos
por §2.2 en la siguiente revisión; no reinterpretar sus resultados históricos.

- El arranque de la preview muestra **10 atletas físicos independientes**:
  cuatro de campo y un portero por lado. Un campo local sigue bajo control humano;
  los otros siete de campo y los dos porteros tienen IA básica activada por defecto.
  Cada atleta tiene identidad, cuerpo de simulación y representación propios;
  reutilizar un modelo/rig es válido, añadir seis mallas decorativas no lo es.
- Mantener el modo **micro 1v1 + dos porteros** como regresión seleccionable,
  con sus cuatro IDs y contratos existentes. El preset de preview se solicita
  explícitamente; las llamadas de simulación sin setup siguen siendo micro.
  Modos, IDs, defaults e interfaces: `docs\DEVELOPMENT_PLAN.md`, §4.1.
- Menú técnico accesible con **F1** o desde pausa, con selector **5v5 experimental / 1v1 de
  regresión** y tres interruptores: **IA rival (incluye su portero)**,
  **IA compañeros de campo** e **IA portero local**. Todos disponibles y activos
  en 5v5; compañeros de campo no aplica en 1v1. Desactivar IA no retira atletas,
  no elimina colisiones ni detiene el balón. Cambiar de modo reinicia explícitamente;
  cambiar IA no reinicia el encuentro. Ajustes efímeros, sin guardado de producto.
- Se conserva el entrenamiento G1 de 120 s y sus reposiciones simplificadas.
  Control humano fijo, sin sustituciones, selección de jugador, dos tiempos,
  competición/reglamento completo ni dificultades comerciales. La IA mínima debe
  permitir observar oposición y compañeros sin que todos persigan el mismo balón;
  no acredita IA táctica de G3.
- **Control, balón y cámara primero.** Diagnosticar la estabilidad temporal del
  suelo y sus líneas durante desplazamiento/giro; corregir iluminación y sombras
  de contacto sin esconder problemas con desenfoque. Definición y zancada de sprint
  se revisan en movimiento, no solo en una captura. Conservar escala física
  40 × 20 m; no deformar pista, balón o atletas para fingir buenas proporciones.
- La captura G1 del usuario es la referencia de trabajo de esta iteración local,
  **no una A-G2/A-G3 aprobada**. Comparar antes/después de cuatro atletas bajo las
  mismas condiciones; la vista de diez sirve para evaluación humana de escala,
  no para puntuar equivalencia contra una imagen de cuatro.
- Este banco de desarrollo **no es Carrera, editor, Partido rápido ni progreso**:
  sin `career_id`, servicio de recompensas, XP o lectura/escritura de carreras.
  Las plantillas del producto siguen siendo exactamente **12 = 2 porteros + 10
  de campo**, con **5 activos/7 suplentes**, **100 XP compartidos**, **+3 idempotente
  por victoria de carrera** y **Partido rápido aislado**. Diez cuerpos de preview
  no sustituyen las futuras plantillas ni crean jugadores persistentes.

Implementación y regresiones técnicas comprobadas; evidencia de fuente/exportación
en `docs\TOOLING.md`. El A/B continuo del parqué usa el shader G1 original con la
misma composición, cámara y poses en ambos pases, no compara cuatro contra diez.
Sus medidas y límites están en `docs\ART_DIRECTION.md`. Valoración humana de
jugabilidad/animación, aceptación artística y rendimiento siguen pendientes.
G1 humano, G2, G3 y sus referencias/pruebas de FPS no quedan aprobados por autorizarlo.
Sin llamadas a APIs externas, assets externos ni ampliación a menús de producto.

### 2.2. Cambio de jugador y pase con foco — implementado en 0.3

**Petición posterior del 2026-09-10, implementada y revisada:** J/A tiene una sola
acción contextual por pulsación. En ambos modos se puede controlar a cualquier
compañero HOME activo, incluido el portero; nunca a un rival.

- **Sin balón:** cambia al compañero cercano al jugador controlado. Si un compañero
  ya tiene el balón, cambiar foco no le ordena pasar ni altera la posesión.
- **Con balón:** realiza un pase y transfiere el foco al receptor efectivo cuando
  sale la patada aceptada, antes de la recepción. El balón continúa su trayectoria
  física; no se teletransporta ni se garantiza que llegue al compañero.
- **Sin dirección:** elige por distancia al controlado, con desempate por ID.
  **Flechas, WASD o stick + J/A:** elige en esa dirección de cámara, con el cono
  de asistencia existente de 35 grados y prioridad ángulo/distancia/ID.
  Sin candidato direccional, el cambio se rechaza con feedback; un pase libre
  conserva el foco. Pase inválido, cooldown o intercepción no transfieren control.
- Mantener J/A no repite la acción; hay que soltarlo para otra pulsación.
  Movimiento y sprint continúan al cambiar foco; carga y acciones pendientes no
  pasan al nuevo jugador. Pausa, pérdida de foco y desconexión siguen exigiendo
  controles neutros. **Ctrl/LT** conserva el control cercano/contención.
- Desarrollo conserva tres grupos: rival, campo local y portero local. Ahora
  configuran **preferencias**, incluido el seleccionado, cuya IA queda suspendida
  mientras lo controlas. «Todo apagado» y subconjuntos parciales no se reactivan
  al cambiar jugador. En micro, campo local configura la preferencia latente del 0.
- Inicio, reinicio y saque canónico vuelven al jugador 0; reinicio/saques conservan
  preferencias de IA. Pausa y fin conservan la última selección; aplicar modo
  restaura sus defaults. Una única marca, HUD y cámara reflejan el foco confirmado.

El portero controlado utiliza movimiento, balón y colisiones existentes; no recibe
comandos IA ni devolución automática hasta quedar fuera de foco. No añade controles
especializados de guardameta, sustituciones, carreras, XP, dificultades ni red.
Interfaces, propiedad y pruebas F01–F12 en `docs\DEVELOPMENT_PLAN.md`, §4.2.

### 2.3. Jugabilidad 0.4 — paquete autorizado

El usuario autorizó todo el plan el 2026-09-10 y coordinación aceptó su contrato
de diseño para `0.4.0-preview`, input schema **3**. El estado de entrega y las
evidencias vigentes están en DEVELOPMENT_PLAN, §1, y TOOLING; no atribuir estas
mecánicas al ejecutable 0.3 conservado ni heredar su aprobación.
La fuente de verdad de **APIs tipadas, enums, propiedad y 32 criterios G01–G32**
es [DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md), §4.3. Esta sección resume el producto,
sin duplicar ese contrato ni reabrir la autorización.

| Bloque autorizado en micro y preview 5v5 | Experiencia exigida |
|---|---|
| IA aliada pasadora | Recuperar, apoyar y priorizar pase seguro al seleccionado; alternativas y desplazamiento si no hay línea, sin ping-pong ni espera indefinida. Política y autoridad bloquean tiro/remate/conducción a gol intencionados de HOME no seleccionado. Tiros humanos y ataque AWAY continúan; desvíos físicos legítimos no se borran |
| Reanudaciones | Bandas, córners y meta con último toque real, cruce completo, equipo/punto/sacador, colocación localizada y ciclo parado → colocación → listo → juego. No devolver a todos al centro por una salida |
| Regates | Enganche lateral y cambio de ritmo adelantado/neutral con L/X + dirección; contacto y recuperación físicos, posibilidad de perder el balón, sin teleport ni invulnerabilidad |
| Faltas | Distinguir contacto limpio, tardío e imprudente; directos, penalti de 6 m y sexta acumulada sin barrera con ubicación reglamentaria. No convertir cada roce o entrada al aire en falta |

Conservar selección dinámica de cualquier HOME activo, incluido portero 2;
IA efectiva = preferencias completas menos seleccionado. El foco pasa al receptor
efectivo al **lanzamiento aceptado**, no al encolar o recibir. Rechazo, tiro,
pase libre e intercepción no fabrican selección/posesión. Movimiento y sprint
continúan al cambiar foco; se conserva una acción por pulsación.

**Cámara y apuntado:** córner propio detrás y algo por encima del sacador,
orientado hacia el área y con balón/receptores visibles. Transición suave de
entrada y regreso al golpeo aceptado; rechazo mantiene preparación. Comprobar
cuatro orientaciones sin paredes/redes, inversión de ejes ni rotación involuntaria
del apuntado sostenido. Córner rival conserva retransmisión para defender.
En preparación propia se apunta sin caminar con el sacador; en la rival se
permite defender/mover/cambiar compañero respetando las restricciones.

La flecha propia aparece al cargar K/B y preparar saques/libres/penaltis; usa
flechas/WASD/stick, potencia disponible y **el mismo resolver puro** que calcula
origen real, asistencia y velocidad inicial del lanzamiento. La consulta no muta
autoridad ni vuelve a consumir input. J/A sigue siendo rápido; meta se ejecuta
con manos, no con un tiro de pie. Conservar Ctrl/LT y Shift/RT.
El ajuste fino de teclado en saque propio es detalle de implementación a confirmar
por Hicks: Ctrl/LT + lateral es una posibilidad, **no un binding ya acordado u
operativo**, y no debe romper el control cercano existente.

Primera guía: flecha de dirección/potencia, sin arco ni zona de caída; no introduce
altura o efecto manuales. No garantiza recepción, esquivar rivales o evitar
rebotes. Se invalida al soltar/ejecutar, perder posesión, cancelar, cambiar foco
o fase, pausar/reiniciar; nunca revela intención rival. F1 permite desactivarla
y conserva la preferencia en la sesión. Apuntar no pausa ni amplía el plazo.
Se crea una representación propia de la referencia conceptual aportada, sin
copiar interfaz, logos o assets.

**Reglas específicas de esta entrega:** fuente contrastada por Hudson,
[FIFA Futsal Laws of the Game 2025/26](https://assets.the-afc.com/downloads/referees/Futsal---Laws-of-the-Game-2025-2026---Sep-12-update.pdf);
no hay edición 2026/27 verificada.

| Caso | Regla vinculante |
|---|---|
| Preparación/plazo | Colocación mínima de 60 ticks y entrada de cámara de como máximo 45; cuatro segundos desde «listo» donde proceda, sin ACK de render. Pausa congela el plazo; carga/rechazo/elección no lo renuevan |
| Banda / córner | Pie; banda con 5 m, córner con 5 m desde el arco. Vencimiento: banda contraria en el mismo punto / meta contraria |
| Meta | Manos dentro del área, adversarios fuera de ella; sin 5 m universal. En juego al liberar y moverse claramente, sin exigir salir del área. Vencimiento: indirecto contrario proyectado a la línea del área |
| Directos / indirectos | Distancias/colocación reglamentarias; vencimiento a los cuatro segundos produce indirecto contrario desde el punto, proyectado cuando corresponda |
| Penalti de 6 m | **Sin cuatro segundos y sin incremento de acumuladas**, según Law 12, PDF p.74 |
| Sexta y posteriores (`DFKSAF`) | **Con cuatro segundos y tiro directo obligatorio, no pase**, sin barrera. Elección infracción/10 m en la franja longitudinal de 10 m fuera del área real, no por radio; dentro del área prevalece penalti |
| Geometría/proyección | Área de arcos de 6 m centrados en Z ±1.58 y tramo de 3.16 m, igual en reglas y dibujo; portería interior 3 × 2 m. Proyección del indirecto paralela a banda: conservar Z y modificar X, no punto más cercano |
| Gol directo y toques | Banda/meta/indirecto directamente a portería rival → meta rival; directamente a propia → córner contrario. Córner/directo permiten gol rival. Otro jugador habilita el gol indirecto; poste no. Deduplicar el golpeo; segundo contacto separado del sacador antes de otro jugador → indirecto |

Mantener **un periodo de 120 s efectivos**. Acumuladas persisten en gol/saques/pausa,
reiniciándose con otra sesión salvo el preset declarado de un ejercicio.
Solo penalti/DFKSAF pendiente permite extensión con reloj en cero: completar ese
lanzamiento hasta gol, fuera, balón detenido o toque distinto del portero
defensor, sin ataque posterior ni reanudación ordinaria adicional. Penalti sigue
sin cuatro segundos; DFKSAF conserva su plazo. No es prórroga ni tanda.
Preservar vuelo/rebotes del gol y pausa física; el saque normal tras gol corresponde
al campo 0/1 del equipo que encajó, no al seleccionado accidental.

**Desarrollo F1:** catálogo fijo de ejercicios de banda, cuatro córners propios,
meta, ambos regates, directo, penalti y sexta, además de juego libre. Los córners
de extremo negativo espejan coherentemente ataque/posiciones; no exponen un
selector arbitrario ni setters de teleport. Aplicar ejercicio reinicia sesión
con confirmación, conserva modo/intención IA/guía y recorre APIs de producción;
seleccionar una opción no lo aplica. El preset de sexta identifica su contador
inicial sin fabricar un historial.

La aceptación exige driver con escena real y entrada teclado/mando, **20 PNG
nativos de 1920 × 1080** de momentos concretos de córner/guía/manos/regates,
sin retoque y con manifiesto. Cada run tiene salida propia; solo coordinación
copia el conjunto final a `build\evidence\0.4.0-preview\gameplay`. No son score
artístico, aprobación humana ni prueba de 1080p60. Propietarios y matriz completa
G01–G32 permanecen en DEVELOPMENT_PLAN, §4.3.

Fuera de esta entrega: fuera de juego, tarjetas, expulsiones, ventaja, reglamento
completo del portero, sustituciones, carrera/XP/guardado, red y dificultades de
producto. Los controles futuros de §3 no quedan habilitados por este contrato.
No se presenta la preview como cumplimiento FIFA completo.

## 3. Partido y controles de referencia

Los bindings son propuesta inicial para mando tipo Xbox; todos serán reasignables.
La dirección de una acción usa el stick izquierdo. El pase/cambio neutro de §2.2
elige al compañero cercano; el tiro neutro conserva la orientación actual.
La asistencia de receptor es limitada, visible y consistente.

| Entrada | Con posesión | Sin posesión |
|---|---|---|
| Stick izquierdo | Moverse y orientar pase/tiro | Moverse |
| RT | Sprint con menor precisión de control | Sprint |
| LT | Conducción cercana y protección del balón | Contención lateral |
| A | Pase raso y controlar al receptor efectivo | Cambiar al compañero cercano o elegido por dirección |
| B | Tiro: mantener carga, soltar ejecuta; límite de carga configurable | Intento de robo de pie, con riesgo de falta |
| X | Regate contextual previsto en §2.3; L en teclado | Sin acción nueva en esta entrega propuesta |
| Y | Pase al espacio del compañero señalado | Sin acción especial en la primera versión |
| LB | Cambiar al receptor previsto o compañero más próximo a la acción | Cambio asistido de jugador |
| Stick derecho | Selección manual direccional de compañero | Selección manual direccional de compañero |
| Cruceta | Solicitar rotación predefinida, confirmada en la siguiente ocasión legal | Igual |
| Menú/Start | Pausa, ajustes, sustituciones y salida | Igual |

La preview adelanta únicamente el cambio mediante A/J descrito en §2.2.
X/Y, LB, selección con stick derecho, rotaciones, ajustes y sustituciones de esta
tabla siguen siendo propuestas de producto, no bindings implementados.
Guardametas no controlados conservan paradas y distribución por IA según preferencia;
el control manual especializado sigue fuera. No exigir combinaciones complejas
para una acción esencial. Teclado de la preview: WASD/flechas, Shift, Ctrl, J/K,
Esc y F1; no afirmar que L/I/Q o rotaciones ya funcionan.
Los contextos deben estar visibles y no disparar dos acciones con la misma entrada.

**Reglamento arcade propuesto:** 5v5 (4 de campo + portero), sin fuera de juego,
saques de banda con el pie, córners, saque de meta, cambio de campo al descanso,
reanudaciones y posesión del portero en campo propio limitadas a 4 segundos, y
restricción de devolución al portero propia de futsal. Faltas con libre directo,
penalti de 6 m y falta acumulada desde la sexta de cada tiempo con tiro sin barrera
de 10 m. Reloj detenido en pausa, gol y balón fuera; reposiciones con límite para
evitar demoras. Empate permitido; no prórroga ni penaltis de desempate en el MVP.

Sin tarjetas/expulsiones ni tiempos muertos en la primera demo: simplificación
arcade explícita, no promesa de reglamento competitivo completo. Hudson debe cerrar
el reglamento v1, sus excepciones y reinicios antes de implementar el partido de G3;
la preview de §2.1 conserva las reglas de entrenamiento, no anticipa esa competición.
Cualquier recorte adicional se refleja aquí, no se introduce silenciosamente.

## 4. Plantilla y personalización

- **Exactamente 12 jugadores:** composición v1 de **2 porteros + 10 de campo**.
  Quinteto activo de 1 portero y 4 de campo; banquillo de 1 portero y 6 de campo.
- **12 no permiten tres quintetos disjuntos de cinco: serían 15.** Si se presentan
  tres quintetos, serán presets que reutilizan integrantes de los mismos 12.
  Nunca duplicar identidades ni elevar la plantilla a 15 sin cambiar el requisito.
- Sustituciones ilimitadas y reversibles: sale un jugador antes de entrar el otro,
  siempre por zona válida; los sustituidos pueden volver. El MVP permite solicitar
  cambios desde pausa o rotación contextual, ejecutados legalmente por la simulación.
- Cada jugador tiene ID estable, nombre, dorsal único, rol y atributos propios.
  No fichajes, lesiones persistentes ni conversión de roles en el MVP.
- Escudo con formas/símbolos parametrizados propios; nombre de equipo, colores y
  **equipaciones local y visitante** editables. Patrones, dorsales y contraste
  mantienen legibilidad; comprobación automática de conflicto de equipaciones.
- Un rig de calidad reutilizado con variaciones acotadas de apariencia y materiales.
  No doce modelos únicos ni marcas, jugadores o escudos reales sin licencia.
- Editor de equipo antes de la primera partida; escudo, colores y kits se pueden
  retocar después fuera de un partido. No editor corporal exhaustivo ni importación
  arbitraria de archivos del usuario en el MVP.

## 5. Atributos y XP: contrato verificable

**100 XP iniciales para todo el equipo, no 100 por jugador.** Se aplican sobre una
base ya jugable: nadie empieza inmóvil, incapaz de pasar o sin reflejos por falta de XP.

Propuesta de balance v1, revisable después de probar la micro slice:

| Rol | Seis atributos elegibles |
|---|---|
| Campo | Velocidad, destreza (control/regate), pase, tiro, defensa, resistencia |
| Portero | Velocidad, destreza/agilidad, reflejos, colocación, blocaje, distribución |

Base propuesta de 50/100 en cada atributo elegible, coste de 1 XP por +1 punto,
tope de 90/100 por atributo y **máximo de 60 XP invertidos por jugador** en total.
El rol define los atributos válidos: no gastar en tiro de campo de un guardameta
ni en blocaje de un jugador de campo. Las curvas de efecto se calibran, no se
interpreta «50» como una velocidad física. Los topes son propuestas de balance;
los contratos **12 / 100 / +3** son requisitos.

Para cada carrera:

```text
W = número de victorias completadas con recompensa única registrada
XP_total = 100 + 3 × W
XP_total = XP_sin_asignar + suma(XP_asignados_a_atributos_de_los_12)
XP_sin_asignar y cada asignación son enteros >= 0
50 <= valor_de_atributo <= 90
suma(asignaciones_de_un_jugador) <= 60
```

- Vista previa reversible durante la creación, antes de confirmar y empezar la carrera.
  Después no hay reseteo/reembolso de atributos en el MVP. El gasto es una transacción
  validada; clics repetidos o dos vistas abiertas no pueden gastar el mismo saldo.
- Se pueden guardar XP para más tarde. Al alcanzar topes, los +3 siguen entrando
  en la bolsa: no se descartan, no se autoasignan ni se alteran las reglas.
- Cada **victoria de carrera completada** otorga **exactamente +3**, cualquiera
  que sea la dificultad. Derrota, empate y abandono: 0. Sin multiplicadores,
  compras, anuncios, suscripciones ni pay-to-win.
- La asignación se bloquea durante un encuentro; la simulación usa una instantánea
  de atributos validada al inicio.
- Cambiar curva, base o tope exige nueva versión de balance y migración que conserve
  el presupuesto; nunca pérdida silenciosa de XP ni inventar nuevas ganancias.

### Finalización, revancha y recarga

| Situación | Resultado exigido |
|---|---|
| Carrera nueva | Registrar una sola concesión inicial de 100 XP |
| Victoria tras terminar los dos tiempos | Confirmar resultado y +3 en una única transacción durable |
| Evento de gol, victoria provisional o pantalla de celebración | No conceder XP |
| Callback duplicado, reabrir resultados, doble clic o recargar tras victoria | Mismo ID de partido: ninguna recompensa adicional |
| Suspender y continuar | Mismo ID e instantánea guardada; recompensa solo al completar |
| Salir/cancelar antes de terminar | Partido abandonado, 0 XP; no convertir ventaja parcial en victoria |
| Revancha/reiniciar antes de terminar | Abandonar anterior; nuevo ID, 0 XP hasta completar otra victoria |
| Revancha después de terminar | Nuevo ID; una nueva victoria completa sí permite otros +3 |
| Fallo de escritura al finalizar | Reintento idempotente; no mostrar XP como guardados antes de confirmación |
| Cierre inesperado | Recuperar último checkpoint consistente y mismo ID; no fabricar resultado |

El identificador de recompensa es único por `(career_id, match_id)` y solo la
autoridad de partida puede confirmar una victoria terminal. Una derrota no se puede
reescribir como victoria dentro del mismo resultado confirmado.

## 6. Dos modos de producto aislados y tres dificultades

El menú de desarrollo de §2.1 es una herramienta efímera de prueba, no un tercer
modo de producto ni una implementación anticipada de los dos siguientes.

**Carrera local:** crear equipo, repartir la bolsa inicial, jugar partidos individuales
contra IA, recibir +3 por victoria y asignarlos después. Historial básico de resultados
y progreso; no exige una liga, calendario ni mercado.

**Partido rápido:** generar automáticamente **ambos equipos**, humano y rival IA:
escudos, colores, kits compatibles, 12 jugadores y atributos. Semilla registrable para
reproducir fallos; repartir automáticamente un presupuesto comparable de 100 XP por
equipo sobre la misma base y respetar topes. Permitir regenerar y elegir dificultad.

Partido rápido opera con estado efímero, sin `career_id`, sin servicio de recompensa
de carrera y sin escritura de su guardado. Una prueba debe comprobar que crear,
ganar, perder, abandonar y repetir partidos rápidos **no cambia ni un atributo ni
un XP de ninguna carrera**. No basta ocultar el botón de cobrar. Puede guardar
preferencias globales de control/audio, nunca datos de progreso.

| Dificultad | Comportamiento objetivo, no ventajas ocultas |
|---|---|
| Fácil | Mayor tiempo de decisión, presión moderada, más margen de error en pase y cobertura |
| Media | Reacción y marcaje equilibrados, apoyos y desmarques coherentes |
| Difícil | Mejor lectura táctica, coordinación, selección de pase y presión; errores aún posibles |

Mismos límites de velocidad, colisión y atributos; sin teletransporte, lectura de
inputs futuros, balón imantado ni boost secreto. La IA sin balón mantiene amplitud,
triángulos de pase, apoyo al poseedor, ataque al segundo palo y cobertura de pérdidas.
En defensa prioriza amenaza, marcaje y recuperación sin perseguir todos el balón.
Porteros con colocación, paradas y distribución compatibles con las mismas reglas.
Hudson define escenarios reproducibles que distingan las tres dificultades.

## 7. Guardado local y frontera para cliente-servidor

- Guardado versionado: `schema_version`, `ruleset_version`, `baseline_version`,
  `profile_id`, `career_id`, IDs estables de jugadores, personalización,
  asignaciones/saldo, transacciones y conjunto de recompensas procesadas.
- Persistir `match_id` antes del saque inicial y estados terminales inmutables.
  Checkpoint incluye reloj, marcador, semilla/estado de IA y estado de la simulación
  necesario para reanudar coherentemente; formato concreto pendiente de diseño.
- Escritura transaccional/atómica con recuperación y copia válida anterior. Migración
  validada; una versión desconocida o corrupción no sobreescribe la única copia sana.
  Guardado legible/exportable para soporte sin incluir credenciales ni datos personales.
- Separar desde el inicio comandos de entrada, simulación/autoridad **headless**,
  eventos/instantáneas, presentación y persistencia. UI/cámara/sonido nunca deciden
  goles, saldo o adjudicación de victoria.
- En offline, la autoridad corre localmente. Después será servidor autoritativo:
  valida comandos, resultados y recompensas; el cliente presenta y eventualmente
  predice/reconcilia. ENet es la hipótesis de transporte de `docs\STACK_DECISION.md`;
  protocolo, sesiones y despliegue se diseñan y prueban después del MVP, no están activos.
- **No exigir lockstep determinista entre máquinas** ni confiar en física idéntica
  por plataforma. Reproducibilidad de pruebas locales no equivale a determinismo de red.
- El guardado offline no puede prometer anti-cheat: manipulación o restauración manual
  de copias puede alterar progreso. Checksums detectan daños, no hacen confiable al cliente.
  No prometer importar ese XP a online; política de migración pendiente y validación
  futura de recompensas exclusivamente del lado servidor.

## 8. Estándares de aceptación — aún no medidos

| Área | Gate propuesto |
|---|---|
| Control y balón | Al menos 3 evaluadores ajenos al implementador: media >=8/10 en respuesta, control, tiros y cámara; ninguna categoría <7/10 |
| Integridad del balón | Escenarios de posesión, rebote, tiro, parada y línea de gol sin atravesar suelo/postes/red a las velocidades admitidas |
| Respuesta | Orden muestreada → simulación p95 <=50 ms; mando → primer cambio visual p95 <=83 ms y p99 <=100 ms, medidos aparte |
| Visual | Crítico independiente con la escalera bloqueante de cinco tiers de dream-loop y nota >=8 sobre el ejecutable; pruebas separadas de movimiento/legibilidad de `docs\ART_DIRECTION.md`, sin defectos críticos |
| Rendimiento | 1920 × 1080 nativos/60 FPS; trabajo sin VSync/limitador p95 <=14,5 ms y p99 <=16,0 ms; presentación a 60 Hz y protocolo completo de la sección 7 de `docs\ART_DIRECTION.md` |
| Escala real | Repetir rendimiento con 10 atletas activos, balón, IA, sombras y efectos del partido; el micro 1v1 no acredita el 5v5 |
| UX y accesibilidad | Menús con mando, reasignación, escala de texto, alternativa no cromática entre equipos, volumen separado y vibración/temblor desactivables |
| Progresión | Pruebas de conservación, topes, +3 idempotente y aislamiento completo de Partido rápido |
| Estabilidad | Sesión de al menos 10 partidos completos, guardado/recarga y sustituciones, sin bloqueos ni pérdida de progreso |

Registrar build, escena, resolución, calidad, renderer, GPU realmente usada, driver y
herramienta de medición. **Evidencia de hardware aportada por coordinación el
2026-09-09**, mediante:

```powershell
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
```

```text
NVIDIA RTX 2000 Ada Generation Laptop GPU, 8188 MiB, 595.95
```

VRAM dedicada verificada: **8188 MiB, aproximadamente 8 GiB**; controlador **595.95**.
No es una estimación de Win32. La consulta de CPU `Win32_Processor` identificó
**Intel Core Ultra 9 185H, 16 núcleos y 22 procesadores lógicos**; el inventario previo
registró **63,4 GiB de RAM** e **Intel Arc Pro**.

Esta evidencia **no prueba FPS ni que Godot esté usando esa GPU**. Registrar el
dispositivo efectivo en cada ejecución; medir consumo, frame times y estabilidad.
No declarar requisitos mínimos comerciales a partir de este único equipo.

Para rendimiento, calentar **120 s** y registrar **tres recorridos de 180 s** por
fase; presentación sincronizada con p95/p99 <=16,67 ms + 0,5 ms de tolerancia,
menos del 0,1 % de intervalos >20 ms y sin tirones recurrentes de 33,3 ms.
No aprobar por una media de FPS ni trasladar cifras del diagnóstico al partido.

Dream-loop está vendorizado, no ejecutado. Su entrada admite **una referencia del
usuario con derechos y aprobación**, o **un generador autorizado y aprobación humana
de la imagen resultante**. Hoy no hay referencia A-G2/A-G3 aprobada ni generador
habilitado; la captura real G1 usada en §2.1 no cubre esa aprobación formal.
Una API no es un requisito irreducible. Conectar Blender/MCP no cubre esa entrada.
Lambert entrega capturas; un crítico independiente aplica el prompt upstream
íntegro de `.github\skills\dream-loop\SKILL.md`: cinco tiers con techos, no una
media ponderada. Vasquez coordina pruebas, Ripley decisiones de producto; ninguno
autoaprueba su trabajo. Referencia, imagen en motor, movimiento y FPS son evidencias distintas.

Máximo de **3 rondas de arte por gate**, con objetivo y comparación en cada
una. Presupuesto de API de pago por defecto: **0**. Sin proveedor habilitado y gasto
explícitamente autorizado, no iniciar llamadas pagadas ni bucles de reintento.
Tras 2 rondas sin mejora o 3 totales, detener, diagnosticar y proponer cambio acotado;
no bajar el umbral ni declarar calidad lograda para continuar.

## 9. Fuera de alcance

Online, matchmaking, cooperativo, pantalla partida, lockstep, ligas, torneos,
transferencias, monetización, contenido licenciado, múltiples estadios, editor
corporal avanzado, comentarios narrados extensos, repeticiones cinematográficas
complejas y anti-cheat comercial. El multiplayer cliente-servidor es una evolución
posterior, no un entregable oculto dentro del MVP.

## 10. Definición de MVP terminado

No basta una instalación ni una demo bonita: todos los gates de
`docs\DEVELOPMENT_PLAN.md` deben tener evidencia y revisión independiente.
Partido 5v5 completo, plantilla exacta de 12, personalización local/visitante,
100 XP compartidos, +3 idempotente por victoria de carrera, Partido rápido aislado,
tres dificultades, guardado recuperable y objetivos visuales/de rendimiento verificados.
Mientras falte alguna prueba se registra «pendiente», nunca «aprobado».
