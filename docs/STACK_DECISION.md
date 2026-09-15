# Decisión de stack — Futsal 3D

**Fecha:** 2026-09-09 · **Propietario:** Bishop · **Integración documental:** Ripley.
**Estado:** elección de ingeniería, revisable tras las primeras pruebas de sensación
y arte. No es un benchmark ni una aprobación de calidad de producto.

## 1. Elección y evidencia disponible

| Componente | Decisión para el proyecto |
|---|---|
| Motor | **Godot 4.7.2 stable**, Windows x64; publicación del 18 de agosto de 2026 confirmada por coordinación en la descarga oficial [1] |
| Renderer | **Forward+**, con driver efectivo y GPU registrados en cada prueba |
| Lenguaje | **GDScript tipado**; no introducir .NET ni extensiones nativas sin necesidad medida |
| Física | **Jolt Physics**, tick fijo inicial de **60 Hz** |
| Autoría / intercambio | **Blender 4.5.13 LTS → glTF 2.0 `.glb` → Godot** |
| Autoridad | Local offline en el MVP; servidor autoritativo y ENet como opción de transporte futura |
| Plataforma | PC Windows y mando primero; no navegador, móvil ni consola en este alcance |

Blender 4.5.13 LTS está probado y dream-loop vendorizado con MIT intacta. La corrección
MCP está migrada y probada con concurrencia real; aceptación formal de Vasquez pendiente.
Versiones/conteos/comandos: `docs\TOOLING.md`.
**Verificado:** Godot `4.7.2.stable.official.ed1daf0bf` estándar, templates Windows
y bootstrap debug exportado, incluida comprobación independiente de coordinación.
Informe en `docs\DEVELOPMENT_PLAN.md`; no aceptación de juego, arte ni FPS.

No hay juego, `MatchSimulation`, referencia aprobada, crítica ni FPS de producto.
El diagnóstico no constituye una micro slice ni abre G1/G2. Los requisitos
**12 jugadores / 100 XP compartidos / +3 por victoria de carrera** de `docs\MVP.md`
no cambian.

Godot se elige por integración local, acceso al motor, licencia e iteración prevista.
Es una **recomendación**, no superioridad demostrada. Si atleta, balón y cancha
fallan G1/G2, reconsiderar antes de producir 5v5 o menús.

## 2. Comparativa técnica y licencias

### Godot

- Forward+ prioriza escritorio 3D/hardware moderno [4], sin afirmar imposibilidad
  técnica de toda ejecución móvil. Mobile atiende esas restricciones; aquí solo Windows.
- AnimationPlayer/AnimationTree y modificadores de esqueleto permiten mezcla e IK;
  apoyos, giros y contactos excelentes requieren clips y pruebas, no solo herramientas.
- Jolt se **integró en 4.4 como alternativa**. La documentación 4.7 lo describe como
  predeterminado para proyectos nuevos [3]; no significa «predeterminado desde 4.4».
  Se fija explícitamente. Balón, CCD, fricción y restitución necesitan calibración.
- MIT permite uso comercial sin regalías ni cuotas de asiento. Al redistribuir el
  motor hay que conservar **copyright y texto de licencia**, además de los avisos
  aplicables de sus componentes de terceros [2]. No es solo añadir un copyright.
  No impone la licencia del juego ni concede derechos sobre assets.

### Unreal Engine

La alternativa más fuerte en fidelidad/animación de serie: Lumen, Nanite y Control
Rig. La contrapartida prevista es más preparación, compilación y mantenimiento
C++/Blueprint, **sin tiempos medidos aquí**. No se fija una versión no instalada
como «última verificada»; tampoco se garantiza arte aprobado.

Epic recomienda **32 GB de RAM** [7]; sus estaciones de referencia no son un mínimo
ni una recomendación general de 64 GB. Hardware detectado no acredita rendimiento.

**Sí admite servidores dedicados headless.** El tutorial oficial usa una compilación
desde fuentes, proyecto C++ y un target `Server.Target.cs`, seguido de build/cook
y pruebas [6]. **No exige UGS ni Multiplay**: UGS significa UnrealGameSync, una
herramienta de sincronización de desarrollo, no un backend de red.

