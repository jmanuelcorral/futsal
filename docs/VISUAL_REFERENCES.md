# Referencias visuales — Futsal

**Autor:** Lambert · **Solicitante:** @jmanuelcorral · **Fecha:** 2026-09-09

**Estado:** investigación de referencia. Sin aprobación visual, sin nota, sin dream-loop ejecutado.

---

## Método

Solo se describe texto leído directamente, alt-text verificado o imágenes inspeccionadas por coordinación. No se han visto vídeos; sin marcas de tiempo. Las dos imágenes CDN de Ref B fueron inspeccionadas directamente por coordinación (archivos temporales privados, no incluidos en Git). UEFA.com devuelve pantalla de compatibilidad en todas las rutas intentadas; FIFA.com es JS puro; LNFS.es falla en DNS: las tres fuentes institucionales se citan como puntos de entrada, **no como contenido inspeccionado**.

---

## Fuentes primarias

### Ref A — FIFA 20 VOLTA Football Deep Dive (EA, 2019)
**URL:** <https://www.ea.com/able/news/pitch-notes-fifa-20-volta-football> — **texto leído**

VOLTA tiene tres modos con reglas distintas. El texto oficial dice literalmente: *"Futsal is always played on a large pitch, WITHOUT Walls and with a Goalkeeper."* Las paredes opcionales corresponden a los modos *Street*, no a Futsal.

Tipos de partido según el texto:
- **Rush Keepers** (3v3/4v4): sin portero, porterías pequeñas.
- **Street with Keepers** (4v4/5v5): portero, porterías de futsal; paredes opcionales en este modo.
- **Futsal** (5v5): sin paredes, cancha grande, portero, árbitros, reglas más auténticas.

Filosofía: *"football stripped back to its fluid, joyful, and energetic core."* Motor Frostbite, no es FIFA Street ni el modo Indoor de años anteriores.

**No observado:** colores de recintos, iluminación, roughness — texto de producto, no imágenes.

---

### Ref B — FC 25 Rush Deep Dive (EA, 2024)
**URL:** <https://www.ea.com/games/ea-sports-fc/fc-25/news/pitch-notes-fc-25-rush-deep-dive> — **texto leído; imágenes inspeccionadas por coordinación**

Rush **no es fútbol sala**: aproximadamente 64 × 47 m. El texto dice 63,7 × 46,6 m; el esquema gráfico muestra la dimensión corta como 46,7 m. Porterías estándar de fútbol y superficie de hierba visible. En Clubs y Ultimate Team hay 4 jugadores de campo de usuario + 1 portero IA; el artículo distingue otros modos de control.

Cuatro cámaras para cancha pequeña — texto oficial + imagen inspeccionada por coordinación (archivo temporal privado, no en Git):

| Cámara | Posición y orientación observadas |
|---|---|
| *Rush Broadcast* (defecto) | Vista lateral de banda, próxima a la acción |
| *Rush Tactical* | Vista lateral de banda más abierta que Broadcast |
| *Rush Pro* | Detrás del juego, orientada hacia portería, semipicado |
| *Rush End to End* | Detrás del juego, orientada hacia portería, ángulo más elevado |

Los cuatro paneles muestran hierba y público, no parqué. El encuadre no permite asegurar si existe cubierta fuera de la imagen. Los bordes verdes y etiquetas grandes de nombre de cámara pertenecen al gráfico comparativo de EA; **no son propuestas de HUD**. Los indicadores de selección y equipo son los propios de FC 25, no propuestas para este proyecto. **No se puede inferir** FOV exacto, alturas, roughness ni animación de estos fotogramas estáticos.

El texto documenta que los problemas de legibilidad de equipo en cancha pequeña motivaron el sistema de ping/flechas por color de jugador.

Enlace a imagen de cámaras (referencia visual primaria):  
`https://drop-assets.ea.com/images/1gwnSSEsi41uhGA7kslAm1/ec320bd9dba6b7ad038434fb7088f159/Rush_Cameras2.jpg`

---

### Ref C — FC 26 PC Deep Dive (EA, 2025)
**URL:** <https://www.ea.com/games/ea-sports-fc/fc-26/news/pitch-notes-fc26-pc-deep-dive> — **texto leído**

Motion Blur: listado como ajuste independiente desactivable, bajo coste. Cloth Quality: físicas de camiseta, alto coste CPU. Estos son datos del texto de especificación, no observación visual del resultado en pantalla.

---

### Ref D — FIFA Futsal World Cup Uzbekistan 2024 (FIFA)
**URL:** <https://www.fifa.com/en/tournaments/mens/futsalworldcup/uzbekistan-2024> — **no inspeccionado (JS)**

URL oficial verificada; contenido no legible. Sin descripción visual del recinto. Punto de entrada para el usuario.

