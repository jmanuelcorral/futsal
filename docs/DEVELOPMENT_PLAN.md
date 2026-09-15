# Plan de desarrollo — gates antes que cantidad de funcionalidades

**Plan integrado, actualizado el 14 de septiembre de 2026.** No es un calendario comprometido.
Tras la preparación, el usuario autorizó comenzar la microdemo G1. La fuente
funcional del producto es `docs\MVP.md`; el contrato implementado de entrenamiento
está en `docs\MICRO_SLICE.md`. La preview 5v5/menú de desarrollo y el control
dinámico están implementados en §4.1–4.2. La jugabilidad de §4.3 está implementada,
exportada y comprobada en 0.4.0-preview; Vasquez cerró la revisión independiente
de fuentes y aprobó la estructura del paquete.
Implementación técnica y aceptación humana son estados distintos.

## 1. Estado real y condiciones de partida

| Elemento | Estado de esta planificación |
|---|---|
| Equipo | Ocho especialistas configurados; no implica que todos hayan ejecutado trabajo |
| Motor, lenguaje, renderer y física | Godot 4.7.2, GDScript tipado, Forward+ y Jolt a 60 Hz elegidos en `docs\STACK_DECISION.md`; no es un benchmark |
| Godot instalado / export templates / diagnóstico | **Verificado**: `4.7.2.stable.official.ed1daf0bf` estándar, templates Windows y bootstrap debug exportado, con comprobación independiente de coordinación. Fuente/.exe en headless y render real; no aceptación de juego, arte o FPS |
| Dirección de arte | `docs\ART_DIRECTION.md` integrada; referencias A-G2 de cuatro atletas y A-G3 de diez, todavía sin producir/aprobar |
| Blender y MCP | Blender 4.5.13 LTS instalado; corrección del listener exclusivo, migración y concurrencia real de Windows **aceptadas formalmente por Vasquez**. No es aprobación de gameplay o arte |
| dream-loop | Original MIT vendorizado intacto; no ejecutado |
| Referencia visual aprobada | **No existe: bloquea G2**. Usuario con derechos y aprobación, o generador autorizado + aprobación humana; hoy no hay generador habilitado |
| Base visual de la nueva iteración | Captura real G1 que está evaluando el usuario; «no es mala» no aprueba A-G2/A-G3 ni acredita dream-loop, aceptación humana o FPS |
| Preview 5v5 y menú de desarrollo | **Implementados y verificados en 0.2.0**. Diez cuerpos reales, regresión micro y controles de IA; no Carrera/Partido rápido ni aceptación G3 |
| Control dinámico | **Implementado y revisado en 0.3.0-preview**, input schema 2; base preservada antes de comenzar §4.3 |
| Jugabilidad de §4.3 | **Implementada y exportada en 0.4.0-preview**. Pipeline integral 196/196; fuente/EXE headless y con GPU, arranque normal y veinte PNG del artefacto comprobados. Fuentes y paquete aprobados técnicamente por Vasquez; 0.3 permanece histórica |
| Simulación | Autoridad headless implementada: diez o cuatro actores, Jolt, balón, IA, pase/foco, goles, pausa, reanudaciones, regates y faltas/acumuladas; contratos y pruebas nativas en `docs\MICRO_SLICE.md` |
| Presentación | Escena `res://match/match.tscn` integrada con input nativo, cámara, HUD y diez o cuatro atletas provisionales; sin audio. Exportación y revisión técnica tienen evidencias separadas |
| Builds conservadas | G1 en `build\windows\FutsalG1-20260909.exe`; 0.2 en `FutsalPreview-0.2.0.exe`, 0.3 en `FutsalPreview-0.3.0.exe` y copia fija actual `FutsalPreview-0.4.0.exe`, dentro de la misma carpeta. `FutsalG1.exe` conserva la ruta de lanzamiento compatible; identidades y evidencias en TOOLING |
| Sensación humana, crítica >=8/10, rendimiento 1080p60 | Gates pendientes; las pruebas técnicas no conceden esas notas ni miden mando-a-píxel |
| Equipo de desarrollo observado | RTX 2000 Ada Generation Laptop GPU: **8188 MiB de VRAM dedicada (~8 GiB)** y driver **595.95**, verificados con `nvidia-smi`; CPU Intel Core Ultra 9 185H, 16 núcleos/22 lógicos; RAM 63,4 GiB e Intel Arc Pro. Comando/evidencia en MVP; no prueba FPS ni GPU efectiva de Godot |
| Estado compartido | Backend local; no sustituir un puente de estado ausente con logs o git notes manuales |

**Ejecución integral 0.4, coordinación, 2026-09-14:** `All` **196/196** en
`tools\godot\runtime\preview-20260914T173159Z-2299ed7ae9a849a1a0cbcf7a43d4f930\result.json`.
Incluye física 1522/1522, HUD 682/682, cámara 8339/8339 y pase/foco 345/345;
son subconjuntos, no sumas de casos únicos. Las cuatro orientaciones de córner
mantienen ambos paneles de instrucciones fuera de la portería atacada.
Capturas del EXE en `build\evidence\0.4.0-preview\gameplay`, procedentes del All
191/191 `preview-20260914T161724Z-92b1a73a68a944c49b48ddf4d2bf2d52`: su ejecutable
es byte-idéntico al candidato del cierre 196/196, SHA-256 `af23eb5c…ce2a0f`.
No se sustituyeron esas imágenes ni las builds históricas. Arranque normal final,
sin smoke, diagnóstico ni `--fixed-fps`, y cotejo de cinco EXE/veinte PNG en
`tools\godot\runtime\coordinator-normal-04-promoted-4de8288e7ced411daeba4443b859fc68\result.json`.
Vasquez cerró los hallazgos de fuente del HUD, tooling y oráculo de metadatos,
y aprobó estructuralmente el paquete `af23…`. La corrección final del oráculo
pasó 247/247 como ejecución posterior; el All conserva sus 235 originales.
El fallo de suspensión del validador se corrigió mediante solicitudes temporales
de disponibilidad de Windows, no aumentando límites ni cambiando políticas
globales. El cierre también comprueba drenaje acotado de salida y promoción
protegida: diagnóstico Foundation 915/915, procesos nativos 110/110 y helper de
promoción 49/49, sin confundirlos con pruebas del juego. Diagnóstico causal,
comandos y límites de esta evidencia en TOOLING.

**Comprobación independiente de preparación Godot, coordinación, 2026-09-09:**
`pwsh -NoProfile -File .\tools\godot\Test-Godot.ps1`, **639/639** tras corregir
el filtrado de dispositivo de teclado; runner nativo 199/199, fuente 90/90 en
headless y 94/94 con render; `.exe` Windows 91/91 en headless y 95/95 con render
(subconjuntos del total, no pruebas adicionales).
Informe: `tools\godot\runtime\20260909T144120Z-14b82e679f1e4477abd1f48d4db4a1f4\result.json`.
Esta verificación se refiere a esa ejecución de preparación, no a todos los informes
posteriores ni a los gates de producto. El 207/207 anterior no cubría la ruta nativa
de eventos de teclado que fallaba; no se usa como prueba de esos controles.
Comandos y artefactos actuales en TOOLING.

**Evidencia de revisión MCP aportada por Bishop, 2026-09-09:** migración real
verificada dos veces y pruebas de concurrencia con un solo proceso listo;
smoke de la sesión ganadora 17/17. La suite de revisión registra 26/26 sin skips.
Informes: `tools\mcp\runtime\revision-tests.json`,
`tools\mcp\runtime\migration-result.json` y `tools\mcp\runtime\overlap-result.json`.
La revisión posterior de Vasquez aceptó código, migración y runtime Windows.
Coordinación repitió las regresiones y verificó el addon instalado; la aceptación
no se extiende a plataformas no ejecutadas ni a los gates del juego.

**Comprobación independiente de componentes G1, coordinación, 2026-09-09:**
simulación **315/315**, con 24/24 trayectorias y 50/50 tiros (subconjuntos),
27 negativas esperadas y sin errores de motor. Informe:
`tools\godot\runtime\core-independent-01a178a28ce9444fab6ccd8eaf2d80fb\result.json`.
HUD **275/275**, con 16 diagnósticos de validación esperados. Son recorridos nativos
de los componentes, no una prueba de su conexión en la escena principal.
`--fixed-fps 60` acelera pasos físicos: no representa FPS renderizados.

La revisión de integración detectó después que continuar una pausa durante un gol
restauraba la fase, pero no el vuelo del balón. Bishop corrigió esa rama y amplió
la batería a **322/322**, repetidos por coordinación. Revertir únicamente el arreglo
en una copia privada reprodujo exactamente dos fallos (320/322), sin cambiar los
tests. Evidencia:
`tools\godot\runtime\core-resume-independent-1084eae341fa4905aad90b7e5e6b05cf`.

La escena principal ya tiene **170/170** comprobaciones nativas de integración,
repetidas por coordinación: 372 eventos de teclado, 203 de ejes y 120 de botones
de mando; cero errores de integración o negativas de comandos. Evidencia:
`tools\godot\runtime\integration-independent-f4f2a6f0435347518d3463aed4c36daf`.
El arranque predeterminado, sin sustituir la escena por un runner, produjo además
**71/71** en modo headless mediante el diagnóstico opt-in:
`tools\godot\runtime\main-smoke-independent-1bf61bae39004164bb7584f94c0fc41d`.
Ninguna de estas dos ejecuciones headless acredita el render ni un mando físico.

Vasquez aprobó técnicamente simulación, HUD e integración y revisó estáticamente
la corrección del alias del instalador. Sus dos observaciones no bloqueantes del
runner se cubrieron posteriormente con **180/180** comprobaciones y pruebas
negativas de salida/desconexión descritas en `docs\MICRO_SLICE.md`.
Vasquez cerró también la revisión de ese delta, tooling/exportación y la ruta
diagnóstica del ejecutable con **APPROVE técnico**, sin bloqueantes pendientes.

**Verificación independiente de la entrega local:** pipeline diagnóstico 692/692,
alias del instalador 13/13 y validación G1 97/97 del runner; arranques fuente
79/84 y `.exe` 85/90, con cuatro actores y la GPU NVIDIA verificada. La última
repetición incluye la exclusión explícita de capturas provisionales del PCK:
`tools\godot\runtime\g1-20260909T194405Z-461a8b7c505d431e92786d0c0a7301a4`.
El `.exe` también arrancó sin diagnóstico y salió normalmente tras las iteraciones
solicitadas. Esto no cierra la valoración humana de G1 ni los gates de arte/FPS.

Mantener diferenciados: configuración, descarga, instalación, arranque, conexión MCP,
ejecución de una operación, arte generado, integración en motor y aceptación.
Ninguno de esos estados prueba automáticamente el siguiente.

## 2. Responsables y hand-offs

| Miembro | Entregable propio | Acuerdo necesario / revisión independiente |
|---|---|---|
| Ripley | Alcance, MVP, prioridad, balance y criterios de salida | Vasquez revisa aceptación; propietarios revisan viabilidad |
| Hicks | Control, balón, cámara y game feel | Bishop: tick/estado; Lambert: contactos/animación; Vasquez: prueba de juego |
| Bishop | Stack, dominio/autoridad, persistencia y evolución a servidor | Hicks/Ferro verifican integración; Vasquez revisa fallos y contratos |
| Lambert | Look, cancha, atleta, rig, materiales y animación | Hicks: respuesta/contactos; Ferro: importación; crítica de Vasquez + Ripley |
| Hudson | IA, porteros y reglamento arcade de futsal | Bishop: comandos/estado; Hicks: acciones; Vasquez: escenarios |
| Ferro | Herramientas, MCP, builds, pipeline y distribución local | Bishop revisa reproducibilidad; Lambert valida Blender/exportación |
| Vasquez | Casos de prueba, rendimiento, accesibilidad y revisión | Pruebas propias revisadas por Bishop o especialista del área |
| Newt | Flujos de UX, personalización, XP y audio integrado | Ripley: reglas; Bishop: transacciones; Lambert/Hicks: presentación |

Squad conserva coordinación; Scribe, Ralph y Rai sus funciones especiales.
Reunir expertos no equivale a reservar ocho jornadas humanas ni a activar agentes
sin límite. Cada tarea futura nombra un propietario de archivos y un revisor distinto.
Cambiar una interfaz compartida exige acordarla primero con sus consumidores.

## 3. Camino crítico y estimación orientativa