Motor propietario con acceso a fuentes bajo condiciones de Epic. **EULA no verificada**:
la consulta oficial redirigió a autenticación. Revisar términos antes de comprometerse;
no presentar regalías históricas como contrato actual.

### Unity

Unity 6 es viable: URP/HDRP, rigs y herramientas de servidor/red. HDRP ofrece alta
fidelidad; no se descarta por incapacidad gráfica ni se fija una supuesta última LTS.

Selección de pipeline, integración y mantenimiento añaden trabajo; condiciones
propietarias y posibles cuotas añaden coste frente a MIT. Verificar contrato vigente
si se reconsidera: no reutilizar precios antiguos ni afirmar acceso al código
«solo con Enterprise» sin comprobar su alcance.

La **Runtime Fee se canceló el 12 de septiembre de 2024** [8], no en octubre.
Ese antecedente no domina la selección: importan flujo, costes actuales y pruebas.

### Three.js / web

**Sí tiene animación esquelética:** `SkinnedMesh` deforma una malla mediante su
esqueleto [9], `AnimationMixer` reproduce sus animaciones [10] y los loaders pueden
importar modelos animados. No se descarta por carecer de animación.

Es una biblioteca de render, no un framework de juego completo. Integrar física,
control, herramientas, persistencia y servidor es posible, pero añade trabajo sin
una ventaja web solicitada. No se rechaza por imposibilidad técnica ni se infieren
FPS; la demo de dream-loop no obliga a elegir Three.js.

## 3. Matriz orientativa, no benchmark

Escala 1–5; pesos suman 100 %. **Todos los valores son estimaciones de ingeniería**
para este alcance, no mediciones ni notas artísticas. Imagen, animación y física
pesan conjuntamente 55 %; coste/iteración no permiten saltarse los gates de calidad.

| Criterio | Peso | Godot | Unreal | Unity |
|---|---:|---:|---:|---:|
| Techo visual utilizable en escritorio | 25 % | 4 | 5 | 5 |
| Herramientas de animación y locomoción | 20 % | 3 | 5 | 4 |
| Física de balón y personajes | 10 % | 4 | 4 | 4 |
| Iteración y mantenimiento para este equipo | 20 % | 5 | 2 | 4 |
| Integración con el flujo de arte elegido | 10 % | 5 | 3 | 4 |
| Licencia y coste previsto | 10 % | 5 | 3 | 3 |
| Autoridad headless y evolución de red | 5 % | 4 | 4 | 4 |
| **Suma ponderada / 5** | **100 %** | **4,20** | **3,85** | **4,15** |

Ventaja estimada frente a Unity pequeña y sensible a pesos; animación es el riesgo
principal de Godot. La matriz orienta; G1/G2 deciden si continuar.

## 4. Arquitectura propuesta, todavía no implementada

Separar cinco responsabilidades desde el primer paquete autorizado:

1. **Entrada:** humanos/IA generan comandos validados con jugador, acción, secuencia
   y tick; no goles, posiciones o XP ya concedidos.
2. **Autoridad:** reglas y física a 60 Hz; puede usar nodos/servicios de Godot headless,
   nunca depender de cámara, UI, audio o poses renderizadas.
3. **Snapshots/eventos:** estado y sucesos separados. `PlayerCommand`, `MatchSimulation`,
   `MatchSnapshot` y `MatchEvent` son contratos futuros, no clases implementadas.
4. **Presentación:** interpola/anima; no adjudica física ni resultado. Render y
   simulación tienen frecuencias distintas.
5. **Persistencia:** versiones, recuperación y transacciones idempotentes; Partido
   rápido no escribe carreras.

En el MVP, un adaptador local invocará la autoridad **sin sockets ni backend remoto**.
Conservar `100 + 3 × victorias_recompensadas = saldo + asignaciones`, con +3 una vez
por victoria de carrera completada y `(career_id, match_id)` único. UI, recarga,
abandono o partido rápido no fabrican recompensas. Bishop/Newt/Vasquez cierran
almacenamiento y recuperación.

### Evolución a cliente-servidor, después del MVP