---

### Ref E — UEFA Futsal EURO y LNFS — puntos de entrada no inspeccionados
- UEFA Futsal EURO: <https://www.uefa.com/futsaleuro/> — URL verificada; UEFA.com bloquea acceso programático.
- LNFS YouTube: <https://www.youtube.com/@LNFSoficial> — canal oficial español; acceso manual del usuario para observar pabellones reales.

---

## Observado vs. inferido

| Afirmación | Base |
|---|---|
| Futsal VOLTA: sin paredes, cancha grande, con portero | Cita directa del texto oficial |
| Rush Broadcast: cámara horizontal próxima a la acción y predeterminada | Texto oficial |
| Rush: cancha ~63,7 × 46,6 m, porterías estándar, sin paredes | Texto + alt-text oficial |
| FC 25 introdujo ping/flechas por legibilidad en cancha pequeña | Texto oficial |
| FC 26: Motion Blur es ajuste desactivable de bajo coste | Texto oficial |
| Proporciones adultas y calidad de telas/PBR de FC 25/26 | Afirmación de texto de marketing — **no observada en pantalla** |
| Iluminación/superficie de pabellones LNFS o FIFA FWC 2024 | **No verificada** — fuentes no accesibles para inspección |
| La superficie visible de Rush es hierba, no parqué | Imágenes inspeccionadas por coordinación; no demuestran ausencia de cubierta fuera del encuadre |
| Bordes/etiquetas de color del composite de cámaras de Rush son HUD del juego | **Incorrecto** — pertenecen al gráfico comparativo de EA, no al HUD en partida |

---

## Tabla adoptar / adaptar / evitar

| Ref | Observado (texto o imagen inspeccionada) | Adoptar | Adaptar | Evitar |
|---|---|---|---|---|
| **A · VOLTA DD** | Texto: Futsal = sin paredes, cancha grande, portero. Street = paredes opcionales. | Filosofía fluida sin complejidad excesiva. | Entornos urbanos/streetwear de VOLTA no son referente visual. | Confundir paredes de Street con el modo Futsal. |
| **B · Rush DD** | Texto + imagen: 4 cámaras; Broadcast/Tactical laterales, Pro/E2E detrás hacia portería; hierba y gradas; ≈64×47 m. | Cámara lateral cercana como punto de partida. Indicadores de selección legibles. | Escala (40×20 m), porterías 3×2 m y superficie de pabellón. | Copiar el campo o interpretar los bordes del composite como HUD. |
| **C · PC DD** | Texto: Motion Blur desactivable, bajo coste. | Motion Blur apagado en partido. | Los presets de FC 26 no equivalen a Godot 4.7. | Strand-Based Hair como expectativa alcanzable. |
| **D · FIFA FWC** | Solo URL verificada; JS no legible. | Punto de entrada para el usuario. | Sin contenido visual verificado. | Asumir detalles del recinto. |

---

## Recomendación de dirección (propuesta Lambert — no aprobación, no nota)

**Cámara:** Broadcast y Tactical son perspectivas laterales de banda, confirmadas visualmente. Para nuestra cancha de 40×20 m se propone una cámara lateral próxima a la acción, ajustada jugando para equilibrar detalle y visión de apoyos. La escala por sí sola no determina altura o FOV. §4.A de ART_DIRECTION sigue siendo una **propuesta pendiente de aprobación por imagen**, no una medida certificada.

**Legibilidad:** el texto de Rush documenta el problema de identificación de equipo como real y motivó UI adicional. Coherente con la propuesta de símbolo+color de este proyecto.

**Motion Blur:** el texto de FC 26 lo lista como switch independiente de bajo coste; su desactivación en partido ya establecida en ART_DIRECTION es coherente.

**No apoyado aquí:** roughness, temperatura de color de pabellón, calidad de sombras en recinto cubierto real — ninguna galería oficial fue accesible.

**No copiar de FIFA/EA:** estadio masivo, césped, cámara broadcast de 11v11, porterías estándar, inertia de campo, activos/rostros/kits licenciados.

---

## Tres enlaces principales para el usuario

1. **FC 25 Rush Deep Dive** — texto + imagen de cámaras inspeccionada (Broadcast/Tactical laterales; Pro/E2E traseras):  
   <https://www.ea.com/games/ea-sports-fc/fc-25/news/pitch-notes-fc-25-rush-deep-dive>

2. **FIFA 20 VOLTA Deep Dive** — Futsal sin paredes, portero, cancha grande (texto oficial):  
   <https://www.ea.com/able/news/pitch-notes-fifa-20-volta-football>

3. **LNFS YouTube** — pabellones reales de fútbol sala de élite española, inspección directa del usuario:  
   <https://www.youtube.com/@LNFSoficial>