```text
G0 preparación técnica sobre el stack elegido
  -> G1 micro slice: control + balón + cámara
  -> G2 prueba visual integrada y medible
  -> G3 partido 5v5 completo
  -> G4 plantilla / editor / XP / Partido rápido
  -> G5 demo candidata verificada

Referencia A-G2 de cuatro atletas con derechos y aprobación -> entrada visual de G2
(aportada por el usuario, o generada con autorización y aprobación humana)

Rama experimental autorizada desde G1: preview 5v5 + menú de desarrollo (§4.1)
  -> evidencia de escala/suelo/movimiento; no promoción automática a G2/G3/G4
```

| Gate | Trabajo y salida | Dependencia | Rango de trabajo activo orientativo |
|---|---|---|---|
| G0 | Decisión documentada, herramientas/diagnóstico verificados y contratos mínimos | Acceso local y herramientas disponibles | 1–3 días |
| G1 | 1 humano de campo vs 1 IA de campo + 2 porteros; prueba de sensación | G0 técnico aceptado | 1–2 semanas |
| G2 | La misma micro slice de cuatro atletas con cancha/animación/luz/audio representativos | G1 aceptado + referencia A-G2 aprobada | 2–4 semanas |
| G3 | 5v5, sustituciones, IA sin balón y reglas; revalidar calidad con diez atletas | G2 aceptado + referencia A-G3 aprobada para su prueba visual | 2–4 semanas |
| G4 | Dos modos, 12 jugadores, editor, 100 XP y +3, guardado y tres dificultades | G3 aceptado | 2–3 semanas |
| G5 | Integración, accesibilidad, optimización, pruebas de sesión y build local | G4 aceptado | 1–2 semanas |

Son rangos de esfuerzo orientativos para iteración con revisión humana; confianza
inicial baja, no plazos garantizados de agentes de IA. No sumarlos como fecha prometida
sin conocer dedicación, experiencia, proveedores y revisiones. Excluyen esperas de
permisos, aprobación de referencias, compras o cambios grandes de dirección. Reestimar
tras G1 y G2 con velocidad de trabajo y evidencia reales.

**Regla de bloqueo:** si falla sensación o prueba visual, no empezar el producto
G3/G4 para aparentar avance. La autorización del 2026-09-10 permite únicamente
el experimento 5v5 y menú técnico de §4.1 para investigar la escala y corregir G1.
Fuera de esa excepción se permite especificar interfaces y diseñar tests, pero no
construir menús de producto, progresión ni volumen de contenido por delante del gate.
Si un cambio posterior rompe un gate anterior, reabrirlo y bloquear la promoción.

## 4. Paquetes de trabajo ejecutables

La siguiente lista define futuros encargos acotados, no una orden de ejecutarlos todos.

| Paquete | Propietario | Depende de | Salida comprobable / revisor |
|---|---|---|---|
| P0.1 Investigación y selección | Bishop | Ninguna | Decisión y matriz documentadas en `docs\STACK_DECISION.md`; validar hipótesis con G1/G2, revisión Hicks/Ferro pendiente de evidencia |
| P0.2 Preparación de herramientas | Ferro; corrección MCP acotada de Bishop | Alcance de instalación autorizado | Godot/templates/diagnóstico verificados independientemente; MCP Windows aceptado por Vasquez. La corrección posterior del alias del instalador Godot tiene 13/13 comprobaciones y aprobación técnica de Vasquez |
| P0.3 Brief visual y rúbrica | Lambert | Requisitos del MVP | Dirección en `docs\ART_DIRECTION.md`, referencias lícitas, cámara objetivo y criterios; revisión Ripley/Vasquez |
| P0.4 Contratos y reglamento base | Bishop + Hudson, archivos separados | P0.1 | Comandos/estado, modos, regla de gol y reloj versionados; revisión Hicks |
| P1.1 Simulación local desacoplada | Bishop | G0 técnico, P0.4 | Autoridad invocable sin UI; pruebas básicas de tick/estados; revisión Hicks/Vasquez |
| P1.2 Movimiento y balón | Hicks | P1.1 | Conducción, pase, tiro, rebote y posesión con respuesta medible; revisión Vasquez |
| P1.3 Rival, porteros y cámara | Hudson (IA), Hicks (cámara) | P1.2 | Escenarios 1v1 + porteros jugables y reiniciables; revisión Vasquez |
| P1.4 Prueba de sensación | Vasquez | P1.3 | Sesión con evaluadores, clips, incidencias y gate G1; revisión Ripley/Hicks |
| P2.1 Referencia y asset representativo | Lambert | G1, P0.3, referencia A-G2 con derechos y aprobación | Cuatro atletas, cancha, rig y materiales para cámara elegida; crítica independiente, sin puntuar solo un render externo |
| P2.2 Integración audiovisual | Lambert + Hicks; Newt en audio | P2.1 | Contactos, movimiento, iluminación, sonido y feedback dentro del motor; revisión Vasquez |
| P2.3 Prueba visual y perfil micro | Vasquez | P2.2 | Escalera upstream de cinco tiers, captura del ejecutable, perfil y pruebas humanas separadas; revisión Ripley/Bishop, salida G2 |
| P3.1 Partido 5v5 y rotaciones | Hudson + Hicks, contratos de Bishop | G2 | 10 activos, 12 por plantilla, cambios legales y reglamento v1; revisión Vasquez |
| P3.2 IA táctica y escala | Hudson | P3.1 | Apoyos, cobertura, transición y parámetros de dificultad verificables; revisión Hicks/Vasquez |
| P3.3 Prueba completa de partido | Vasquez | P3.2, referencia A-G3 aprobada de Lambert | Dos tiempos, reglas, sensación y nueva crítica de diez atletas contra A-G3, con rendimiento real; salida G3 revisada por Bishop/Ripley |
| P4.1 Guardado y transacciones | Bishop | G3; contrato XP aprobado | Recuperación, migraciones y claves idempotentes; revisión Vasquez/Newt |
| P4.2 Editor y progresión | Newt | P4.1 | Escudo, kits, 12 jugadores, asignación de bolsa y resultados; revisión Ripley/Vasquez |
| P4.3 Partido rápido y modos | Newt + Hudson | P4.1, P3.2 | Generación automática de ambos equipos y tres dificultades, sin mutar carrera; revisión Vasquez/Bishop |
| P4.4 Prueba del flujo completo | Vasquez | P4.2 y P4.3 | Creación → partido → +3 → guardado → recarga; salida G4 revisada por Ripley |
| P5.1 Accesibilidad y optimización | Newt (UX), Hicks/Bishop/Lambert según perfil | G4 | Remapeo, legibilidad y correcciones guiadas por medición; revisión Vasquez |
| P5.2 Build y sesión candidata | Ferro + Vasquez, tareas separadas | P5.1 | Build local reproducible y 10 partidos sin pérdidas/bloqueos; salida G5 revisada por Bishop/Ripley |

La persistencia mínima del checkpoint de prueba puede existir en G1 como soporte
técnico; el producto de carrera, wallet, editor y pantallas de progreso esperan G4.
No implementar un transporte de red para «prepararse» antes de demostrar el juego.
P0.1–P0.3 tienen entregables documentales/operativos, no gates autoaprobados.
El diagnóstico técnico de P0.2 no implementa P1.1 ni demuestra aceptación de G0.

### 4.1. Paquete experimental 0.2.0 — contrato histórico implementado

Esta sección conserva la base validada. La petición posterior de cambio/pase
autoriza §4.2, que sustituye humano fijo, pase neutro y semántica de configuración
de IA; sus resultados todavía no se heredan de los de 0.2.0.

**Alcance del 2026-09-10:** partir de la captura real G1 del usuario, corregir
parqué en movimiento, luces/sombras y legibilidad/sprint; disponer de diez atletas
reales para juzgar cancha y proporciones. Es una excepción a la prohibición previa
de cualquier 5v5, **no G3 aceptado, competición, carrera, editor, XP ni Partido rápido**.
Conserva entrenamiento de 120 s, reposiciones G1, un humano fijo y geometría física.
No introduce cambios de jugador, sustituciones, dificultades ni reglas adicionales.
La composición, menú e integración siguientes están implementados y comprobados
en fuente y ejecutable. `docs\MICRO_SLICE.md` documenta la API y sus regresiones;
`docs\TOOLING.md` identifica la exportación y la revisión técnica. No implica
aceptación humana, artística o de rendimiento.

#### Propiedad y secuencia acotadas