La hipótesis es servidor autoritativo Godot headless, ENet, predicción local,
reconciliación con snapshots e interpolación de rivales. ENet ofrece modos
**fiable, no fiable y no fiable ordenado**, con canales independientes [5];
no convierte todo UDP en entrega garantizada y ordenada. Protocolo/frecuencias se
diseñan y prueban en esa fase.

Sin física idéntica ni lockstep entre máquinas. La corrección autoritativa admite
divergencia física, pero estabilidad y tacto **no están demostrados**: probar latencia,
pérdida, jitter y contactos. Reproducibilidad local no es determinismo de red.
Autenticación, hosting y matchmaking no están implementados/contratados; XP de saves
offline no será confiable por defecto.

## 5. Arte y validación del stack

Fuentes `.blend`/mapas maestros en **`art\source\`**, fuera de `game\`; exportar
`.glb`/mapas runtime a **`game\assets\`**, importados por Godot desde ahí. Sin copia
intermedia ni `.blend` en runtime. PBR, rig, kits, LOD y reimportación: ART_DIRECTION.

Perfilar GDScript antes de añadir C#/GDExtension. Pruebas de dominio sin presentación,
actualizadas con contratos según `.copilot\skills\test-discipline\SKILL.md`.

**Comandos reales de instalación, arranque, comprobación y exportación:
`docs\TOOLING.md`, propietario Ferro.** No duplicar rutas de binarios ni flags
provisionales. Un smoke del editor no es lint; `--check-only` comprueba el script
indicado, no todo el proyecto al combinarlo con apertura/cierre del editor.

G0 exige versión instalada, renderer/driver, Jolt/tick, exportación del diagnóstico
y contratos revisados. G1/G2: **1v1 + dos porteros = cuatro atletas**; G3: diez.
Referencias aprobadas propias por fase, sin heredar notas de la micro slice.

Dream-loop: referencia lícita del usuario aprobada o generador autorizado + aprobación
humana; hoy ninguna disponible. Cinco tiers upstream, **≥8 y FPS aceptable**;
movimiento aparte. Máximo **3 rondas**, parada tras 2 sin mejora, API **0**.
Original intacto en `.github\skills\dream-loop`; no crear assets en esta integración.

## 6. Reevaluación y responsables

- **G1 falla:** Hicks/Bishop aíslan control/física y prueban una corrección acotada.
- **G2 falla:** Lambert/Bishop contrastan límites con Unreal/Unity antes de 5v5;
  no rebajar calidad para conservar Godot.
- **FPS falla:** Vasquez perfila GPU/driver/build/escena y revalida; no cambiar de
  renderer o perfil silenciosamente.
- **Nueva plataforma/equipo/licencia:** revisar solo ante requisito autorizado.

Ripley coordina; Vasquez/especialistas no autores revisan. Umbrales y método:
`docs\DEVELOPMENT_PLAN.md` / `docs\ART_DIRECTION.md`. Ningún gate ni FPS queda
acreditado por esta decisión.

## 7. Fuentes primarias

Consulta/integración: 2026-09-09. Las fuentes de capacidades no fijan versiones
instaladas de motores alternativos ni sustituyen contratos comerciales vigentes.

1. [Godot: descarga Windows y publicación elegida](https://godotengine.org/download/windows/).
2. [Godot: licencia MIT y componentes de terceros](https://godotengine.org/license/).
3. [Godot 4.7: Jolt, integración y diferencias](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html).
4. [Godot 4.7: renderers y plataformas objetivo](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html).
5. [Godot 4.7: multijugador, modos de transferencia y canales](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html).
6. [Epic: preparar un servidor dedicado](https://dev.epicgames.com/documentation/en-us/unreal-engine/setting-up-dedicated-servers-in-unreal-engine).
7. [Epic: hardware recomendado y estaciones de referencia](https://dev.epicgames.com/documentation/en-us/unreal-engine/hardware-and-software-specifications-for-unreal-engine).
8. [Unity: cancelación de Runtime Fee, anuncio histórico de 2024](https://unity.com/blog/unity-is-canceling-the-runtime-fee).
9. [Three.js: SkinnedMesh](https://threejs.org/docs/pages/SkinnedMesh.html).
10. [Three.js: AnimationMixer](https://threejs.org/docs/pages/AnimationMixer.html).