| Propietario | Archivos / responsabilidad de este paquete |
|---|---|
| Ripley | Solo `docs\MVP.md` y este plan: alcance, defaults, interfaces y escenarios. Esta revisión es la alineación de diseño, sin fanout ni código |
| Bishop | `game\match\simulation\*.gd`, pruebas nativas de simulación y actualización de `docs\MICRO_SLICE.md`: composición, setup/snapshot, IA básica y mutador de IA. La asignación acotada de IA no transfiere el futuro reglamento/táctica G3 de Hudson |
| Lambert | Archivos visuales de `game\match\presentation\arena\`, `athletes\` y `ball\`: suelo/líneas, iluminación, sombras, silueta y sprint; no host, input ni autoridad. Solo recursos propios/locales |
| Newt | Nuevo componente autónomo `game\match\presentation\development\match_dev_menu.gd` y `match_dev_menu.tscn`, HUD y sus pruebas de UI: controles, etiquetas, foco y señales; no editar el host ni llamar directamente a la simulación |
| Hicks | `game\match\match.gd`, `game\match\match.tscn`, input, cámara e integración/pruebas nativas de entrada: arranque explícito, reconciliación de vistas, pases, pausa/modal y expectativas de smoke según modo |
| Ferro | **Solo después** de integrar y validar los cambios: exportación y validación de fuente/ejecutable. No sustituir pruebas nativas ni empezar la exportación de una composición a medias |

La asignación original separó las piezas independientes; Hicks integró la API de
Bishop y las vistas de Lambert/Newt. Coordinación comprobó el conjunto y la última
exportación después de la preparación de Ferro. La revisión independiente del delta
se registra en TOOLING, sin trasladar la aprobación del G1 histórico.
Sin puente de estado no escribir historiales, decisiones o logs.

#### Modo, setup y snapshot

| Superficie implementada | Contrato exacto |
|---|---|
| `MatchSetup.Mode` | Enum `MICRO_1V1 = 0`, `PREVIEW_5V5 = 1`; `mode: Mode = Mode.MICRO_1V1` |
| `MatchSetup.new()` | Mantiene los cuatro actores, posiciones y `ai_actor_ids = [1, 2, 3]` actuales |
| `MatchSetup.preview_5v5() -> MatchSetup` | Factoría estática del preset siguiente, `mode = PREVIEW_5V5`, IA `[1, 2, 3, 4, 5, 6, 7, 8, 9]` |
| `start/reset(setup: MatchSetup = null) -> Error` | Firmas y semántica existentes; `null` sigue siendo micro, nunca infiere modo por tamaño de arrays. Validar todo antes de cambiar composición |
| `MatchSnapshot` | Añade solo `mode: MatchSetup.Mode` y `ai_actor_ids: Array[int]`; copia ordenada/desacoplada de la IA efectiva. `actors` y `actor(id)` siguen dando identidad/equipo/rol/control humano |
| Arranque del host | `_ready()` solicita explícitamente `start_match(MatchSetup.preview_5v5())`; `start_match(null)` conserva la regresión micro. No cambiar el default del core para forzar el nuevo arranque |

**Identidades conservadas:** `HUMAN_ID = 0`, `RIVAL_ID = 1`,
`HOME_KEEPER_ID = 2`, `AWAY_KEEPER_ID = 3`. Micro usa `[0, 1, 2, 3]`;
preview usa IDs contiguos `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]`.
HOME: campo `[0, 4, 6, 8]`, portero `2`; AWAY: campo `[1, 5, 7, 9]`,
portero `3`; solo `0` humano. `ACTOR_IDS` conserva su significado micro por
compatibilidad, pero deja de dirigir bucles de composición/presentación.
Cada ID activo posee su propio cuerpo en el World3D privado y una vista sin
colisiones duplicadas. Reutilizar malla/rig no sustituye cuerpos ni snapshots.

Preset preview, pies en metros `(X, Y, Z)`; HOME mira `Vector2.RIGHT`,
AWAY `Vector2.LEFT`. Balón `(-1.45, 0.12, 0)`, velocidades lineal/angular cero:

| HOME | AWAY |
|---|---|
| `0: (-2, 0, 0)` | `1: (2, 0, 0)` |
| `2: (-18.5, 0, 0)` | `3: (18.5, 0, 0)` |
| `4: (-8, 0, -6)` | `5: (8, 0, -6)` |
| `6: (-8, 0, 6)` | `7: (8, 0, 6)` |
| `8: (-13, 0, 0)` | `9: (13, 0, 0)` |

`copy()` conserva modo, ambos diccionarios, IA y estado inicial del balón.
Start/reset exige exactamente las claves del modo, roles fijos y validaciones
existentes de finitud, límites y no solapamiento. Un modo desconocido o setup
incoherente devuelve `ERR_INVALID_PARAMETER`, sin destruir el encuentro vigente.
No cambiar la escala 40 × 20 m/cápsulas/balón para mejorar artificialmente la imagen.

#### Mutación de IA, host y menú

| API implementada | Contrato |
|---|---|
| `MatchSimulation.set_ai_actor_ids(ids: Array[int]) -> Error` | Reemplaza atómicamente el conjunto de generación de IA; copia/ordena la entrada. Vacío apaga toda IA; nunca admite el humano `0` |
| Host `start_development_mode(mode: MatchSetup.Mode) -> Error` | Solicitud explícita «Aplicar modo y reiniciar»: crea el preset canónico, reinicia marcador/reloj/secuencias/vistas/cámara y defaults de IA; éxito cierra el panel y entra en `PLAYING`. Incluso elegir el mismo modo reinicia; una selección del desplegable por sí sola no |
| Host `set_ai_actor_ids(ids: Array[int]) -> Error` | Delega en el core y, solo con `OK`, sincroniza la copia de setup usada por `restart_match()` y presenta el snapshot efectivo |
| `MatchDevMenu.present(state: MatchSnapshot) -> Error` | Solo refleja modo, recuento y grupos de IA; snapshot nulo o modo desconocido devuelve `ERR_INVALID_PARAMETER` sin mutación parcial. No guarda, pausa ni decide física |
| Señales de `MatchDevMenu` | `mode_requested(mode: MatchSetup.Mode)`, `ai_actor_ids_requested(ids: Array[int])`, `close_requested()`; intenciones atendidas por el host, no cambios optimistas de autoridad |
| HUD | Añade `development_requested()`, `set_development_open(value: bool) -> void` y `set_mode(mode: MatchSetup.Mode) -> Error`; modo inválido se rechaza sin cambiar etiquetas. Las APIs actuales de marcador, carga, pausa y resultado se conservan |

El host rechaza modos desconocidos con `ERR_INVALID_PARAMETER` y propaga errores
del core; no sustituye setup, eventos, vistas o selección confirmada antes de `OK`.

Interruptores **sin grupos solapados**, activos por defecto salvo «no aplica»:

| Etiqueta del menú | IDs micro | IDs preview |
|---|---|---|
| IA rival — incluye portero | `[1, 3]` | `[1, 3, 5, 7, 9]` |
| IA compañeros — campo local | `[]`, deshabilitado/no aplica | `[4, 6, 8]` |
| IA portero local | `[2]` | `[2]` |

Derivar grupos de `team_id/role/human_controlled` del snapshot, no mantener otro
catálogo en la UI. Cada clic envía la lista completa resultante; un drill con un
grupo parcialmente activo se muestra «Parcial» y su activación habilita el grupo
entero. La UI refleja cambios confirmados y muestra los rechazos del host.

El mutador devuelve `ERR_UNCONFIGURED` antes de inicializar, `ERR_BUSY` durante
tick/entrega de eventos y `ERR_INVALID_PARAMETER` por duplicados, ID ausente o `0`;
mantiene `last_error` y la vía diagnóstica `command_rejected` con actor `-1`.
No filtrar errores silenciosamente. Se admite entre ticks en cualquier fase
inicializada, incluida pausa/fin, sin cambiar fase, reloj, marcador ni balón.
Aplicar el mismo conjunto es idempotente, sin limpiar decisiones de actores intactos.
Al quitar IA, neutralizar su intención y acción pendiente y reiniciar su temporizador;
el cuerpo permanece y frena con la física normal, conservando contactos. Al habilitar,
la siguiente decisión usa una secuencia nueva, sin teletransporte ni acción retenida.
No reiniciar secuencias aceptadas ni cooldowns al cambiar IA.
Esto apaga el generador autónomo, no invalida `submit_command` de los drills.
Gol/fuera y `restart_match()` conservan el modo y la IA efectiva; aplicar un preset
de modo restaura explícitamente sus defaults. Ninguna opción se persiste en disco.

Entrada: **F1** y botón **Desarrollo** dentro de pausa/resultado, navegable con mando,
teclado y ratón. Un solo modal recibe input.
`set_development_open` oculta/suspende únicamente el modal del HUD: no altera la
autoridad. Esc/B/Start en desarrollo vuelve a pausa/resultado, **no reanuda**
involuntariamente. Solo el host pausa con `MatchSimulation.set_paused`, difiere
operaciones si hay entrega de eventos y limpia input/carga; exige controles neutros
al continuar. No delegar pausa física en UI ni en `SceneTree.paused`.
El HUD identifica «5v5 experimental · Sin progresión/XP» o «1v1 de regresión»;
sus textos de pase se ajustan al modo.

#### Riesgos de compatibilidad cubiertos respecto al G1

- **Cuatro IDs incrustados:** `ACTOR_IDS`, `_create_world`, validación de setup
  y `id < 2` para rol; ampliar la lista sin corregir esto convertiría campos nuevos
  en porteros o dejaría cuerpos ausentes. Reconciliar cuerpos al cambiar modo,
  sin colisiones huérfanas ni colisiones entre autoridades.
- **Pases y IA:** G1 fijaba receptor `2`; core usaba `team_id`/`team_id + 2`;
  portero usaba `state.actor(team_id)` y rival protegía frente a `actor(0)`.
  Micro conserva pase al portero/devolución. En preview, input deja receptor `-1`;
  core selecciona compañero dentro de `pass_assist_degrees` (35° por defecto)
  por menor ángulo, luego distancia y luego ID; sin aim usa frente, sin candidato mantiene pase
  dirigido libre. Un receptor explícito sigue validándose y nunca fuerza giro
  fuera del cono. Porteros eligen campo de su equipo por distancia/ID; amenaza
  se busca entre rivales, no siempre en el humano. IA básica: un perseguidor de
  campo por equipo (distancia/ID), resto apoyo/cobertura separados desde sus spawns;
  mismos comandos y límites físicos, sin pretender táctica/dificultad G3.
  Las nuevas selecciones y coordinación se aplican solo a preview; micro conserva
  su comportamiento de IA como regresión.
- **Presentación de cuatro:** kits/dorsales indexados con arrays de cuatro,
  creación/interpolación de atletas y mensajes «Pase al portero» en host/HUD.
  Crear/eliminar vistas por IDs del snapshot, materiales por equipo/rol,
  reiniciar ambos snapshots al cambiar composición. Encuadre inicial de preview
  con diez atletas y cancha legibles, sin sacrificar seguimiento/lectura del balón.
- **Reinicio y copias:** `_restart_play()` creaba `Setup.new()`; conservar modo
  y toggles al reponer. Actualizar `copy()`, snapshot y setup cacheado del host.
  No cambiar los cuatro actores esperados de los drills micro para hacer pasar
  tests; sí actualizar el smoke de arranque ahora explícitamente preview.
  APIs modificadas y tests correspondientes se entregan juntos.

#### Escenarios de aceptación del paquete

| ID | Escenario / evidencia exigida |
|---|---|
| EXP-01 | Arranque normal: diez cuerpos físicos y diez vistas con IDs únicos, cuatro campos + portero por lado y solo `0` humano. Verificar colisiones/estado de los añadidos, no solo contar nodos de malla |
| EXP-02 | Preview → micro → preview y reinicio: 10/4/10, sin cuerpos/vistas/eventos antiguos; `start/reset(null)` y drills G1 conservan cuatro actores y comportamiento. Reinicio conserva IA; aplicar modo restaura defaults |
| EXP-03 | Cada grupo de IA on/off, incluido portero rival, y todos apagados: no acciones retenidas, cuerpos presentes, frenada física y secuencias válidas al activar; no reset de tiempo/marcador/balón. Mantener opciones tras gol, fuera y reinicio |
| EXP-04 | Modo/IDs/diccionarios inválidos, humano en IA, duplicados y reentrada: errores exactos sin mutación parcial. Cambiar un setup/snapshot ya entregado no modifica autoridad |
| EXP-05 | Pase dirigido a compañero nuevo, recepción/devolución de portero, tiro, gol y fuera en diez; rival y apoyos no forman un enjambre. Regresión del pase/devolución micro y misma asistencia, sin reglas competitivas nuevas |
| EXP-06 | Menú con teclado/mando/ratón, carga o sprint retenidos, pausa en gol/fuera, fin, pérdida de foco y desconexión: un único modal, sin disparo/continuación accidental, fase y vuelo restaurados correctamente |
| EXP-07 | Clips/capturas nativas antes/después del micro con cámara/acción comparables a G1; desplazamiento, giro, sprint y frenada. Comprobar parqué/líneas temporalmente estables, luz/sombras de contacto y siluetas, sin ocultar defectos con blur; nueva vista de diez para juicio humano de escala |
| EXP-08 | Exportación posterior validada de ambos modos, identificando build/renderer/GPU/resolución. Aceptación humana y medición real de frame times siguen separadas; ni headless, smoke, captura estática ni `--fixed-fps 60` acreditan FPS |
| EXP-09 | Abrir, cambiar, terminar y repetir ambos modos no invoca persistencia de carreras ni servicios de recompensa. Sin XP de prueba ni creación de plantillas persistentes; no reutilizar el flujo de Partido rápido |

La validación técnica de EXP-01–06 y EXP-08–09 está identificada en TOOLING.
Para EXP-07, ART_DIRECTION documenta un A/B continuo del shader de parqué,
con composición/cámara/poses idénticas y reproyección de puntos del suelo; no es
una nueva ejecución completa del G1 ni una prueba humana de sprint. La captura
actual de diez atletas está en `docs\images\preview-5v5.png`.
Los conteos/evidencias G1 de §1 son históricos, no resultados de este paquete.
La impresión del usuario sobre su captura es la base de trabajo, no aprobación
dream-loop. G1 humano, G2 con A-G2/cuatro, G3 con A-G3/diez, aceptación de animación
y medición de FPS continúan pendientes; no comparar cuatro contra diez ni heredar
notas. Prioridad a control/balón/cámara y estabilidad temporal del suelo sobre
cantidad de opciones. Sin llamadas a APIs externas, assets externos, commits/push ni trabajo de producto
G4; se conservan **12 = 2 porteros + 10 campo, 5 activos/7 suplentes, 100 XP
compartidos, +3 idempotente por victoria de carrera y Partido rápido aislado**.

### 4.2. Pase contextual y cambio de control — contrato histórico implementado

**Estado: implementado y con revisión técnica aprobada, 2026-09-10.** Se sustituye el
humano fijo de 0.2.0 sin abrir otros sistemas de G3/G4. Se conserva el ejecutable
previo como `build\windows\FutsalPreview-0.2.0.exe`; la revisión de control usa
`0.3.0-preview` e input schema 2. Sigue siendo entrenamiento de 120 s,
geometría 40 × 20 m, diez atletas por defecto y micro de cuatro seleccionable.

Cierre independiente: proceso nativo 72/72, preparación 819/819 y validación
completa 125/125; veredicto final APPROVE de Vasquez. Ejecutable de esta entrega
conservado como `build\windows\FutsalPreview-0.3.0.exe`; informes e identidades
en TOOLING. La siguiente iteración sustituye las reposiciones simplificadas,
no reinterpreta esta evidencia histórica ni concede aceptación humana o artística.

#### Autoridad e interfaces

| Superficie | Contrato |
|---|---|
| `PlayerCommand.Action.SWITCH_TEAMMATE = 4` | Se añade sin renumerar acciones existentes. Usa `aim` y exige `target_actor_id = -1`; solo el seleccionado puede ejecutarla, sin posesión ni cooldown de cambio |
| `MatchSnapshot.selected_actor_id: int` | Control vigente, inicialmente 0. Exactamente un HOME tiene `human_controlled = true`; `HUMAN_ID = 0` conserva identidad/default, no representa control actual |
| `submit_human_command(command)` | Admite únicamente al seleccionado vigente; próxima secuencia = última aceptada de ese actor + 1, incluidas las órdenes IA anteriores |
| `MatchSnapshot.ai_intent_actor_ids: Array[int]` | Preferencias completas, ordenadas y desacopladas |
| `MatchSnapshot.ai_actor_ids: Array[int]` | IA efectiva = intención menos seleccionado; nunca manda sobre el humano |
| `MatchSetup.ai_actor_ids` / `set_ai_actor_ids(ids)` | Cambio intencional: representan intención completa y admiten al seleccionado. Defaults `[0..3]` / `[0..9]`; `[]` apaga todo, sin inferencias ni habilitaciones implícitas |
| `MatchEvent.Kind.FOCUS_CHANGED = 9` | `actor_id` anterior, `target_actor_id` nuevo, `reason` = `off_ball_switch` o `pass`; llega por `event_raised` con estado ya coherente |
| `MatchInput.clear_for_focus_change()` | Cancela carga/pulsaciones y bloquea botones retenidos hasta liberarlos; no activa una nueva barrera de neutral ni detiene movimiento/sprint |
| `MatchHUD.set_selected_actor(actor) -> Error` | Presenta identidad/rol confirmados; null, no HOME o no humano se rechazan sin mutación parcial |

El cambio no modifica intención de IA: el anterior solo vuelve a IA si figuraba
en ella. El host conserva **intención**, no la lista efectiva, para reinicio.
Cambiar la preferencia latente del seleccionado no cancela su movimiento. Se
conservan validaciones de duplicados/IDs ausentes, atomicidad, idempotencia y copias.
Entradas públicas mutadoras, incluidos comandos, rechazan reentrada durante tick
o entrega de eventos; la generación IA utiliza aceptación interna.

#### Entrada, selección y transferencia

J/A emite `PASS` si el seleccionado posee el balón y `SWITCH_TEAMMATE` en caso
contrario, incluso con un compañero poseedor. Flechas físicas se añaden a
`move_*`, manteniendo WASD/stick; la dirección se muestrea al construir el comando
para aceptar dirección previa o ambas pulsaciones dentro del mismo frame.
Una pulsación produce una acción: mantener/repetición automática no encadena
cambios ni pases, tampoco tras una recepción. Pase tiene prioridad sobre tiro
simultáneo. Ctrl/LT conserva control cercano/contención.

Elegibles: compañeros HOME activos distintos, incluido el portero, sin radio máximo
arbitrario. Neutro: distancia planar al controlado y después ID. Con dirección:
conversión cámara→cancha, cono `pass_assist_degrees` de 35 grados y prioridad
ángulo/distancia/ID; origen del cambio = actor, asistencia física del pase = balón.
No candidato: switch rechazado con `ERR_UNAVAILABLE`; pase libre con receptor −1
y foco intacto. El pase neutro apunta al elegido; el tiro neutro conserva su frente.
Un receptor explícito no se sustituye ni fuerza asistencia fuera del cono con aim.

La patada `PASS` aceptada del seleccionado transfiere al receptor **efectivo** de
ese pase, antes de recibirlo; no basta encolar un comando. No transfiere un pase
de otro actor, fallo/contacto perdido/cooldown, pase libre o intercepción; nunca
concede posesión ni altera posiciones/velocidades/cooldowns/secuencias.
Resolver la acción del seleccionado antes del resto de acciones pendientes y
limpiar intención/acción de ambos al transferir, incluida IA del receptor con ID
inferior. Emitir `PASS` antes de `FOCUS_CHANGED`. Si el seleccionado recupera la
posesión antes de ejecutar `SWITCH_TEAMMATE`, rechazarlo sin convertirlo en pase.

#### Fases, desarrollo y presentación

Pausa, pausa de gol/fuera y fin conservan selección; fin no acepta acciones.
Inicio, reinicio y saque canónico vuelven a 0. Reinicio/saques conservan modo e
intención; aplicar modo restaura sus defaults. `start/reset(null)` sigue siendo
micro. La limpieza estricta de pausa, foco de ventana y desconexión se conserva;
no se reutiliza esa barrera para exigir soltar el stick en cada pase.

Desarrollo presenta preferencias completas por equipo/rol, incluyendo al
seleccionado: rival `[1,3]` / `[1,3,5,7,9]`, campo local `[0]` / `[0,4,6,8]`,
portero local `[2]`. Identificar suspensión por control humano y estado parcial;
campo local micro ya no es «no aplica». Ningún checkbox muta optimistamente el core.
Una sola marca humana cambia según snapshot, sin recrear vistas ni cambiar
identidad/kit/dorsal. HUD y posesión se refieren al seleccionado real.
Micro encuadra seleccionado y balón sin giro/salto; preview mantiene lectura de
los diez, balón y porterías. Portero seleccionado no recibe órdenes IA ni
devolución automática; fuera de foco las recupera según preferencia. No se añaden
controles especializados de guardameta.

#### Propiedad y aceptación

Bishop: core, regresiones nativas y MICRO_SLICE. Hicks: host/input/cámara, flechas,
integraciones, nueva prueba productiva `test_match_player_control.gd` y driver.
Newt: HUD/Desarrollo, solo marca dinámica del atleta y pruebas correspondientes.
Ferro: contratos del runner, schema/versionado, metadatos y documentación operativa.
Coordinación valida el conjunto/exportación; Vasquez revisa el delta independiente.

| ID | Recorrido exigido |
|---|---|
| F01 | Main real antes de drills: diez cuerpos, seleccionado 0, nueve IA; 10→4→10 y escala/regresiones conservadas |
| F02 | Cercano al controlado, no al balón; empates por ID; micro 0↔2 |
| F03 | Flechas/WASD/stick, dirección previa y simultánea en ambos órdenes, cono y ausencia de candidato |
| F04 | Mantener pase/echo/cambio de posesión no repite; liberación antes de otra pulsación |
| F05 | Compañero poseedor: switch no genera pase ni nueva posesión |
| F06 | Pase neutro/dirigido a campo/portero: foco en patada aceptada con balón libre, recepción física posterior |
| F07 | Cooldown/contacto/objetivo inválido/pase libre/intercepción no provocan transferencia indebida |
| F08 | 0→8 y 8→0 con IA pendiente; cancelación independiente del orden, secuencias crecientes y reentrada rechazada |
| F09 | Defaults/subconjuntos/parciales/latente/todo apagado sobreviven cambios y reinicios exactamente |
| F10 | Movimiento/sprint continúan, carga/acciones no migran; pausa/foco/desconexión exigen neutral |
| F11 | Gol/fuera/fin/reinicio/modo y snapshots/copias cumplen contrato |
| F12 | Marca única, identidad estable, HUD/Desarrollo y cámara coherentes; portero IA fuera de foco |

Conducir entradas productivas y eventos nativos; no sustituirlas por pruebas
aisladas de selección. Actualizar assertions fijas a 0 solo donde cambió el
contrato; el default previo a los drills sigue siendo 0. Separar devolución manual
del portero controlado de devolución IA fuera de foco, sin borrar la regresión.
Conservar negativas exactas, reporte incompleto fallido y watchdog. Estas pruebas
no conceden aceptación humana, puntuación artística ni 1080p60.

### 4.3. Iteración de jugabilidad 0.4 — implementación autorizada

**Contrato vinculante de `0.4.0-preview`, input schema 3.** El usuario autorizó
todo el paquete el 2026-09-10 y coordinación aceptó su Design Review. Esta sección
define el comportamiento exigido; el estado vigente de fuentes, revisión,
ejecutable y evidencias se registra en §1 y `docs\TOOLING.md`. El cierre requiere
entrega de los productores, integración, exportación y verificación independiente
de Vasquez. No se solicita otra aprobación de alcance.

La evidencia de 0.3 en §4.2 es histórica, no prueba de 0.4. Preservar
`build\windows\FutsalPreview-0.3.0.exe`, SHA-256
`6fe42916e7d91309044758439b96c48324ce967d1597f3f24872ff6dbd9192f6`,
sin sobrescribir sus informes ni los de 0.2/G1.

| Orden | Resultado exigido en micro y preview 5v5 |
|---|---|
| 1. IA aliada pasadora | Recuperación, apoyo y distribución; prioridad al humano con línea segura, alternativas y protección. Política y autoridad impiden finalizar intencionadamente; no borran goles físicos accidentales |
| 2. Reanudaciones y apuntado | Bandas, córners y meta con último toque, cruce completo, adjudicación, colocación localizada, plazo y consecuencias; cámara de córner y guía compartida con el lanzamiento |
| 3. Regates | Enganche y cambio de ritmo con L/X + dirección; gestos físicos cortos, recuperación y vulnerabilidad, sin teletransporte ni invulnerabilidad |
| 4. Faltas y balón parado | Contacto limpio/tardío/imprudente, directos, penalti de 6 m y sexta acumulada sin barrera, incluidas sus excepciones de ubicación |

#### 4.3.1. Compatibilidad y enums

Se conserva la autoridad en el `World3D` privado, los comandos validados y los
snapshots desacoplados. Exactamente un HOME es humano, incluido el portero 2;
IA efectiva = intención completa menos seleccionado. Se mantienen selección,
asistencia, secuencias y transferencia efectiva de §4.2 salvo los cambios
explícitos de reanudación de esta sección. No introducir setters públicos de
teletransporte, foco, falta o contador, ni un flag que esconda las reglas nuevas
a las regresiones antiguas.

| Enum existente | Valores estables y ampliación |
|---|---|
| `PlayerCommand.Action` | Conservar `NONE=0`, `PASS=1`, `SHOOT=2`, `TACKLE=3`, `SWITCH_TEAMMATE=4`; añadir `DRIBBLE=5`, `KEEPER_THROW=6`, `CHOOSE_RESTART_SPOT=7` |
| `MatchSnapshot.Phase` | Conservar `READY=0`, `PLAYING=1`, `GOAL_PAUSE=2`, `RESTART_PAUSE=3`, `PAUSED=4`, `FINISHED=5`; no renumerar ni confundir `READY` global con el subestado de saque |
| `MatchEvent.Kind` | Conservar `GOAL=0`, `PASS=1`, `SHOT=2`, `SAVE=3`, `RESTART=4`, `END=5`, `POSSESSION=6`, `TACKLE=7`, `BALL_CONTACT=8`, `FOCUS_CHANGED=9`; añadir `RESTART_CHANGED=10`, `DRIBBLE=11`, `FOUL=12` |

`PlayerCommand` añade
`restart_spot_choice: MatchRuleTypes.SpotChoice = DEFAULT`, significativo solo para
`CHOOSE_RESTART_SPOT`. `target_actor_id` se admite en `PASS` y `KEEPER_THROW`;
los demás comandos requieren −1. Actualizar validación, copia, límite de enum
y limpieza de todos los campos de acción, también en el fallback de movimiento.
Un lanzamiento de portero emite `PASS` con `launch_kind=KEEPER_THROW`.

Nuevo `game\match\simulation\match_rule_types.gd`, propiedad de Bishop: enums y DTOs
`RefCounted`, sin lógica de adjudicación ni dependencias de presentación.

| Enum de `MatchRuleTypes` | Valores exactos |
|---|---|
| `RestartKind` | `NONE=0`, `KICK_IN=1`, `CORNER=2`, `GOAL_CLEARANCE=3`, `DIRECT_FREE_KICK=4`, `INDIRECT_FREE_KICK=5`, `PENALTY_6M=6`, `ACCUMULATED_FREE_KICK=7` |
| `RestartStage` | `NONE=0`, `STOPPED=1`, `PLACEMENT=2`, `READY=3`, `IN_PLAY=4` |
| `SpotChoice` | `DEFAULT=0`, `TEN_METRE=1`, `OFFENCE_SPOT=2` |
| `ControlContext` | `DISABLED=0`, `LIVE=1`, `RESTART_AIM=2`, `RESTART_DEFEND=3` |
| `FoulVerdict` | `NONE=0`, `CLEAN=1`, `LATE=2`, `RECKLESS=3` |
| `GestureKind` | `NONE=0`, `CUT=1`, `PACE_CHANGE=2`, `TACKLE=3`, `FOOT_KICK=4`, `KEEPER_THROW=5` |
| `LaunchKind` | `FOOT_PASS=0`, `FOOT_SHOT=1`, `KEEPER_THROW=2` |
| `Border` | `NONE=0`, `NEG_X=1`, `POS_X=2`, `NEG_Z=3`, `POS_Z=4` |
| `ContactKind` | `BALL_ACTOR=0`, `ACTOR_ACTOR=1` |
| `DecisionKind` | `NONE=0`, `GOAL=1`, `RESTART=2`, `FOUL=3` |
| `PeriodState` | `REGULATION=0`, `EXTENDED_KICK=1` |

#### 4.3.2. DTOs, snapshots y eventos

Los nombres de tipos siguientes pertenecen a `MatchRuleTypes`. Las copias no
comparten arrays, DTOs mutables ni referencias a cuerpos de la autoridad.

| DTO / grupo | Campos tipados |
|---|---|
| `RestartState`: identidad | `id, awarded_team_id, taker_actor_id: int`; `kind: RestartKind`; `stage: RestartStage`; `spot, offence_spot: Vector3`; `border: Border` |
| `RestartState`: contacto del lanzamiento | `launch_contact_id: int = -1` |
| `RestartState`: elección y reloj | `spot_choice: SpotChoice`; `has_spot_choice: bool`; `stage_started_tick, placement_end_tick, ready_tick, deadline_tick: int` |
| `RestartState`: restricciones | `minimum_opponent_distance: float`; `direct_opponent_goal_allowed, requires_direct_shot, other_actor_touched: bool` |
| `BoundaryCrossing` | `border: Border`; `fraction: float`; `position: Vector3`; `goal_team_id: int` |
| `ContactEvidence` | `contact_id, tick, actor_id, other_actor_id: int`; `kind: ContactKind`; `point, normal, actor_velocity, other_velocity: Vector3`; `tackle_started_tick, ball_touch_tick: int`; `ball_touched_first: bool` |
| `ActorPlacement` | `actor_id: int`; `position: Vector3`; `forward: Vector2` |
| `RuleDecision` | `kind: DecisionKind`; `scoring_team_id, offender_actor_id, victim_actor_id, contact_id: int`; `foul_verdict: FoulVerdict`; `position: Vector3`; `reason: StringName`; `restart: RestartState`; `counts_as_accumulated_foul: bool = false` |

`RestartState.id` identifica la reanudación; `deadline_tick=-1` significa sin
cuenta de cuatro segundos, no vencimiento inmediato. `contact_id` identifica un
episodio físico: deduplicar el golpeo y sus notificaciones, no contar cada callback
como un toque nuevo.

| Superficie existente | Campos añadidos |
|---|---|
| `MatchSnapshot` | `restart: MatchRuleTypes.RestartState`, nunca nulo e inicialmente `NONE`; `accumulated_fouls: Vector2i`, faltas cometidas por HOME/AWAY |
| `MatchSnapshot`: control | `human_control_context: MatchRuleTypes.ControlContext`; `human_allowed_actions: Array[PlayerCommand.Action]`; `selected_can_move: bool` |
| `MatchSnapshot`: historial físico/táctico | `last_touch_tick, last_pass_actor_id, last_pass_target_actor_id, last_pass_tick: int` |
| `MatchSnapshot`: periodo y ejercicio | `period_state: MatchRuleTypes.PeriodState`; `extended_restart_id, extended_kick_event_id: int`; `training_exercise: MatchSetup.TrainingExercise` |
| `ActorSnapshot` | `ball_contact_reachable, ball_in_hands: bool`; `gesture_kind: MatchRuleTypes.GestureKind`; `gesture_started_tick, gesture_duration_ticks: int`; `gesture_direction, gesture_contact_position: Vector3` |
| `MatchEvent` | `restart: MatchRuleTypes.RestartState`; `launch_kind: MatchRuleTypes.LaunchKind`; `gesture_kind: MatchRuleTypes.GestureKind`; `foul_verdict: MatchRuleTypes.FoulVerdict`; `contact_id: int`; `contact_point: Vector3` |

Los nuevos eventos se entregan mediante `event_raised`, sin otra autoridad de UI.
Motivos de `RESTART_CHANGED`: `awarded`, `placement`, `ready`, `taken`, `expired`,
`spot_changed`. `FOCUS_CHANGED` incorpora `restart_taker`. En `FOUL`, `actor_id`
identifica al infractor y `target_actor_id` al jugador afectado; los contadores
confirmados proceden del snapshot.

#### 4.3.3. APIs y límites entre módulos

Nuevo `game\match\simulation\match_rules.gd`, propiedad de Hudson. Todas sus
funciones son estáticas y puras: no mutan argumentos, nodos, reloj, selección,
contadores o física.

| Función de `MatchRules` | Parámetros | Retorno |
|---|---|---|
| `first_crossing` | `previous: Vector3, current: Vector3, tuning: MatchTuning` | `MatchRuleTypes.BoundaryCrossing` |
| `boundary_decision` | `crossing: MatchRuleTypes.BoundaryCrossing, state: MatchSnapshot, tuning: MatchTuning` | `MatchRuleTypes.RuleDecision` |
| `contact_decision` | `contact: MatchRuleTypes.ContactEvidence, state: MatchSnapshot, tuning: MatchTuning` | `MatchRuleTypes.RuleDecision` |
| `expiry_decision` | `state: MatchSnapshot, tuning: MatchTuning` | `MatchRuleTypes.RuleDecision` |
| `placement_plan` | `state: MatchSnapshot, tuning: MatchTuning` | `Array[MatchRuleTypes.ActorPlacement]` |
| `allowed_actions` | `actor_id: int, state: MatchSnapshot` | `Array[PlayerCommand.Action]` |
| `can_move` | `actor_id: int, state: MatchSnapshot` | `bool` |
| `constrain_displacement` | `actor_id: int, displacement: Vector3, state: MatchSnapshot, tuning: MatchTuning` | `Vector3` |
| `launch_error` | `command: PlayerCommand, state: MatchSnapshot, velocity: Vector3, effective_target_actor_id: int, tuning: MatchTuning` | `Error` |
| `project_to_penalty_area_line` | `point: Vector3, defending_team_id: int, state: MatchSnapshot, tuning: MatchTuning` | `Vector3` |

La entrada existente de `match_ai.gd` continúa siendo
`decide(actor: MatchSnapshot.ActorSnapshot, state: MatchSnapshot, tuning: MatchTuning, held_seconds: float) -> PlayerCommand`.
Despacha entre juego y reanudación sin romper el caller de simulación; la
denominación «make_command» de un handoff no autoriza renombrarla. El primer tramo
de Hudson se limita a política HOME en `PLAYING` y `test_match_ai_tactics.gd`,
sin adelantar ediciones del core/DTOs.

Nuevo `game\match\simulation\match_launch.gd`, propiedad de Bishop:
`static resolve(state: MatchSnapshot, command: PlayerCommand, tuning: MatchTuning) -> MatchLaunch.Solution`.

| Campos de `MatchLaunch.Solution` | Semántica |
|---|---|
| `error: Error`, `executable: bool`, `reason: StringName` | `error=OK, executable=false` permite visualizar una preparación todavía no ejecutable |
| `tick, actor_id, restart_id, effective_target_actor_id: int` | Observación/contexto y receptor realmente asistido |
| `launch_kind: MatchRuleTypes.LaunchKind` | Pase/tiro con pie o lanzamiento con manos |
| `origin, direction, velocity: Vector3` | Origen real, dirección planar efectiva y velocidad inicial con componente vertical real |
| `speed, power: float` | Velocidad y potencia disponibles con el tuning vigente, no alcance ni llegada garantizados |

| Consumidor | API acordada |
|---|---|
| `MatchSimulation` | Añadir `query_human_launch(request: PlayerCommand) -> MatchLaunch.Solution` |
| Input | Conservar `sample(state: MatchSnapshot, camera: BroadcastCamera, delta: float) -> PlayerCommand`; añadir `get_preview_command() -> PlayerCommand`, copia o `null` |
| Cámara | Conservar `follow(state: MatchSnapshot, ball_at: Vector3, delta: float, snap: bool = false) -> void` y `screen_direction_to_court(direction: Vector2) -> Vector2`; añadir `sync_context(state: MatchSnapshot) -> void` y `react(event: MatchEvent) -> void` |
| Host | `set_aim_guide_enabled(enabled: bool) -> void`; `is_aim_guide_enabled() -> bool`; `start_training_exercise(exercise: MatchSetup.TrainingExercise) -> Error` |
| HUD | `present_restart(state: MatchSnapshot) -> Error`; `set_restart_aim_hint(message: String) -> void`; `show_restart_feedback(message: String, restart_id: int, actor_id: int) -> Error`; `clear_restart_feedback() -> void` |
| Desarrollo | Señales `aim_guide_requested(enabled: bool)` y `exercise_requested(exercise: MatchSetup.TrainingExercise)`; confirmación `set_aim_guide_enabled(enabled: bool) -> void` |
| Nuevo `presentation\aim\world_aim_guide.gd` | `present(solution: MatchLaunch.Solution, render_ball_position: Vector3, enabled: bool) -> void`; `clear() -> void` |
| Atleta | Conservar las firmas de `present`, `react`, `reset_pose`; añadir `sync_context(before: MatchSnapshot, state: MatchSnapshot) -> void` antes de cada `present`, para interpolar ticks y balón reales |

Los nombres de componentes pueden ser aliases de scripts precargados; no requieren
abrir el editor para registrar clases. `query_human_launch` solo consulta al
seleccionado HOME y no consume secuencia/input, cambia `last_error`, emite eventos,
crea otro mundo ni altera posesión/cooldowns. La autoridad vuelve a observar y
validar el estado al ejecutar y llama al **mismo `MatchLaunch.resolve`**, incluidas
asistencia y validación reglamentaria. Se conservan el origen del pase neutro,
cono desde el balón, desempates y tratamiento del receptor explícito de §4.2.

`get_preview_command()` devuelve una caché del único `sample()` del tick: no
consulta `Input` ni avanza carga. `render_ball_position` solo alinea la interpolación
con `BallView`; no sustituye `Solution.origin` ni entra en el cálculo autoritativo.
La guía no instancia simuladores, añade colisiones o reconstruye física privilegiada.
El contexto del atleta procede de los mismos snapshots del host; no incorpora
otro reloj de simulación ni deduce el anclaje de manos desde una pose renderizada.
La ayuda y los rechazos de un saque tienen una superficie visible propia en el
HUD, vinculada a reanudación y actor; no dependen de `show_event`, cuyo panel
normal se oculta durante las reanudaciones. No modifican ni tapan la cuenta.

#### 4.3.4. IA, contacto, faltas y regates

| Área | Obligación de implementación |
|---|---|
| Autoridad aliada | Usar equipo y selección actuales, no un flag de procedencia falsificable. HOME no seleccionado no ejecuta `SHOOT`, remates disfrazados de pase sin receptor efectivo ni conducción deliberada hacia la boca de gol. Guardas al aceptar y al ejecutar; limitar intención/movimiento/control, nunca borrar después un gol físico legítimo |
| Táctica aliada | Humano con línea segura primero; después alternativa segura. Si están tapadas, proteger y desplazarse lateralmente/atrás; tras espera acotada, intentar distribución legal aunque pueda ser interceptada. Evitar devolución automática inmediata al anterior pasador IA, ping-pong y espera indefinida |
| Rival y preferencias | Conservar ataque AWAY en juego abierto y tiros humanos, incluido portero seleccionado. No inventar generadores para actores deshabilitados ni cambiar intención al transferir foco |
| Contacto de falta | Evidencia real entre rivales, tiempo de la entrada y movimiento relativo. Fallar sin tocar al rival o un roce ordinario no son faltas. Balón primero con contacto moderado es limpio; contacto tardío/al jugador primero es falta; velocidad de cierre imprudente puede sancionarse aunque hubiera balón primero |
| Contabilización | Una decisión por episodio; sin ventaja. El core incrementa solo si `counts_as_accumulated_foul=true`, no por cualquier evento `FOUL`. Umbrales de sensación son tuning validado, no números presentados como FIFA |
| Regates | `DRIBBLE` lateral respecto al frente produce `CUT`; dirección adelantada o neutral produce `PACE_CHANGE`; dirección puramente hacia atrás no añade otro regate. Contacto, impulso/aceleración, duración y recuperación acotados por autoridad; balón disputable, sin teleport ni inmunidad. La animación sigue al gesto, no lo adjudica |

Tuning inicial acordado entre autoridad y reglas, propiedad de Bishop. Son
parámetros de sensación que requieren pruebas físicas, no umbrales FIFA:

| Campo de `MatchTuning` | Inicial | Validación |
|---|---|---|
| `foul_challenge_window_ticks: int` | 18 ticks, 0.3 s | 1–60 ticks |
| `foul_min_closing_speed: float` | 0.8 m/s | 0.1–4.0 m/s |
| `foul_reckless_closing_speed: float` | 9.5 m/s | 2.0–20.0 m/s; mayor que el mínimo |

Registrar velocidad previa al contacto, no la velocidad ya anulada por el
deslizamiento. «Balón primero» debe pertenecer a esa misma ventana de entrada;
una posesión antigua no concede inmunidad.

#### 4.3.5. Reglamento, geometría y reanudaciones

Fuente primaria contrastada por Hudson:
[FIFA Futsal Laws of the Game 2025/26, actualización de septiembre](https://assets.the-afc.com/downloads/referees/Futsal---Laws-of-the-Game-2025-2026---Sep-12-update.pdf).
No hay edición 2026/27 verificada en este contrato. Dos cláusulas fijan excepciones:

- Law 12, PDF p.74: «however, no accumulated foul is recorded when a penalty kick
  is awarded.» Una infracción sancionada con penalti de 6 m **no incrementa
  acumuladas**; tampoco lo hacen indirectos ni vencimientos.
- Indirectos, PDF p.93: «following an imaginary line parallel to the touchline».
  En esta cancha, proyectar **conservando Z y modificando X** hasta la frontera
  reglamentaria del área; Y corresponde al balón colocado. No usar punto euclídeo
  más cercano.

Bishop declara en `MatchTuning` estas constantes `float`; Hudson y Lambert las
consumen sin duplicar números ni convertir el área en rectángulo:

| Constante | Definición | Valor |
|---|---|---|
| `PENALTY_RADIUS` | Radio de los arcos | 6.0 m |
| `GOAL_POST_CENTER_Z` | `GOAL_WIDTH / 2 + POST_THICKNESS / 2` | 1.54 m |
| `GOAL_POST_OUTER_Z` | `GOAL_WIDTH / 2 + POST_THICKNESS` | 1.58 m |
| `PENALTY_STRAIGHT_LENGTH` | `2 * GOAL_POST_OUTER_Z` | 3.16 m |

Centros transversales de los arcos: Z ±1.58. Conservar abertura interior de
portería **3 × 2 m**, postes de 0.08 m y cancha 40 × 20 m. La corrección visual
se limita a líneas del área y coherencia de postes, no rediseña la arena.

`RESTART_PAUSE` contiene el ciclo común; no renumerar fases globales:

| Subestado | Transición y autoridad |
|---|---|
| `STOPPED` | Congelar balón, cancelar acciones antiguas, adjudicar equipo/punto/sacador |
| `PLACEMENT` | Colocar balón/sacador y solo jugadores que incumplen restricciones. No reset colectivo ni cambio de spawns/secuencias por una salida. Mínimo autoritativo de 60 ticks; cámara de córner entra en un máximo de 45 ticks |
| `READY` | Contacto y controles disponibles; cámara sincronizada antes del muestreo. Sin ACK de render ni espera indefinida headless. Donde corresponde, `deadline_tick = ready_tick + 240`; se ejecuta solo con `tick < deadline_tick` |
| `IN_PLAY` | Golpeo aceptado lleva la fase a `PLAYING`. Reanudar el balón antes de aplicar la velocidad; no sobrescribir el lanzamiento con un `resume` posterior |

Sacador de campo elegible por distancia/ID; portero obligatorio para meta. HOME
cede foco al sacador; AWAY nunca toma el foco humano. La IA sacadora habilitada
actúa legalmente tras espera fija desde `READY`, no mediante carga humana
automática. Si está deshabilitada, no se inventa un generador: rige el vencimiento
que corresponda. Pausa congela ticks, colocación, plazo y vuelo; carga, rechazo,
consulta, cambio de IA o elección de punto no renuevan el plazo.

| Reanudación | Preparación y ejecución | Consecuencia a los cuatro segundos |
|---|---|---|
| Banda | Pie, punto de salida, adversarios a 5 m | Banda contraria en el mismo punto |
| Córner | Arco correspondiente; 5 m medidos **desde el arco**, no simplemente desde el balón | Meta contraria |
| Meta | Manos del portero dentro del área, adversarios fuera de ella; **sin 5 m universal**. Balón en juego al liberarse y moverse claramente, sin esperar a salir del área | Indirecto contrario proyectado a la línea del área en dirección paralela a la banda |
| Directo / indirecto | 5 m y restricciones de área aplicables | Indirecto contrario desde el punto, proyectado si corresponde |
| Sexta acumulada y posteriores (`DFKSAF`) | Sin barrera y disparo directo obligatorio: `SHOOT`, no `PASS`; portero a ≥5 m, resto detrás del balón y conforme al área | Indirecto contrario |
| Penalti de 6 m | Portero y resto en posiciones reglamentarias; lanzamiento con tiro | **No tiene cuenta de cuatro segundos** |

Los indirectos son parte necesaria de las consecuencias, no un sistema omitible.
Primera a quinta falta acumulable: directo. Sexta y posteriores: 10 m; cuando la
infracción está dentro de la **franja longitudinal** entre la línea de 10 m y la
meta defensora, fuera del área real, permitir elegir punto de infracción o marca
de 10 m. No usar distancia radial. Dentro del área prevalece el penalti de 6 m,
sin incrementar acumuladas. `CHOOSE_RESTART_SPOT` solo selecciona esos puntos
legales y no reinicia el plazo.

| Lanzamiento directo | Portería rival sin toque de otro jugador | Propia portería sin toque de otro jugador |
|---|---|---|
| Banda, meta o indirecto | Meta del equipo de esa portería | Córner contrario |
| Córner, directo, penalti o DFKSAF | Gol permitido si cumple el cruce físico | Córner contrario |

Conservar tipo/origen/sacador para resolver esas restricciones y el segundo toque.
`RestartState.launch_contact_id: int = -1` conserva el episodio original del
lanzamiento en copias, snapshots, eventos y evidencias. La originalidad se decide
por identidad y separación física, no con una gracia temporal: un episodio
nuevo en el tick siguiente ya puede ser un segundo toque.
Otro **jugador** que toca físicamente levanta la restricción de gol indirecto;
poste/suelo no. Un segundo contacto separado del sacador antes de otro jugador
origina indirecto; no implementar aquí el detalle de doble apoyo accidental.
Asignar posesión por proximidad no equivale a último toque. Se conserva el cruce
barrido de la esfera completa: manda el primer borde y, si hay empate exacto en
una esquina, la línea de meta. Un cruce válido de gol no se convierte después
en otra salida; contactos posteriores no cambian la concesión.

#### 4.3.6. Periodo, pausa y gol

Un periodo de **120 s efectivos**, sin descanso ni modos de dificultad. Las
acumuladas persisten en goles, saques y pausa; se reinician al comenzar otra
sesión, salvo el estado inicial declarado de un ejercicio catalogado.

Existe una única excepción al cierre de regulación: **penalti de 6 m o DFKSAF
pendiente**, con `period_state=EXTENDED_KICK`, `extended_restart_id` y
`extended_kick_event_id`. No es prórroga ni tiempo extra de juego general.

- `seconds_remaining` queda en cero; completar preparación y lanzamiento
  pendiente sin reiniciar reloj. Penalti sin cuatro segundos; DFKSAF conserva
  su cuenta y exige tiro directo.
- Resolver ese lanzamiento hasta gol, fuera, balón físicamente detenido o toque
  de un jugador distinto del portero defensor. Rebote/parada de ese portero no
  concede automáticamente otro ataque ni termina por sí solo el desenlace.
- Sin ataque posterior ni reanudación ordinaria adicional. El indirecto por
  vencimiento de DFKSAF no abre tiempo extra. Pausa congela también la extensión.

Preservar el contrato físico anterior: gol una sola vez, vuelo y rebotes en red
durante `GOAL_PAUSE`, restauración lineal/angular al continuar tras pausa. El
saque normal tras gol sigue perteneciendo al campo **0/1 del equipo que encajó**,
no al seleccionado accidental; mantiene su reset canónico y foco 0. Las nuevas
salidas no usan ese reset. `FINISHED` conserva el foco terminal y no recoloca.

#### 4.3.7. Input, cámara de córner y guía

| Contexto | Entrada y presentación |
|---|---|
| Juego abierto | Un `sample()` por tick. K/B carga y dispara al soltar; J/A sigue siendo pase/cambio por pulsación. L/X produce un flanco de regate. Conservar Ctrl/LT y Shift/RT |
| Reanudación propia | Dirección apunta, el sacador no camina. J/A mantiene acción rápida; meta usa `KEEPER_THROW`, no tiro con el pie. Penalti/DFKSAF respetan acciones legales. L/X es elección contextual cuando existe alternativa de punto |
| Reanudación rival | Retransmisión; humano puede moverse, contener, esprintar y cambiar compañero, sujeto a distancias/colocación. No robar balón parado |
| Prioridad | Una acción: pase → regate/elección contextual → tiro/robo. Mantener/repetición no encadena; los botones heredados requieren liberación, no neutralizar todo el stick para habilitar un saque |
| Continuidad | Mantener proyección a pista mientras continúa la misma dirección sostenida; recapturar al neutralizar/cambiar dirección. Un giro de cámara no cambia por sí solo apuntado, receptor o movimiento |

**Apuntado fino en saque propio listo:** Ctrl + A/D o flechas izquierda/derecha;
en mando, LT + componente lateral del stick izquierdo. Ajuste continuo a
**30 grados/s**, sin desplazar al sacador ni ampliar el plazo. Produce el mismo
`aim` del resolver compartido, no una acción nueva del dominio. Ctrl/LT conserva
su función de control cercano en juego abierto.

En córner propio, transición suave detrás del sacador, algo elevada y hacia el
área. Derivar orientación de la esquina, no de un único signo fijo. Encuadrar
balón, sacador y opciones sin paredes/redes ni deformar cancha/atletas; comprobar
las cuatro orientaciones. La cámara se sincroniza con el progreso autoritativo
de colocación antes del muestreo, sin ACK de render.
La orientación acoplada al balón se limita al córner y a su transición; al
completarse el regreso se conserva el encuadre broadcast calculado para los
atletas. La ayuda de apuntado no debe tapar la portería atacada en las capturas
1080p. El límite de salto al cambiar foco se mide entre imágenes consecutivas,
no entre esperas que puedan abarcar varios renders.

El regreso empieza al `PASS/SHOT` **aceptado**, no al pulsar ni recibir. Rechazo
mantiene preparación; pausa, reinicio, vencimiento y cambio de reanudación
restauran el contexto correcto. En un pase de saque, el orden es
`PASS → FOCUS_CHANGED → RESTART_CHANGED(taken)`, con snapshot atómico y receptor
efectivo. Tiro/pase libre no inventan selección; conservar movimiento/sprint.

La guía propia usa la imagen aportada como referencia conceptual, sin copiar
interfaz, logos o assets. Visible al cargar K/B y preparar saques/libres/penaltis;
flecha de dirección y potencia real, anclada al mundo y legible sobre parqué,
sin ocultar atletas o confundirse con líneas. La barra representa la carga
disponible. La meta coloca autoritativamente el balón en el anclaje de manos:
consulta y liberación usan ese balón real, no un hueso renderizado.

Primera entrega: flecha, **sin arco ni zona de caída**. No añadir elevación/efecto
manuales; cualquier futura curva requeriría física elevada real. La guía no
garantiza llegada: defensores, rebotes y movimiento pueden cambiar el resultado.
No forzar recepción ni teletransportar para cumplir el dibujo.

Invalidar la caché al soltar, ejecutar, perder posesión, cancelar, cambiar
foco/contexto, pausar o reiniciar. Nunca mostrar intención rival ni dejar flechas
huérfanas. Preferencia F1 efímera, conservada entre reinicios/modos; no cambia
reloj o intención IA. Apuntar no pausa ni amplía los cuatro segundos.

#### 4.3.8. Ejercicios F1 de producción

Catálogo fijo para probar el paquete en ambos modos, no modo de carrera ni consola
de teletransporte. Añadir `MatchSetup.training_exercise: TrainingExercise = FREE_PLAY`,
con copia y validación de valores desconocidos, y estas APIs:

| API de `MatchSetup` | Retorno / finalidad |
|---|---|
| `static for_exercise(mode: Mode, exercise: TrainingExercise) -> MatchSetup` | Candidato de setup del catálogo; `start/reset` validan antes de mutar |
| `attack_direction(team_id: int) -> Vector3` | Dirección de ataque derivada coherentemente del ejercicio |

| `MatchSetup.TrainingExercise` | Valor |
|---|---|
| `FREE_PLAY` | 0 |
| `KICK_IN` | 1 |
| `CORNER_POS_X_NEG_Z` | 2 |
| `CORNER_POS_X_POS_Z` | 3 |
| `CORNER_NEG_X_NEG_Z` | 4 |
| `CORNER_NEG_X_POS_Z` | 5 |
| `GOAL_CLEARANCE` | 6 |
| `DRIBBLE_CUT` | 7 |
| `DRIBBLE_PACE_CHANGE` | 8 |
| `DIRECT_FREE_KICK` | 9 |
| `PENALTY_6M` | 10 |
| `ACCUMULATED_FREE_KICK` | 11 |

`FREE_PLAY` conserva los defaults. Los ejercicios de saque comienzan mediante
`start(setup)` en `STOPPED` y recorren todo el ciclo de producción. Los dos
córners de extremo negativo espejan coherentemente equipos, ataque y posiciones
para probar cuatro córners propios; no hay selector arbitrario de orientación.
El ejercicio de sexta declara su contador inicial en HUD, sin fabricar un
historial de faltas ni admitir valores arbitrarios de debug.

Aplicar ejercicio reinicia sesión con confirmación explícita del menú; seleccionar
una opción no lo aplica. `start_training_exercise` conserva modo, intención IA y
preferencia de guía del host. Inicio/reset siguen siendo la entrada pública de
setup; no se conceden setters de estado a UI o pruebas.

#### 4.3.9. Propiedad y orden de integración

Esta propiedad rige el pase 0.4; no reescribe las asignaciones históricas de §4.2.

| Propietario | Escritura exclusiva |
|---|---|
| Bishop | `game\match\simulation` salvo `match_ai.gd`/`match_rules.gd`; DTOs, `match_launch.gd`, catálogo/setup, snapshots/tuning, cuerpos/contactos y aplicación de decisiones; `test_match_simulation.gd`, `test_match_preview.gd`, **`test_match_player_control.gd`** y nuevas pruebas físicas/integradas; `docs\MICRO_SLICE.md` |
| Hudson | `match_ai.gd`, nuevo `match_rules.gd`; nuevos `test_match_ai_tactics.gd` y `test_match_rules.gd`. No crear el duplicado `test_match_ai.gd`, ni editar simulador/DTOs |
| Hicks | `game\match\match.gd`, `match.tscn`, input/cámara y `game\project.godot`; `test_match_integration.gd`, `test_match_preview_integration.gd`, nuevos `test_match_camera.gd` y `test_match_gameplay_runtime.gd`; adaptación de **`game\diagnostics\match_smoke.gd`** y nuevo **`game\diagnostics\gameplay_smoke.gd`** si hace falta. No HUD/Desarrollo ni atleta/core |
| Newt | HUD/Desarrollo, nueva carpeta `game\match\presentation\aim`; pruebas HUD/Desarrollo y `test_match_aim_guide.gd`. No host ni atleta |
| Lambert | `athlete_view.gd`, `test_match_visuals.gd` y pruebas de gestos; `game\match\presentation\arena\match_arena.gd` solo para líneas de área y coherencia visual de postes. No cámara, host o física |
| Ferro | Validadores PowerShell, bootstrap y pruebas de herramientas, configuración de exportación, README/TOOLING; integración de rutas/manifiestos. No `game\project.godot` ni host/driver |
| Ripley | Esta sección y `docs\MVP.md`, §2.3; coherencia de alcance y contrato |
| Vasquez | Revisión independiente de integración/evidencia; un productor no acredita su propia aceptación |

Orden: **DTOs/tuning → reglas/IA y consumidores → integración física →
conexión final del host/driver → validadores/exportación nueva → revisión Vasquez**.
Paralelizar solo archivos independientes; no editar un módulo ajeno para suplir
una interfaz pendiente. Hicks fija producto `0.4.0-preview` y schema 3; Ferro
consume esos valores, no los duplica en `project.godot`. Actualizar pruebas y
conteos con cada cambio de interfaz. Los antiguos tests «fuera → centro» deben
esperar las nuevas reanudaciones, no ejecutarse bajo un flag de reglas antiguas.

#### 4.3.10. Capturas y aceptación finita

El driver de Hicks usa la escena real, teclado/mando y el punto de entrada de
ejercicios de producción. No modifica cuerpos o estado privado. Las capturas
son del viewport nativo a **1920 × 1080**, sin retoque, no imágenes de un mockup
ni de una segunda simulación.

Cada ejecución escribe únicamente en un **directorio de salida propio de ese
run**, sin sobrescribir fuentes o artefactos ajenos/anteriores. Solo coordinación
copia el conjunto final seleccionado a `build\evidence\0.4.0-preview\gameplay`;
ese destino no es la salida compartida de los drivers concurrentes.

| PNG por modo | Momento real requerido |
|---|---|
| 1–4 | Cada córner propio preparado, cámara y guía visibles |
| 5 | Carga de tiro en juego |
| 6 | Meta preparada con balón en manos |
| 7 | Liberación del lanzamiento del portero |
| 8–9 | Contacto de enganche a izquierda/derecha |
| 10 | Contacto de cambio de ritmo |

Total: **20 PNG**, diez por cada modo. Manifiesto con modo/ejercicio, tick, fase,
selección, reanudación, cámara, entrada aplicada y evento aceptado cuando
corresponda. Ferro integra rutas/manifiesto/validadores; no sustituye el driver.
Son candidatas de revisión de interacción, **no score artístico ni medición de
FPS**. No iniciar dream-loop, atribuir notas o aprobar gates humanos por ellas.
Los recorridos diagnósticos usan `--fixed-fps 60` para reproducir la secuencia
de entradas sin depender de la agrupación de frames. No es una prueba 1080p60;
el arranque normal conserva la temporización en tiempo real.

Los criterios siguientes definen la aceptación técnica de 0.4; su resultado
vigente se enlaza desde §1 y TOOLING. Los IDs G01–G32 identifican casos de este
paquete, no sustituyen los gates G0–G5. Aplicar
ambos modos y teclado/mando donde corresponda; conservar negativas y watchdogs.

| ID | Criterio de aceptación |
|---|---|
| G01 | ABI estable, selección HOME/portero 2, listas IA desacopladas y efectiva exacta |
| G02 | Política y guardas aliadas bloquean tiro/remate disfrazado/conducción a gol; humano y AWAY conservados |
| G03 | Pase seguro prioritario al humano, alternativas, apoyo y salida acotada; sin bucle IA↔IA ni espera indefinida |
| G04 | Último toque físico, esfera completa, primer borde y precedencia de gol; rebotes legítimos |
| G05 | Bandas de ambos equipos: punto, sacador, colocación localizada y 5 m |
| G06 | Córners en cuatro esquinas: arco, adjudicación y gol directo permitido |
| G07 | Metas de porteros 2/3: manos, origen/velocidad reales, adversarios fuera del área |
| G08 | Ciclo completo; `READY` después de preparación; headless progresa sin ACK de render |
| G09 | Cada vencimiento reglamentario, incluido límite exacto; carga/repetición no amplían tiempo |
| G10 | Goles directos prohibidos, propia puerta, segundo toque y habilitación por otro jugador |
| G11 | Pase aceptado transfiere receptor efectivo; rechazo, tiro, pase libre e intercepción no fabrican foco |
| G12 | Un flanco/acción, secuencias crecientes, sin replay al cambiar foco; movimiento/sprint continuos |
| G13 | Propio listo apunta; rival listo permite defender/cambiar; sacador IA legal y preferencias respetadas |
| G14 | Cámara detrás/arriba en cuatro orientaciones; balón, sacador y opciones visibles sin paredes/redes |
| G15 | Entrada sostenida no rota apuntado; retorno solo tras golpeo; rechazo/pausa/vencimiento limpian el contexto |
| G16 | Consultas repetidas no consumen input ni mutan autoridad; ningún segundo `sample()` |
| G17 | Guía y lanzamiento coinciden en origen, asistencia, potencia y velocidad inicial; revalidación ante cambios reales |
| G18 | Guía solo propia, F1 conservado en sesión, limpieza completa y reloj independiente |
| G19 | Enganche a ambos lados y cambio de ritmo físicos, vulnerables y acotados; sin spam mantenido |
| G20 | Limpia/tardía/imprudente por contacto y velocidad relativa; roce/fallo sin contacto no sancionados |
| G21 | Directo y penalti de 6 m, geometría real de área y colocación reglamentaria |
| G22 | Contadores por equipo; sexta+, 10 m, elección longitudinal, prioridad del penalti y ausencia de barrera |
| G23 | Pausa congela relojes y vuelo; snapshots privados y aislamiento entre mundos |
| G24 | Gol/red/parada existentes, saque al equipo que encajó y cierre de regulación a 120 s sin reset terminal; única extensión según G29 |
| G25 | Driver con escena/APIs de producción; tests antiguos de fuera adaptados, sin flag para esconder las reglas |
| G26 | Suites/conteos coherentes, ejecutable 0.4 independiente, hash de 0.3 intacto y revisión final Vasquez |
| G27 | Proyección longitudinal sobre arcos reales y desempate exacto de esquina |
| G28 | Acumuladas explícitas y deduplicadas, penalti sin incremento conforme al pasaje 2025/26 confirmado |
| G29 | Extensión exclusiva de penalti/DFKSAF, plazos distintos y terminación física sin ataque adicional |
| G30 | Catálogo F1 en ambos modos, cuatro orientaciones propias coherentes y conservación de preferencias |
| G31 | Ejecución nativa teclado/mando y 20 PNG específicos con manifiesto concordante, en salidas propias por run |
| G32 | Adjudicación y presentación comparten arcos de 6 m/tramo de 3.16 m; proyección longitudinal y portería física/visual 3 × 2 m coherentes |

La implementación autorizada no incluye fuera de juego, tarjetas, expulsiones,
ventaja, reglamento completo del portero, sustituciones, carrera, XP, guardado,
red ni dificultades de producto. No se presenta como cumplimiento FIFA completo
ni hereda aceptación humana, artística o de rendimiento de otras entregas.

## 5. Criterios de salida por gate

### G0 — preparado para iniciar una tarea de implementación autorizada

- Roster/casting/custom agents consistentes y seleccionables por sus archivos persistentes.
- Elección Godot 4.7.2 razonada, avisos MIT/terceros y ruta de exportación Windows
  comprobables. Renderer/driver, Jolt y 60 Hz identificados en la evidencia.
- Ferro presenta instalación/operación verificadas o bloqueo preciso por herramienta.
- Godot/diagnóstico tienen comprobación independiente y MCP Windows tiene aceptación
  formal de Vasquez. Mantener versiones/parches/conteos vinculados a su ejecución;
  ninguna de esas pruebas sustituye la validación de la escena jugable.
- Bishop/Hicks/Hudson acuerdan comandos, tick, estado de balón/partido y reglas base.
- Riesgos y capacidades no disponibles quedan explícitos. G0 técnico puede permitir
  un encargo de micro slice gris aunque falte referencia aprobada; **no permite
  aprobar arte ni el gate G2**. El usuario ya autorizó la implementación de G1;
  esa autorización no elimina los gates antes de G3/G4. La excepción experimental
  posterior de §4.1 tampoco los aprueba ni autoriza el producto completo.

### G1 — la sensación merece continuar

- Micro 1v1 de campo + porteros que permite secuencias reales de recuperar, conducir,
  pasar/devolver, tirar, parar, marcar y reiniciar; no una animación pregrabada.
- Matriz de balón: al menos 20 trayectorias de rebote/contacto y 50 tiros con distintas
  velocidades/ángulos, incluidos postes y línea de gol; cero goles duplicados o falsos,
  tunneling reproducible o bloqueos en el conjunto de aceptación.
- Al menos 3 evaluadores independientes del implementador juegan con mando.
  Media >=8/10 en respuesta, posesión, tiro y cámara; ninguna categoría <7.
  Una crítica automática de vídeo no sustituye una prueba de control.
- Objetivos de respuesta de `docs\MVP.md` medidos con método declarado.
  Input-a-estado y mando-a-píxel son métricas distintas; la segunda requiere captura
  o instrumento adecuado, no deducirla solo de FPS.
- Lista cerrada de problemas aceptables y cero defectos críticos abiertos.

### G2 — calidad visual dentro del motor, no solo en una imagen

- Referencia **A-G2 aprobada, de cuatro atletas**: una imagen del usuario con derechos,
  o generación autorizada y posterior aprobación humana del archivo/hash.
  No hay ninguna actualmente; sin referencia aprobada, este gate queda bloqueado.
- Arte visible en el mismo encuadre y acción que el juego: una cancha excelente,
  atleta reutilizable, materiales local/visitante y animaciones sin deslizamiento grave.
  Igualar resolución 1920 × 1080 nativa, cámara/FOV, acción, condiciones y recuento:
  un humano de campo, un rival de campo y dos porteros; pase al portero/devolución.
- Capturas y vídeo de gameplay de la build evaluada; ningún score prestado de un
  render Blender, referencia externa o imagen de marketing.
- Crítico independiente con contexto limpio y **prompt upstream íntegro**
  de `.github\skills\dream-loop\SKILL.md`: forma (techo 3), luz/color (5),
  materiales (7), detalle (9) y equivalencia (10). Cada puerta inferior debe
  superarse antes de exceder su techo. **Nota >=8**, sin redondear ni promediar;
  declarar mayor tier completamente superado, bloqueos y directivas pendientes.
  Ninguna valoración ponderada sustituye esta escalera.
- **Pruebas separadas** de movimiento, contactos, lectura y mando según la sección 9
  de `docs\ART_DIRECTION.md`: instrumentación y participantes reales, cero defectos
  críticos. Su valoración humana no se mezcla con la nota del crítico estático.
- **Además del >=8, rendimiento aceptable:** 1080p nativos, trabajo sin VSync/limitador
  p95 <=14,5 ms y p99 <=16,0 ms; presentación a 60 Hz p95/p99 <=16,67 ms + 0,5 ms,
  menos del 0,1 % >20 ms y sin tirones recurrentes de 33,3 ms.
  Calentar 120 s y medir tres recorridos de 180 s con build/GPU/driver declarados.
  Presupuestos de memoria/geometría y protocolo completo: sección 7 de ART_DIRECTION.
  En G2 se mide el micro; casos de diez atletas y tres dificultades se repiten en G3/G4.

### G3 — 5v5 sin perder la calidad anterior

La preview experimental de §4.1 no satisface este gate por tener diez cuerpos.

- Dos equipos con 12 identidades cada uno; 5 activos y 7 suplentes por equipo.
  Cada plantilla contiene 2 porteros y 10 de campo; un portero y cuatro de campo activos.
  Cambios con salida antes de entrada y reutilización de suplentes, sin seis en pista.
- Reglamento arcade v1 cerrado, escenarios de faltas/reanudaciones y ambos tiempos.
  IA de apoyo, segundo palo, marcaje, cobertura, recuperación y portero demostrable.
- Repetir los gates de sensación, visual y rendimiento con los 10 atletas activos,
  IA, balón, sombras y efectos reales. Una micro slice rápida no basta.
- Lambert aporta **A-G3**, referencia propia aprobada de diez atletas; igualar cámara,
  resolución y acción de esa fase. No comparar cuatro contra diez y declarar que
  pasa Tier 1, ni heredar la nota obtenida con A-G2.
- Estado de partida válido sin depender de una cámara, HUD o componente de audio.

### G4 — producto local sin exploits accidentales de progreso

- Editor completo del MVP, dorsales/roles válidos y equipaciones distinguibles.
- Pruebas del presupuesto compartido 100, topes y +3 una vez por victoria de carrera.
- Partido rápido genera ambos equipos, ofrece tres dificultades y no escribe carrera.
- Guardado versionado, transacción terminal idempotente, backup y migraciones probadas.
- Salida, cancelación, revancha y cierre inesperado cumplen la tabla de `docs\MVP.md`.
- UX de mando sin pérdida de foco; saldo, gasto y errores de guardado comprensibles.

### G5 — candidato de demo local

- 10 encuentros completos incluyendo cambios, pausas y recargas; sin crash, deadlock,
  pérdida de saldo ni bloqueos de IA. Incidencias no críticas documentadas con límites.
- Revisión de accesibilidad y pruebas de controles, contraste, texto, audio y vibración.
- Perfil final sobre build candidata, no una escena vacía; repetir tras optimizaciones.
- Build reproducible, instrucciones de ejecución y revisión por alguien distinto al autor.
- No subir, publicar ni generar release externa sin un nuevo permiso explícito.

## 6. Matriz mínima de pruebas de producto

| ID | Escenario | Evidencia esperada |
|---|---|---|
| ROSTER-01 | Crear, editar, guardar, cargar y sustituir | Siempre 12 IDs únicos; 2 porteros/10 campo; 1+4 activos |
| ROSTER-02 | Tres presets de quinteto con jugadores compartidos | Reutilización legal; no crear 15 ni duplicados dentro del quinteto |
| XP-01 | Nueva carrera y asignación parcial/completa | Una concesión de 100; total = saldo + asignaciones |
| XP-02 | Saldo insuficiente, negativos, fracciones, rol ajeno y topes | Rechazo sin mutación parcial |
| XP-03 | 20 victorias de carrera distintas | Total 160: 100 iniciales + 60 por victorias, conservados entre saldo y asignaciones |
| XP-04 | Callback duplicado, doble clic y recarga de victoria | El mismo `(career_id, match_id)` suma solo 3 una vez |
| XP-05 | Derrota, empate, abandono y ventaja parcial | Cero ganancia; no falsear finalización |
| XP-06 | Todos los jugadores al tope y nueva victoria | +3 conservados sin asignar, nunca descartados |
| XP-07 | Dos intentos simultáneos de gasto del mismo saldo | Un resultado serializable; sin saldo negativo |
| QUICK-01 | Generar/ganar/perder/repetir/abandonar en cada dificultad | Hash/estado de todas las carreras intacto; datos rápidos efímeros |
| SAVE-01 | Fallo antes/durante/después del commit del resultado | Recuperación consistente; 0 o 1 recompensa confirmada, nunca 2 |
| SAVE-02 | Checkpoint, cierre inesperado, continuar y revancha | ID conservado al continuar; nuevo ID al empezar otro partido |
| SAVE-03 | Migración, versión desconocida y corrupción | Presupuesto conservado; copia sana intacta y error accionable |
| AI-01 | Apoyos, cobertura y recuperación en semilla conocida | No enjambre; decisión legal y dificultad explicable sin boosts |
| RULE-01 | Gol, fuera, penalti, sexta falta, 4 s y sustitución | Resultado único y reinicio correcto según reglamento v1 |
| INPUT-01 | Mando/teclado, remapeo y desconexión | Pausa/recuperación segura; sin acciones atrapadas |
| PERF-01 | Micro y 5v5 en captura estandarizada | Métricas reales, contexto reproducible, aprobado solo al alcanzar objetivo |
| ART-01 | A-G2/cuatro atletas y A-G3/diez atletas | Referencias aprobadas por separado; misma cámara/resolución/acción/recuento en cada comparación; cinco tiers sin medias |

Vasquez convertirá estos casos en pruebas del runner acordado para Godot.
No añadir un framework antes de conocer la necesidad. Cambiar un contrato exige
actualizar sus tests en la misma entrega; conteos y arrays esperados deben coincidir
con archivos y recursos reales, conforme a `.copilot\skills\test-discipline\SKILL.md`.
Pruebas de configuración documental no equivalen a pruebas de gameplay.

## 7. dream-loop, costes y condiciones de parada

Este procedimiento es para los gates formales de arte. La corrección provisional
de G1 y la evaluación de escala autorizadas en §4.1 usan la captura real del usuario
como base de trabajo sin fingir una referencia dream-loop aprobada.

1. Lambert define hipótesis y encuadre por fase: A-G2/cuatro atletas, A-G3/diez.
2. Obtener una referencia del usuario con derechos y aprobación **o**, con Ferro,
   verificar generador autorizado, coste/límite y posterior aprobación humana.
   **Estado: ninguna referencia aprobada y ningún generador habilitado.**
3. Solo con referencia aprobada y paquete autorizado, integrar el recurso
   representativo en Blender/Godot. No confundir MCP conectado con arte terminado.
4. Capturar gameplay real comparable; crítico independiente aplica el prompt
   upstream y sus cinco tiers; medir rendimiento y probar movimiento/mando aparte.
5. Máximo **3 rondas por gate**; parar también tras **2 rondas sin mejora**,
   proveedor ausente, error repetido o presupuesto agotado. Escalar un diagnóstico
   acotado, no un ciclo interminable ni rebajar el umbral de aceptación.

Presupuesto de APIs pagadas: **0 por defecto**. Cualquier coste requiere autorización
explícita con proveedor, límite y número de intentos. No exponer secretos en logs,
repo, capturas o prompts; no enviar código privado a servicios externos. Utilizar
referencias/recursos autorizados y registrar licencias con el pipeline.

## 8. Riesgos y decisiones restantes

| Riesgo / decisión pendiente | Responsable | Mitigación y momento límite |
|---|---|---|
| Cámara espectacular pero incómoda | Hicks | Probar antes de producir el estadio; opciones de altura, shake y zoom limitados |
| Física/animación incapaces de contacto convincente | Hicks + Lambert | Un pase, tiro y parada excelentes en G1/G2 antes de ampliar acciones |
| Hipótesis Godot/Forward+ y exportación Windows | Bishop + Ferro | Elección documentada; acreditar instalación/diagnóstico en G0 y reabrir si G1/G2 muestran un límite estructural |
| Runner, contratos headless y serialización | Bishop | GDScript tipado elegido; concretar pruebas y persistencia antes de UI, no fingir clases implementadas |
| Referencia aprobada ausente | Lambert + Ferro | Imagen lícita del usuario o generador autorizado + aprobación; no aprobar G2 ni fingir que una API es la única ruta |
| Coste del arte o demasiadas variantes | Lambert + Ripley | Una cancha y rig reutilizable; tope de rondas y gasto aprobado |
| Importación de rigs, materiales y animaciones | Lambert + Ferro | Round-trip de un asset con escala/orientación correctas antes de fabricar variantes |
| Memoria/GPU o rendimiento insuficientes | Vasquez | Medir GPU realmente usada, frame time y memoria; no asumir VRAM |
| IA cara o ilegible al pasar a 5v5 | Hudson | Escenarios tácticos y profiling; limitar frecuencia de decisión sin alterar autoridad |
| XP duplicados o gasto incoherente | Bishop + Newt | Transacciones, claves únicas y matriz de fallos desde el contrato |
| Coste oculto de preparar online | Bishop | Frontera headless hoy; transporte, hosting y conciliación después del MVP |
| Falsa seguridad de saves offline | Bishop | No prometer anti-cheat ni importar XP local como confiable al futuro servidor |

**Cerrado para iniciar pruebas:** Godot 4.7.2, Forward+, GDScript tipado, Jolt,
tick fijo inicial a 60 Hz y Blender 4.5.13 LTS → `.glb` en `game\assets\`, con
fuentes `.blend` en `art\source\` fuera del runtime. Los contratos de simulación G1
están implementados en `docs\MICRO_SLICE.md`. **Pendiente de diseño/prueba:**
ajustes de contacto/animación con evaluadores, guardado y gates de producto.
Los 60 Hz están sujetos a profiling, no implican lockstep.
ENet es hipótesis futura; autenticación, protocolo y hosting esperan al post-MVP.

## 9. Cierre de una tarea y control de alcance

Cada encargo termina con archivos propios, evidencia reproducible, límites, revisor
y siguiente paso acotado. No autoaprobarse. Si falta evidencia, estado «pendiente» o
«bloqueado», no «hecho». Para trabajo compartido, acordar interfaz antes de editar.
Esta integración recoge las decisiones documentadas y evidencias de herramientas
disponibles; Ferro mantiene comandos, informes y artefactos del diagnóstico en TOOLING.
Ni este texto ni sus conteos acreditan revisión o aprobación de Vasquez.

No modificar historiales existentes, logs ni `.squad\decisions.md` sin puente de estado.
Si falta, comunicar al coordinador el resultado para su gestión autorizada, sin crear
notas alternativas, ramas o commits. Mantener el scaffold existente y archivos ajenos.
La autorización del 2026-09-10 permite solo el 5v5 experimental y menú técnico de
§4.1. No extenderla a aceptación G3, progresión, modos de producto o red antes de
sus gates ni usar la excepción para omitir evidencia humana, visual o de rendimiento.
