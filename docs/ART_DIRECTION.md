# Dirección artística — Futsal

**Autor:** Lambert · **Solicitante:** @jmanuelcorral · **Fecha:** 2026-09-09

**Estado:** propuesta de diseño y plan de validación; no implementación ni calidad conseguida.

## 1. Objetivo, alcance y stack elegido

Construir un juego de fútbol sala **visualmente bello, deportivo y creíble**, con jugadas espectaculares por el movimiento, los contactos y la lectura del juego, no por efectos que escondan la acción. La referencia es una retransmisión deportiva cuidada: materiales convincentes, atletas coherentes y una única cancha realizada con atención artesanal.

- Windows PC y mando primero; 3D, singleplayer inicialmente y multijugador cliente-servidor después.
- Plantilla de **12 personas por equipo**, 2 porteros y 10 de campo, con **5 en pista, incluido el portero**, y 7 suplentes. Presets y cambios reutilizan esas identidades, no crean 15. El 5v5 tiene 10 atletas activos; la micro slice G1/G2, cuatro.
- Escudo, colores y equipaciones local/visitante configurables; equipos rápidos autogenerados; tres dificultades de IA.
- Prioridad: **balón visible y respuesta > pies/contactos creíbles > siluetas/equipos > iluminación/materiales > detalle de primer plano**.
- Una arena excelente antes que varias mediocres. Los bloqueos geométricos sirven para pruebas internas, pero no se presentan como arte final ni como «gráficos preciosos».
- No buscamos una estética de juguete, caricatura, low-poly plano, muñecos cabezones o primitivas procedurales brillantes. Tampoco prometemos un resultado AAA por instalar un motor, Blender o un MCP.

Stack elegido en `docs\STACK_DECISION.md`: **Godot 4.7.2, Forward+, GDScript tipado y Jolt a 60 Hz**. **Blender 4.5.13 LTS está instalado y verificado** según `docs\TOOLING.md`; no se deduce de la documentación consultada. **Godot estándar, templates Windows y bootstrap debug exportado están verificados**, incluida comprobación independiente de coordinación registrada en `docs\DEVELOPMENT_PLAN.md`. La simulación y el HUD de G1 ya están implementados; contrato y simplificaciones en `docs\MICRO_SLICE.md`. Ni ese código ni la captura del diagnóstico acreditan el pipeline artístico completo.

**Dependencia abierta:** no hay referencia visual aprobada ni generador habilitado. La entrada admite una imagen aportada por el usuario con derechos y aprobación **o** generación autorizada y posterior aprobación humana. La API no es la única ruta. El bucle de G2 sigue bloqueado; sí está autorizada la representación funcional provisional de G1 para probar controles, cámara y contactos. Esa representación no es arte final ni una referencia autoaprobada. No se ha generado `.dream-loop\concept.png` ni obtenido una puntuación artística.

## 2. Un pabellón memorable y realizable

### Composición y escala

Propuesta de cancha de **40 × 20 m**, porterías de **3 × 2 m** de abertura interior y líneas de **8 cm**. Son dimensiones de diseño que deben cotejarse con el reglamento de futsal vigente antes de cerrar geometría y colisiones. Reservar inicialmente unos 2 m de circulación perimetral y una cubierta suficientemente alta, alrededor de 8 m libres, sin presentarlos como homologación.

Elementos obligatorios: tablones con juntas discretas, marcajes de futsal reconocibles, áreas y puntos de penalti, círculo central, postes y larguero con espesor real, redes tensadas con caída y anclajes, bancos, protecciones, accesos, estructura de cubierta y luminarias plausibles. No mezclar líneas de numerosos deportes ni inventar marcas gigantes para llenar el suelo.

La riqueza se concentra en pista, atletas y porterías. Grada corta, público moderado y desaturado, señalética genérica y pocos objetos secundarios bien colocados. Reutilizar módulos y variantes propias sin repetición obvia en primer plano. Evitar cientos de accesorios únicos, pancartas luminosas animadas y público que robe atención.

### Paleta, materiales e iluminación

Paleta guía: madera miel clara, azul petróleo `#174D66`, grafito `#202A31`, marfil `#F3EEE3` y terracota `#B84E36` como acento. Son muestras de base, no valores finales garantizados tras iluminación y tonemapping. La cancha queda en luminancia media, los atletas se separan por masas claras/oscuras y el balón conserva paneles oscuros legibles.

| Superficie | Objetivo visible | Punto de partida PBR, sujeto a calibración |
| --- | --- | --- |
| Madera barnizada | Fibra a escala, juntas finas, reflejos anchos de luminarias y desgaste localizado; nunca un espejo mojado | Metallic 0; roughness 0,28–0,42; normal muy discreta; variación de tono contenida |
| Líneas y pintura | Bordes estables sin parpadeo ni z-fighting; pintura sobre madera, no luz emitida | Metallic 0; roughness 0,40–0,55; geometría o máscara con mipmaps verificados |
| Tejido deportivo | Trama fina, costuras y pliegues según tensión; no plástico ni arrugas aleatorias profundas | Metallic 0; roughness 0,65–0,90; relieve horneado, sin simular tela completa en cada atleta |
| Piel y cabello | Volúmenes anatómicos, piel sin aspecto encerado, cabello con masas limpias | Piel: roughness inicial 0,40–0,65; evitar depender de extensiones complejas de shader |
| Balón | Tamaño de futsal, paneles claros/oscuros, juntas pequeñas y sombra de contacto | Metallic 0; roughness 0,45–0,65; sin emisión ni brillo que borre la silueta |
| Porterías y redes | Pintura blanca satinada, red de nailon reconocible sin moiré | Pintura metallic 0; metal solo donde esté realmente desnudo; red mate, LOD revisado |

Usar una tarde de partido a las **19:30**, con luz interior neutra-cálida de unos **4300 K** y exterior crepuscular frío apenas sugerido en accesos. La hora es una condición artística, no un sistema dinámico de día/noche.

- Iluminación amplia desde techo, sombras de contacto claras y exposición fija durante la jugada. Fondo algo más oscuro; nada de jugadores escondidos en sombras teatrales.
- Resolver primero luz estática horneada y/o sondas, según motor, más sombras dinámicas seleccionadas para atletas y balón. No crear una luz dinámica con sombra por cada luminaria modelada.
- Reflejos de suelo plausibles mediante la técnica viable del motor; sondas como base y reflexión adicional solo si el perfil lo permite. No exigir ray tracing ni un reflejo perfecto de cada jugador.
- Emisión **0** en piel, ropa, madera y balón. Solo luminarias y pantallas pueden emitir; contrato de intercambio inicial con factor glTF por canal **≤ 1**, sin depender de `KHR_materials_emissive_strength`. La iluminación real se calibra aparte en el motor.
- Bloom desactivado en partido como referencia; ninguna fuente debe borrar balón, dorsales o líneas. No destellos grandes ni emisivos en los uniformes para diferenciarlos.
- **Sin motion blur, profundidad de campo, grano, aberración cromática ni volumétricos costosos durante el juego.** Antialiasing y sombras se evalúan en movimiento: una captura limpia no justifica estelas, ghosting o redes parpadeantes.

## 3. Atletas, identidad y animación

### Familia de atletas y rig único

Un cuerpo deportivo base con variaciones moderadas de complexión, rostro, piel y peinado; proporciones y lenguaje de ropa comunes. No es necesario fabricar 24 cuerpos independientes. Un rig reutilizable, también para porteros, con objetivo inicial de **55–75 huesos deformantes** y **hasta 4 influencias por vértice**. Los controles de autoría no forman parte del esqueleto de juego.

La calidad se invierte en pelvis, rodilla, tobillo, hombro y contacto con suelo/balón. Camiseta y pantalón deben doblarse con el cuerpo; normales y pliegues horneados más correctivos limitados, si el importador los conserva. La simulación de tela por atleta no es requisito.

Biblioteca mínima de movimiento:

- Espera activa, caminar/correr, aceleración y frenada; desplazamiento lateral y marcha atrás.
- Plantadas y giros de 45°, 90° y 180° a ambos lados; transiciones sin cambio instantáneo de orientación.
- Conducción con interior/exterior, parada y arrastre con la suela, recepción orientada y primer toque.
- Pase con ambos pies, disparo de empeine y puntera; anticipación y recuperación cortas y reconocibles.
- Portero: posición de espera, pasos laterales, blocaje, parada baja, estirada y recuperación.
- Reacciones de equilibrio/contacto sin atravesar extremidades, suelo o balón.

Medir desplazamientos y cadencias de los clips contra la velocidad real del personaje. La locomoción puede ser in-place con desplazamiento de simulación; conservar datos de contacto y velocidad para ajuste de zancada/IK. No delegar la posición física del jugador o del balón a una animación ornamental.

El instante de golpeo debe provenir del contrato de gameplay y alinearse visualmente con el pie. Para la futura red, definir identificadores de acción, pie de apoyo y fase de contacto reproducibles; la presentación no será autoridad de la física. Esto no implementa ni valida netcode. Las tres dificultades no justifican acelerar clips, deslizar pies o ocultar indicadores.

### Equipaciones editables sin multiplicar activos

Definir un material común de equipación con base neutra y cuatro máscaras de peso: **R = principal, G = secundaria, B = acento, A = ribetes**. Son datos lineales, no transparencia. Resolver solapes de manera determinista y normalizar pesos en las zonas textiles; piel, ojos y cabello quedan fuera de estas máscaras.

Separar color, roughness, normal y AO: cambiar azul por marfil no debe cambiar el tejido ni hornear luces nuevas. Escudo, dorsal y nombre usan regiones UV o un atlas propio, con márgenes contra sangrado de mipmaps y orientación verificada. Objetivo: hasta tres materiales por atleta, no uno por cada adorno.

glTF no convierte automáticamente este contrato de máscaras en un shader personalizado de cualquier motor. Exportar mapas, UV y material PBR base; el adaptador del motor aplicará parámetros/instancias compartidas sin editar el archivo importado a mano.

- Dos juegos de parámetros local/visitante por equipo, más combinaciones de portero. Los porteros deben distinguirse de ambos equipos de campo.
- Equipos rápidos: semilla reproducible, nombres y escudos geométricos originales, paletas y patrones prevalidados; no combinaciones RGB aleatorias sin control de choque.
- Probar el cruce de todas las equipaciones admitidas bajo la luz real de la cancha. Si chocan, seleccionar una alternativa válida y mostrar la elección en el editor.
- Combinar luminancia, bloques de color, dorsales y patrón: por ejemplo, torso petróleo liso frente a torso marfil con banda terracota. No depender de rojo frente a verde.
- Marcadores accesibles por **forma**: círculo para compañeros y rombo para rivales, con triángulo adicional para el atleta controlado. Hacer su densidad configurable y no tapar el balón; rol de portero identificado también mediante símbolo.
- Revisar escala de grises y simulaciones de protanopia, deuteranopia y tritanopia; estas simulaciones no sustituyen pruebas con personas.
- UI: objetivo de contraste de 4,5:1 para texto normal y 3:1 para indicadores esenciales. En el mundo 3D, comprobar separación renderizada y reconocimiento, no trasladar mecánicamente una ratio de UI a cada píxel del uniforme.

Solo activos de autoría propia por ahora, incluidos escudos, texturas y entorno. Bibliotecas externas, HDRI, servicios de pago o generación externa requieren selección y permiso explícitos posteriores, con licencia y atribución comprobadas. Instalar una herramienta no concede permiso sobre activos.

### Excepción autorizada: atleta representativo — 2026-09-15

El usuario autoriza expresamente, a las **10:22 del 2026-09-15**, descargar,
adaptar e incorporar **Human Base Meshes v1.4.1 de Blender Studio, CC0**.
Esta excepción concreta sustituye el bloqueo de esa base humana, no la regla
para otros activos. No autoriza otras bibliotecas, HDRI, imágenes generadas,
compras ni APIs de pago: **presupuesto de API 0**.

- Selección inspeccionada: colección **`Body Male - Realistic`**, autor **Dan
  Ulrich**, metadato de licencia **CC0**, cuerpo
  `GEO-body_male_realistic` y sus dos ojos. Es anatomía humana adulta continua
  con detalle multirresolución; **no incluye rig ni acciones de animación**.
  No se utilizan variantes *primitive/stylized* ni un personaje de otra obra.
- Archivo oficial: `human-base-meshes-bundle-v1.4.1.zip`, **50.643.039 bytes**,
  SHA-256 `811f43accbb31a88266d932f8f5563b2d13586fca0ba2693aad1f5fe582b3515`.
  El miembro `.blend` mide **49.420.489 bytes**, SHA-256
  `3c121505651140ceb4d69fd1d8923f7788ffadd81672f5be14845a5f2c75c137`.
  Se comprobaron rutas, colisiones de nombres Windows, enlaces y CRC antes de
  extraer exclusivamente los datos seleccionados; no se ejecutan textos embebidos.
- La [página oficial](https://www.blender.org/download/demo-files/#assets),
  el README interno y el metadato de la colección identifican CC0 y Blender
  4.2+. Existe un texto residual `License` referido a **Rain Rig / CC-BY 4.0**:
  se declara esta discrepancia para revisión de procedencia, no se incorpora
  Rain Rig ni se atribuyen sus derechos o animaciones al atleta.
- La referencia privada del usuario, de 1280 × 720, orienta **calidad anatómica,
  ropa y postura**, no rostros, marcas, equipaciones ni escenario. No se publica
  ni se convierte en `concept.png`. La captura real
  `docs/images/gameplay-0.4-corner.png` muestra el problema de las piezas separadas.
  Ninguna es una A-G2/A-G3 comparable aprobada.
- Alcance de esta entrega: **un atleta de campo adulto de unos 1,75 m**, camiseta
  de manga corta, pantalón de una pieza con entrepierna, calcetines, pelo corto
  y zapatillas de sala propios. Preservar cabeza, orejas, manos y dedos de la base;
  ocultar únicamente piel completamente cubierta, con solape suficiente.
  No dedicar esta iteración a estadio, luz de partido, UI o multiplicar personajes.
- Presupuesto específico de este candidato: **25–45 mil triángulos visibles,
  máximo aproximado 60 mil**, mapas 1K–2K, tres materiales si es viable y ≤4
  influencias normalizadas por vértice. Registrar valores reales y desviaciones;
  no sustituye los presupuestos históricos de LOD de §7 ni acredita FPS.
- Interfaz de primera pasada: fuente Z arriba / frente −Y, metros aplicados,
  pies en el origen; glTF Y arriba / frente +Z. `Root` no deformante;
  `Hips`, `Spine`, `Chest`, `Neck`, `Head`, cadenas bilaterales de clavícula,
  brazo, antebrazo, mano, muslo, pierna, pie y puntera, con dedos útiles.
  `AthleteSkin`, `AthleteKit`, `AthleteGear`; máscara textil RGBA de §3, albedo
  sRGB, normal tangente +Y y ORM/máscaras lineales. El JSON del recurso registra
  padres, posiciones, matrices de reposo y proporciones **medidas**, no fuerzas
  de adaptación a los targets provisionales.
- Coordinación conserva la autoridad y los targets actuales de apoyos/pases/gestos;
  adapta su presentación al `Skeleton3D` y el frente −Z de `MatchSnapshot` con
  un único giro de raíz. No cambiar colisiones ni mover física mediante animación.
- Propiedad de Lambert: fuente, generador, mapas maestros y manifiestos en
  `art/source/athletes/court_athlete/`. Caché y autoinspección local en
  `.dream-loop/downloads/` y `.dream-loop/athlete-upgrade/`. **No escribir en
  `game` hasta que coordinación confirme aislamiento del candidato 0.4**;
  después exportar directamente a
  `game/assets/athletes/court_athlete/court_athlete.glb`, sin `art/exports` ni
  copias derivadas paralelas. Ferro mantiene instalación/pipeline/distribución.

Se trata de una **mejora de atleta autorizada**, no del inicio del bucle formal
de puntuación. Máximo tres rondas de esta iteración; parar tras dos sin mejora
y reservar margen para corregir la importación tras capturas reales de coordinación.
El render de Blender sirve sólo para autoinspección. Vasquez/Ripley mantienen la
crítica independiente; no hay autoaprobación de arte, gate, movimiento ni rendimiento.
El puente de estado no está disponible: no se escriben historias, logs o decisiones
de Squad como sustituto. Los manifiestos son contratos técnicos del recurso.

#### Hito de fuente candidata, r2 — no aceptación artística

**Referencia anterior a los helpers/COLOR0.** Los números y capturas de este
hito describen la fuente `99be9c22…`; el contrato v2 posterior, descrito más abajo,
es el vigente para integración. No confundir sus hashes o formatos de máscara.

Fuente editable y generador en `art/source/athletes/court_athlete/`:
`court_athlete.blend`, `build_athlete.py`, auxiliares de malla/atlas,
`acquire_base.py`, `inspect_base.py`, `inspect_athlete.py`,
`export_athlete.py`, `maps/`, `manifest.json`, `rig_manifest.json` y
`provenance.json`. El `.blend` contiene la anatomía original multirresolución
oculta para autoría, además del atleta vestido de runtime; el exportador excluye
esa fuente de alta resolución.

| Medida real de la fuente r2 | Resultado |
| --- | --- |
| Altura vestida de reposo | **1,745953 m**, suela a menos de 0,001 mm del plano z=0 |
| Geometría de runtime | **47.186 triángulos / 24.386 vértices** antes de splits glTF |
| Desviación del objetivo preferido | +2.186 triángulos sobre 45 mil (**4,86 %**); por debajo de 60 mil. Cara y manos sin decimación |
| Esqueleto | **52 huesos, 51 deformantes**, ninguno deformante sin vértices; `Root` no deformante |
| Pesos | **Máximo 4**, cero vértices sin peso; error máximo de normalización **4,47 × 10⁻⁸** |
| Materiales / mallas de runtime | **3 / 3**: piel, textiles y accesorios |
| Mapas | Piel y kit **2048²**, accesorios **1024²**; albedo/normal/ORM por material y máscara RGBA de kit; tres maestros AO **1024²** adicionales |
| Tamaño PNG en disco | **5.775.395 bytes** en los diez mapas previstos para runtime; **7.279.806 bytes** incluyendo maestros AO. No es residencia GPU |
| Fuente `.blend` comprimida | **34.077.538 bytes**, SHA-256 `99be9c22bd32396241be426e870703a49d27a981e5a039d0daae227fe59f684f` |

Rig medido para adaptar presentación, **no para modificar autoridad**:
muslo/pierna **0,398271 / 0,416950 m**; brazo/antebrazo
**0,262953 / 0,227841 m**. En coordenadas glTF, hombro izquierdo
`(0,173823; 1,359882; −0,009043)`, articulación de cadera izquierda
`(0,096457; 0,915779; −0,010048)` y tobillo izquierdo
`(0,175832; 0,107955; −0,057271)`. Rest pose A con pies abiertos:
leer ambos lados y matrices completas de `rig_manifest.json`, no reconstruirlos
a partir del resumen. El antebrazo medido termina en **muñeca**; según el contrato
de integración aclarado posteriormente, el target provisional `hand` termina en
**centro de palma**. No comparar ambos como si fueran el mismo segmento ni estirar
la anatomía para compensar esa diferencia de semántica.

**Comprobado:** 15/15 controles estructurales de la fuente, matrices aplicadas,
normales de piel orientadas como la anatomía original, pesos, ausencia de cámaras,
luces y acciones en el recurso. La máscara PNG suma exactamente **255 por texel**
entre sus cuatro canales de 8 bits. El probe de poses verifica alineación real de
cabezas/colas de huesos en espacio de armadura; se corrigió la mezcla errónea con
`Bone.vector`, relativo al padre. La pose de flexión alcanza ángulos interiores de
rodilla de aproximadamente 98°/80° y codo de 88°; esto no valida el retarget de Godot.

Autoinspección real de **Cycles CPU**, 1024 × 1024, en
`.dream-loop/athlete-upgrade/r2/source-{front,back,flex,detail}.png`;
metadatos/hashes en `source-inspection.json` de esa carpeta. **No son capturas del
juego ni prueba de FPS.** No se publican las referencias privadas del usuario.

**Defectos visibles pendientes, no ocultos por los controles técnicos:** piel
intersectando camiseta en cuello/espalda alta y cintura del pantalón atravesando
el faldón, que parece roto especialmente por detrás. La corrección debe separar
las capas y conservar solapes, no cambiar luz o recortar la captura. Acabado de
pelo y tejido todavía no final; revisar UV de costuras y su AO: el raster de kit
detecta 10.878 texels con cobertura múltiple, frente a 25 en accesorios y 2 en piel.
No hay LODs, clips de gameplay, rig facial o contenido específico de portero.

Se han consumido **dos pasadas locales de fuente/autoinspección** y se reserva
la tercera para corregir estos puntos junto con defectos de importación que
devuelva coordinación. **No se ha escrito `game/assets` ni exportado el GLB**:
falta confirmación explícita de aislamiento de 0.4. El exportador comprueba ese
permiso antes de crear el destino; la prueba negativa pasó sin crear carpeta.
Las 15 opciones previstas existen en la API instalada de exportación glTF,
pero eso **no sustituye ejecutar/verificar la exportación**.

Comandos de construcción y autoinspección ejecutados desde la raíz (Blender en
`%LOCALAPPDATA%/Programs/Blender/blender-4.5.13-windows-x64/blender.exe`):

```powershell
python art\source\athletes\court_athlete\acquire_base.py --download
python art\source\athletes\court_athlete\acquire_base.py --extract-reviewed human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend
# Con la ruta de Blender anterior en $blender:
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\inspect_base.py
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\build_athlete.py
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\inspect_athlete.py -- --round r2 --views front back flex detail --samples 24
```

El primer intento de construcción se detuvo por superar el techo geométrico
(93.590 triángulos); se redujeron subdivisiones de ropa/accesorios, sin decimar
cara/manos. También se corrigieron la transformación de ojos cargados como datos,
normales invertidas de pantorrillas abiertas y desplazamiento inestable del pelo.
Los errores de autoría/probe no son regresiones del juego. Exportación, crítica
independiente de Vasquez/Ripley y validación de contactos/rendimiento siguen pendientes.

#### Contrato de palma y zapatilla para integración — 2026-09-15

**Primera versión del contrato de contactos.** El cambio v2 posterior añade los
huesos auxiliares solicitados y sustituye la máscara runtime por COLOR0; conserva
los centros, ejes, dimensiones y ecuación de muñeca de esta sección.

`hand` significa **centro de palma**, no cabeza del hueso `Hand_L/R` ni centro
del balón. Se añaden **locators de datos** `Palm_L` y `Palm_R`, sin huesos
auxiliares, bajo `rig_manifest.json → contact_contract.palms`.
`contact_locators.py` los mide sobre triángulos reales de la piel; conserva
índices, coordenadas baricéntricas, normal, matrices y huella del `.blend`.
El generador conserva este contrato al reconstruir el recurso.

Offsets en metros **en la base local del hueso Hand correspondiente**, no en
ejes del actor:

| Locator | X local | Y local | Z local | Distancia muñeca → palma |
| --- | ---: | ---: | ---: | ---: |
| `Palm_L` | −0,02182638 | 0,07188790 | 0,00401302 | 0,07523539 m |
| `Palm_R` | 0,02209726 | 0,07188193 | 0,00400400 | 0,07530832 m |

La diferencia pequeña entre lados procede de la superficie de la base, no de
una escala distinta. El locator se sitúa en la superficie palmar central
inspeccionada; el primer sondeo proximal incidía en la almohadilla tenar y fue
descartado, no publicado como centro de palma.

Para conservar el target existente:

```text
wrist_origin = desired_palm_center - posed_hand_basis * position_bone_local_m
```

No volver a añadir aquí un radio/offset de balón que ya aplique el resolver de
la acción. Todos los locators incluyen `axes_bone_local`, `axes_blender`,
`axes_gltf` y matrices completas: **+Z del frame = forward**, **+Y = up**,
**+X = up × forward**, base ortonormal dextrógira.

- **Manos:** forward hacia los nudillos proyectado en el plano tangente central;
  up es la normal geométrica suavizada **hacia fuera de la palma**, no vertical
  del mundo ni dorso. No asumir que forward/up coinciden con los ejes del hueso.
- **Pies:** forward hacia la puntera, paralelo al plano de suela; up se aleja
  del suelo. En reposo equivale a +Z de Blender / +Y glTF. Los pies están abiertos
  22°: medir alcance sobre ese forward, no sobre Z crudo del actor.
- Si el importador cambia las bases de huesos, reconstruir el locator local con
  `imported_bone_global_rest.inverse() * transform_gltf`, dentro de la raíz del
  modelo antes del giro global para `MatchSnapshot`. No reinterpretar el offset
  local como coordenadas glTF ni girarlo dos veces.

Dimensiones extraídas de la geometría final de **cada** zapatilla, sin deformar
el cuerpo o bajar artificialmente el tobillo:

| Medida | Fuente real | Target provisional |
| --- | ---: | ---: |
| Altura de articulación de tobillo | **0,107955 m** | 0,080 m |
| Alcance frontal exterior desde tobillo | **0,199502 m** | 0,195 m |
| Alcance posterior exterior desde tobillo | **0,068942 m** | ~0,075 m |
| Alcance frontal/posterior de suela | **0,197658 / 0,067342 m** | — |
| Longitud / anchura máxima de suela | **0,265000 / 0,119600 m** | — |
| Suela: límites verticales | **−0,000001 a 0,029465 m** | suelo 0 |
| Suela inferior en puntera / talón | **0,004465 / 0 m** | — |

La diferencia relevante es **+27,955 mm de altura del tobillo anatómico**;
puntera y talón exteriores difieren aproximadamente +4,502/−6,058 mm.
Adaptar anclajes/targets de presentación, no colisiones ni proporciones del humano.
Los límites verticales de la suela incluyen la elevación de puntera; no son una
medición uniforme de espesor ni del tamaño de colisión.

**Material confirmado:** PNG `maps/kit_mask.png`, **RGBA8 Non-Color en UV0**,
no `COLOR0`, sin transparencia. R camiseta principal, G pantalón **y los estrechos
paneles laterales secundarios existentes de camiseta**, B calcetines, A ribetes.
Se conservan albedo sRGB neutro, normal tangente +Y y ORM lineal exportables;
roughness permanece en G de ORM. En runtime se prevé `textures/kit_mask.png`
junto al GLB, pero aún no se ha escrito ese destino.

Validación local **29/29** de reconstrucción de locators, bases, conversión de
ejes y conservación del target palmar con rotaciones distintas. En el diagnóstico
de muñeca a ±35° sobre X/Z local, la diferencia máxima entre superficie skineada y
locator fue **1,04 × 10⁻⁷ m**, dentro del ruido numérico; no mide blocajes/saques
reales del juego ni cubre poses articuladas de los dedos. Fuente `.blend`, rig,
geometría y mapas permanecen byte-idénticos a r2. Esta ampliación de metadatos no
consume la pasada artística reservada ni habilita escribir `game`.

El hook del generador reproduce exactamente estos datos sobre la fuente actual.
Dos mutaciones negativas —offset de palma puesto a cero y up del pie reemplazado
por un eje local supuesto— se rechazaron. Comando ejecutado para medir y actualizar
sólo los manifiestos, sin guardar de nuevo el `.blend`:

```powershell
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\contact_locators.py -- --update-manifests
```

#### Contrato vigente v2: Palm auxiliares y COLOR0 — 2026-09-15

Petición explícita de coordinación de las **12:20**: alinear el recurso con
cadenas directas `Thigh → Shin → Foot → Toe` y
`UpperArm → Forearm → Hand → Palm`, sufijos `_L/_R`, y un shader que consume
COLOR0 como datos RGBA. Este cambio **sustituye la elección anterior de locators
sólo JSON y máscara PNG runtime**, sin alterar anatomía, gameplay o física.
No se ha leído ni editado `.dream-loop/athlete-upgrade/integration/`.

- **54 huesos, 51 deformantes.** `Root`, `Palm_L` y `Palm_R` no deforman.
  Los Palm son hijos directos de Hand, con origen exactamente en los centros
  palmares medidos. Su base auxiliar usa **+Y hacia fuera de la palma** y **+Z
  hacia los dedos**; la cola de autoría mide 20 mm, sin modificar la malla.
  Se conservan también los offsets relativos a Hand en `contact_contract`,
  ahora schema **2**, para comprobación y adaptación de bases del importador.
- **COLOR0 real en `AthleteKitMesh`:** atributo Blender `FLOAT_COLOR`, dominio
  `CORNER`, 48.192 esquinas / 771.072 bytes de datos float en fuente.
  Las discontinuidades se separan por vértice al exportar a glTF **`COLOR_0`**;
  el shader Godot lo recibe como **`COLOR`**. No es una promesa de importación
  comprobada: todavía falta la exportación del mesh real.
- Los valores se trasladaron del PNG propio existente por muestreo bilineal en
  las esquinas UV y normalización. Error medido de transferencia y suma: **0**
  en la precisión float de la fuente. Se conservan R principal, G pantalón
  **y paneles laterales secundarios de camiseta**, B calcetines y A ribetes.
  Piel y accesorios no reciben ese atributo de máscara.
- `maps/kit_mask.png` permanece como **maestro de autoría**, no como entrada
  runtime activa. Albedo neutro, normal +Y y ORM exportables permanecen intactos.
  El exportador prevé los **nueve PNG PBR**, **5.579.939 bytes** en disco; ya no
  copia la máscara PNG a `game`. No es todavía un tamaño de GLB medido.
- COLOR_0 es **dato**, no color base ni transparencia. Usar el shader de kit de
  coordinación; un visor glTF genérico podría mostrar los canales de máscara
  al multiplicarlos como color de vértice. No convertir alpha en opacidad ni
  aplicar una transformación sRGB a estos pesos.

Guardas explícitas en `export_athlete.py`:

```text
export_def_bones = False
export_vertex_color = "NAME"
export_vertex_color_name = "COLOR0"
export_all_vertex_colors = False
export_active_vertex_color_when_no_material = False
```

Se consultaron estas opciones en Blender 4.5.13 instalado. La comprobación del
GLB exigirá Palm dentro de los joints del skin, las cadenas directas, COLOR_0
RGBA normalizado con sus cuatro zonas y material de kit opaco. Rechaza un COLOR_0
blanco ficticio y la pérdida de alpha; no basta comprobar que existe el atributo.
**Estas guardas no acreditan que se haya exportado/importado el atleta.**

Fuente actual: `court_athlete.blend`, **34.065.947 bytes**, SHA-256
`55522a44d8e750283a632e7f3be0b85cdc054b614af7af0098adb2ae13c26ead`.
Los fingerprints de posiciones/topología, suavizado, UV y pesos de las tres
mallas son idénticos antes/después; delta máximo de las matrices rest de los
52 huesos anteriores: **0**. Se mantienen 47.186 triángulos y 24.386 vértices de
fuente, tres materiales y los trece mapas maestros byte-idénticos. El `.blend`
anterior está archivado en
`.dream-loop/athlete-upgrade/source-archive/court_athlete-99be9c22bd32.blend`
para vincular correctamente las capturas r2; no es una exportación runtime paralela.

Comprobado localmente: **27/27** del contrato de fuente helpers/COLOR0,
**29/29** de contactos y **15/15** estructurales; adaptación idempotente y hook
del generador verificados sobre la fuente guardada, sin repetir modelado/horneados.
Además, **13/13** pruebas en memoria de las guardas de exportación
(cinco entradas válidas y ocho rechazos esperados; float, enteros normalizados,
offsets y stride), sin crear un GLB. Dos mutaciones negativas de la fuente
(Palm deformante y COLOR0 blanco) se detectan; se verificaron las trece huellas
de mapas. Repetir el CLI de adaptación sólo valida, sin reescribir fuente o
manifiestos ni reasignar las capturas r2. El exportador sin autorización se
rechazó antes de crear destino.
El **59/59 nativo** comunicado por coordinación corresponde a su driver
sintético, no a este mesh; no se presenta aquí como ejecución propia ni como
aceptación del atleta.

Comando ejecutado para el cambio técnico explícito:

```powershell
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\rig_material_contract.py -- --update-source
```

Validación reproducible ejecutada, sólo lectura y sin render/exportación:

```powershell
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\validate_integration_contract.py
```

Los defectos artísticos de cuello/faldón siguen pendientes. **No se consumió
la tercera pasada artística, no se tocó `game`, ni se concedió aprobación visual,
de movimiento o FPS.** La exportación directa continúa esperando el aviso de
aislamiento del candidato 0.4.

#### Exportación directa autorizada — 2026-09-15, después del aislamiento

**Ferro confirmó a las 12:50 el aislamiento y liberó el destino del atleta.**
La fuente 0.4 queda en `build\release\frozen-04-12fb5d6\source`, según su
confirmación; Lambert no ha modificado esa fuente, snapshots, `build\windows`,
tooling, presets, código de partido o la carpeta de integración. No hay commit,
push ni publicación asociados a esta entrega.

Recurso real en `game\assets\athletes\court_athlete\court_athlete.glb`:
**8.304.648 bytes**, SHA-256
`4cbe87c13cd679427d2c4c270658a182ecda991baaa2b4e7d6a4252371535157`.
Incluye **47.186 triángulos, 33.898 vértices glTF** tras separaciones de UV,
normales y datos de color, **tres mallas/materiales, un skin y 54 joints**.
Palm_L/R están realmente dentro del skin y conservan las cadenas directas.
No hay cámaras, luces ni clips de animación exportados.

**COLOR_0 real:** VEC4 de `UNSIGNED_SHORT` normalizado, 14.076 vértices del kit.
Error máximo de suma de canales: `1,52590219e-5`; diferencia máxima contra el
muestreo del PNG maestro: `7,95641016e-6`. Se conservan los cuatro canales como
pesos, no opacidad. El shader de coordinación sigue siendo necesario.

El primer intento real descubrió n-gons incompatibles con el cálculo de
tangentes de Blender. Se resolvió **sólo durante la exportación**, mediante el
modificador nativo Triangulate: 22 caras de ropa y 122 de accesorios, sin mover
vértices ni cambiar pesos, UV, COLOR0 o presupuesto de triángulos. Una inspección
numérica posterior detectó una tangente nula en una cara casi horizontal del
borde superior del pantalón: el suavizado compartía la normal de la pared
lateral. La preparación separa **la normal de esa única cara**, no inventa
tangentes ni modifica geometría. Se comprueban componentes finitos, longitudes,
ortogonalidad y handedness del marco tangente en el GLB final.

El exportador valida un archivo temporal dentro del **mismo destino autorizado**
antes de reemplazar `court_athlete.glb`; no queda otro GLB derivado ni se usa
`art\exports`. La fuente `.blend` permanece byte-idéntica (`55522a44…`), con sus
24.386 vértices de autoría. Las diferencias de triangulación y normal de cintura
se registran en `export_manifest.json → export_only_geometry_preparation`.
Una segunda ejecución completa reprodujo **el mismo GLB byte a byte** y su hash.

Comprobación sobre el binario final: influencias no negativas y normalizadas
(error máximo `1,78813934e-7`), índices de joints dentro del skin y marcos
normales/tangentes válidos para los 33.898 vértices. Los **nueve PNG PBR embebidos
son idénticos píxel a píxel** a sus maestros. Las advertencias de Blender sobre
múltiples nodos de imagen para un sampler no cambiaron los mapas: los nodos
usan Linear/Repeat y el GLB conserva ese comportamiento, con mipmapping.
También se comprobaron las nueve copias PNG y las copias de `rig_manifest.json`
y `provenance.json` dentro del destino. La máscara PNG no se copia a runtime.

Regresión local actual: **27/27** contrato de fuente, **15/15** estructura,
**29/29** contactos, trece hashes de mapas, dos mutaciones negativas de fuente
y **17/17** guardas de exportación, incluyendo tangente nula, paralela y normal
no unitaria. Los trece casos anteriores siguen incluidos; no se ha reducido
ningún criterio para aceptar la exportación.

Comando de exportación ejecutado con la confirmación de Ferro:

```powershell
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\export_athlete.py -- --permit-game-export --approval "Ferro 2026-09-15 12:50+02:00: 0.4 aislado en build\release\frozen-04-12fb5d6\source; destino del atleta liberado."
```

**Pendiente de coordinación:** importar/animar el GLB real con el driver,
devolver capturas de partido y detalle (incluidos cuello, cintura, planta y
palma), y revisión independiente. La última pasada artística permanece reservada
para esos defectos; la corrección técnica de exportación no constituye otra
ronda visual evaluada. No se ha ejecutado Godot para esta entrega ni se concede
aprobación artística, de gameplay o FPS.

#### R3 final: ropa tras el feedback del EXE — 2026-09-15

**Última pasada artística autorizada: 3/3, ninguna restante.** Coordinación
aportó nueve PNG reales del EXE en
`.dream-loop\athlete-upgrade\builds\r2-capture-c496a18b506c4b1ca6ecbf733906aa3a\captures`.
Su manifiesto declara 1920×1080, RTX 2000 Ada, `editor_binary=false`,
sin medición FPS ni gate aprobado. Las comprobaciones nativas comunicadas
(216 skinning, 190 gestos, 230 visuales y 204 integración) corresponden a **R2**,
no se presentan como ejecuciones propias ni aceptación de R3. El feedback visual
no es un dictamen independiente.

**Cambios propios y acotados:** cuello de camiseta elevado 12 mm sin mover cuello
anatómico ni huesos; ajuste de holgura contra la base real; solape de camiseta y
pantalón separado al menos 9 mm en la zona medida; anclaje compartido a Hips con
transición de pesos en la cintura. Camiseta, shorts y cada calcetín incorporan
dobladillos conectados, de 1,4 mm y retorno interior de 12 mm, con pesos heredados
de su propio borde. Se eliminan los cordones independientes de todos los bordes;
el canal A de ribete queda en el fino remate del collar. El kit pasa de quince
componentes a **cuatro**: camiseta, shorts de una pieza y dos calcetines.

La medición sobre R2 detectó penetración mayor de 1 mm en **75 vértices de
camiseta, 26 de shorts y 42 de calcetín**, además de los ribetes. La candidata R3
ajustada tiene **cero vértices exteriores** por debajo de ese criterio en reposo.
La holgura diseñada es 7 mm, con 3,5 mm en el pliegue axilar estrecho, hasta 29 mm
en la cintura suelta, y 5,5 mm en calcetines; no se fuerzan dos capas de aire de
7 mm donde la anatomía de reposo no las permite. Medidas, tolerancias y límites
de las consultas se conservan en `manifest.json → garments.r3_tailoring`.
Esto no sustituye la inspección del movimiento retargeteado real.

**Rig, piel y calzado preservados:** mismos nombres y matrices rest de los
54 huesos, Palm incluidos; misma geometría/UV/pesos de piel y accesorios; ocho
maestros de piel/calzado byte-idénticos. No se modifican la anatomía para targets
antiguos, los pies, toe-out, cámara, retarget, iluminación ni shaders de
coordinación. La ropa conserva pesos anatómicos interpolados; los dobladillos no
se vuelven a vincular por cercanía a otra zona del cuerpo. Se corrige también
la utilidad de transferencia para borrar influencias residuales y compartir
cálculo baricéntrico de doble precisión con los contactos.

Sólo se regeneraron los **cinco mapas de kit**. Su micro-normal baja de 0,047
a 0,015, con variaciones menores de albedo/roughness; se mantienen los pliegues
geométricos y los tres materiales. No se retoca la piel para compensar el
doble tintado, el factor de roughness o el patrón punteado del EXE: la captura
CPU con el PBR original no muestra ese patrón. La cuantización de COLOR0 a
RGBA8 en Godot pertenece a la normalización que coordinación ya aplica en el
shader; **no se reexporta para ocultarla**.

**Fuente final:** `art\source\athletes\court_athlete\court_athlete.blend`,
33.959.644 bytes, SHA-256
`88276733d1f8271a4a5481089dbf442fc6ee61252c28cedd75e69c9e12a309dd`.
**GLB final directo:** `game\assets\athletes\court_athlete\court_athlete.glb`,
7.739.520 bytes, SHA-256
`79ad10342db6f6bbb0f97f11b3680647e45ff0feb1611937df87fff78d0d8b3b`.
Presupuesto real: **43.345 triángulos, 22.441 vértices de fuente / 31.450 glTF,
54 joints / 51 deformantes, tres materiales, máximo cuatro influencias**.
El GLB contiene nueve PNG PBR, idénticos píxel a píxel a los maestros; las nueve
copias runtime suman 5.223.860 bytes y los trece maestros 6.964.674 bytes.
COLOR_0 sigue siendo VEC4 UINT16 normalizado, con las cuatro zonas presentes.

**Fallo técnico detectado y corregido:** el guardado incremental trató las
rutas relativas Blender `//maps/...` como rutas UNC de Windows y produjo una
primera inspección magenta. Se repararon sólo enlaces, sin cambiar geometría,
mapas ni diseño; las imágenes inválidas permanecen bajo
`.dream-loop\athlete-upgrade\r3\invalid-missing-map-links`. No son evidencia de
acabado ni una cuarta ronda artística. Ahora se validan explícitamente las
rutas y la lectura de mapas antes de guardar/exportar. Las capturas corregidas
front/back/flex/detail y su manifiesto están en `.dream-loop\athlete-upgrade\r3`.

Comandos ejecutados (Blender existente, CPU):

```powershell
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\rebuild_wardrobe.py -- --final-r3
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\rebuild_wardrobe.py -- --repair-r3-map-links
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\inspect_athlete.py -- --round r3 --views front back flex detail --samples 24
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\validate_integration_contract.py
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\export_athlete.py -- --permit-game-export --approval "Coordinacion 2026-09-15 14:38+02:00: ultima pasada R3 de ropa y reexport directo autorizados; 0.4 aislado en build\release\frozen-04-12fb5d6\source; sin cambios de retarget, rig rest, fisica o release."
```

El generador completo `build_athlete.py` comparte la misma construcción de ropa;
el comando incremental parte de R2 y rechaza otra pasada artística sobre R3.
No hay nueva copia `.blend`, `art\exports`, descarga, API pagada ni cambios en
release, `game\match`, tests o tooling.

Controles finales: **27/27** de contrato, **18/18** estructura/enlaces,
**29/29** contactos, **17/17** guardas, tres regresiones de pipeline y dos
mutaciones negativas; pesos y marcos tangentes comprobados también en los
31.450 vértices del GLB. En las cuatro vistas CPU examinadas ya no se observan
las roturas blancas de ropa de R2. **Límites honestos:** boca de zapatilla aún
irregular y 10.772 texels de cobertura múltiple en el atlas de kit; las costuras,
cobertura extrema y retarget real quedan pendientes de la revisión del EXE,
sin evaluación independiente, score, AAA ni FPS. No se inicia otra ronda
artística dentro de este encargo.

**Feedback adicional de retarget, recibido a las 15:36:** las capturas en
`.dream-loop\athlete-upgrade\builds\retarget-capture-6217f7ef41214f24a7667f41ed988c7a\captures`
siguen usando el **GLB R2 `4cbe87c1…`**, no el R3 `79ad1034…` ya exportado.
Se inspeccionaron frente, espalda y sprint: siguen presentes los cierres y
ribetes defectuosos de R2, aun con mejor apoyo y brazos. No se atribuyen esos
resultados al recurso R3 ni se descarta la necesidad de verificarlo en el EXE.
Los 235/235 de skinning/retarget y las métricas de apoyo comunicados por
coordinación pertenecen a esa combinación de runtime y R2.

Se mantienen como límites el **pelo de silueta rígida tipo casco** y la lectura
del tejido, todavía pendientes de juicio integrado. La trama puntuada también
aparece fuera del atleta; coordinación investiga auto-sombras/SSAO/aliasing.
Su origen no queda demostrado aquí y no se compensa alterando mapas de piel.
Se conservan los ocho maestros de piel/calzado y todo el rig para que la
calibración real de coordinación se mantenga al consumir R3.

#### R3 + normalización técnica de formato — 2026-09-15, 16:11

Encargo explícito de coordinación, **no cuarta ronda ni cambio visual**:
convertir únicamente `skin_normal.png` de RGB8 a **RGBA8 opaco**. La ejecución
verbose del candidato `79ad…` avisaba:
`Image format RGB8 not supported by hardware, converting to RGBA8`,
en `texture_storage.cpp:2855`. Evidencia aportada y leída en
`.dream-loop\athlete-upgrade\builds\r3-candidate-dec184a44ee54e9681b0f653e2db0148\gameplay-artifact-rendered\native.stderr.log`.
Los resultados nativos del candidato anterior no se reasignan a este hash.

Se conservaron **todos los bytes RGB** y la resolución 2048×2048; se añadió
alfa **255 a los 4.194.304 píxeles**, sin reutilizar un canal normal como alfa.
Hash de los bytes RGB, antes y después:
`896a3c750f3a216d621166a4b075eeff98e9502045de4dc8fec2129162897fd6`.
El maestro, su copia runtime y el PNG extraído del GLB nuevo son byte-idénticos.
Los otros doce maestros PNG y las otras ocho imágenes embebidas no cambiaron.

| Recurso técnico actual | Bytes | SHA-256 |
| --- | ---: | --- |
| `maps\skin_normal.png` y `textures\skin_normal.png` | 1.978.822 | `a0ed497d4f1b61f72bb670f70c9f6be1d2fe628d30cf6728bfdc07d77a48e67c` |
| `court_athlete.blend` | 33.950.289 | `34b519c921b5101974e40cdd70ff6d576e6544ff032f28feb8f6d054ccc9b53f` |
| `game\assets\athletes\court_athlete\court_athlete.glb` | 8.038.876 | `72bb973ced0b5cb44d6871c23c9e1a8c3fb35db85adc7bc66673f74a61becc66` |

Prueba antes/después persistida en `normal_encoding_manifest.json`: tres mallas,
COLOR0, UV, pesos, transforms, los 54 huesos/rest/Palm y parámetros/conexiones
de materiales idénticos incluso después de guardar y reabrir Blender.
El GLB conserva **los 23 accessors completos** —incluidos geometría, normales,
tangentes, pesos e inverse binds— y el mismo documento de rig/materiales.
No se recalcularon formas, poses, medidas, rig ni ropa. Se mantienen **43.345
triángulos / 31.450 vértices glTF**, tres materiales y una única piel de 54 joints.

`atlas_tools.py` normaliza de forma idempotente y el bake de piel genera alfa
opaco reproducible. Se comprueban RGBA8/2048 en fuente y GLB; no se desactiva
`--verbose`, no se ocultan avisos y no se modifican `.import`, Godot, settings
de coordinación ni pruebas de partido. La comprobación independiente con
Pillow/NumPy confirma RGB idéntico y alfa 255 dentro del binario exportado.
Regresiones: **27/27**, **19/19**, **29/29**, **21/21** guardas, tres pruebas de
conversión/opacidad/idempotencia y las tres anteriores de pipeline.

Comandos ejecutados:

```powershell
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\normalize_skin_normal.py -- --apply
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\validate_integration_contract.py
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\export_athlete.py -- --permit-game-export --approval "Coordinacion 2026-09-15 16:11+02:00: R3 + normalizacion tecnica exclusiva skin_normal RGB8 a RGBA8 alpha255; RGB/geom/rest/UV/pesos intactos, sin nueva ronda artistica; reemplazo avisado y hashes finales obligatorios."
& $blender --background --factory-startup --disable-autoexec --python-exit-code 1 --python art\source\athletes\court_athlete\normalize_skin_normal.py -- --verify-export
```

Se avisó antes de reemplazar el GLB `79ad…`, que permaneció intacto durante
la preparación. Las capturas del EXE congelado con `79ad…` mantienen su
atribución; la normalización de Lambert no añadió renders ni retoques artísticos.

**Cierre técnico confirmado por coordinación — 2026-09-15, 16:55.**
Reimportado el GLB `72bb…` y validado en motor y en el EXE SHA-256
`4b1892467e21e946cee3722d1bcf243570d370b67933367fb5f2b83f8ddaf9a5`.
Los nueve PNG extraídos son RGBA8, con alfa 255 y RGB idéntico a sus maestros.
El aviso RGB8 está **ausente** en la ejecución final con lector estricto
`--verbose`, sin whitelist ni supresión. Son resultados ejecutados y comunicados
por coordinación, no una revisión independiente de Lambert.

Nueve checks permanentes nuevos de RGBA8 opaco/tres materiales elevan piel de
268/268 a **277/277**. Restantes contratos finales: **67/67 rig, 190/190 gestos,
232/232 visual y 238/238 integración**. Evidencia de fuente en
`.dream-loop\athlete-upgrade\validation\r3-final-source-45160fa792e84c51b34016e21d13f8ee`
y comprobación de piel identificada como `rgba-skinning-80efa98a0ed24679b8267e5819d74a4a`.
Los controles automatizados de «visual» no equivalen a juicio artístico.

Evidencia del EXE/candidato/exportación/validación runtime en
`.dream-loop\athlete-upgrade\builds\r3-rgba-final-e7ca816f0fd7448d8fc679481cf71cb4`:
**1.097 controles headless y 1.137 en ejecución renderizada con 20 PNG**,
validados por el lector estricto. Cinco negativos de URI/rutas existentes con
`--verbose` devuelven código 2. Incluye nueve vistas reales, cobertura de cortes
con 25 renders y sprint con al menos 24; no son mediciones de FPS.

La autorrevisión de coordinación de frente, dorso, sprint y 5v5 aprecia una
mejora anatómica clara y las principales grietas resueltas. Persisten pelo tipo
casco, manos abiertas y limitaciones de acabado superficial, calzado y bajos.
**R3 artística cerrada en 3/3 y codificación resuelta; GO técnico independiente
de Vasquez (`SOURCE_APPROVE` + `ARTIFACT_APPROVE`) para EXE `4b189246…` y GLB
`72bb…`.** Preview local entregada en
`build\windows\players-r3-preview\FutsalPlayers-preview.exe` y ZIP
`build\windows\futsal-players-r3-preview-windows-x86_64.zip`
(44.608.409 bytes; SHA-256 final
`9c6a46d6186f0bbab3f88167a4e19c1b437c0919ac0380c722bf136fdd148ac4`),
separada de la 0.4 pública; sin aprobación de G2/G3, mando ni publicación.
El hash final sólo incorpora la errata documental de `README.txt` y
`BUILD_INFO.json`: arranque normal 5v5; F1 permite elegir 1v1/5v5.
EXE `4b189246…` y GLB `72bb…` intactos, sin reexportación ni nueva ronda.
No está listo para el juicio formal frente a FIFA/GOALS,
no hay score ni >=8, aceptación artística/gate o FPS aprobados. Este cierre
no autoriza R4 ni más modelado o exportaciones.

#### Fuentes para publicación 0.5.0-preview — 2026-09-16

Nueva autorización explícita de publicación de los gráficos: coordinación
prepara **0.5.0-preview para tres OS**, manteniendo 0.4 inmutable. Esta autorización
de distribución sustituye la restricción de publicación anterior, **no** concede
G2/G3, calidad FIFA/GOALS, puntuación >=8, FPS o aceptación humana. Lambert sólo
prepara sus fuentes/procedencia; no publica, cambia versiones ni filtros LFS.

Se conservan byte a byte el `.blend` **34b519…**, el GLB **72bb973c…**, los trece
maestros PNG, los nueve PNG extraídos por Godot, sus diez `.import` contando
el del GLB, ambos manifiestos de rig y la evidencia de normalización:
**37 archivos protegidos sin cambios**. Los dos recursos LFS suman
**41.989.165 bytes**. No se modeló, horneó, renderizó ni reexportó el atleta.

Se retiraron únicamente las nueve copias PNG de `runtime\textures` y sus nueve
`.import` (**5.531.963 bytes**). La búsqueda por rutas y UID no encontró
consumidores fuera de sus propios imports; el contrato real sigue usando las
imágenes del GLB y COLOR0. `export_athlete.py` deja de producir ese set: publica
localmente sólo GLB y los dos JSON de integración, comprobando los nueve
payloads embebidos contra los maestros. **No cambian los importflags de Godot.**
Las copias retiradas y los manifiestos previos permanecen íntegros en
`.dream-loop\athlete-upgrade\publication-cleanup`; los informes históricos no
se reescriben como si aquellas copias nunca hubieran existido.

Procedencia comprobada: **Body Male - Realistic, Dan Ulrich, CC0**, con el
fingerprint de la geometría original conservado. `license_scope` aclara que
CC0 corresponde a la base; no asigna licencia general de reutilización al
código/arte propios, conforme a `THIRD_PARTY_NOTICES.md`. La fuente contiene
sólo la base seleccionada y los objetos de autoría locales, sin bibliotecas
enlazadas, textos ejecutables, acciones, drivers, clips o sonidos ajenos.
La referencia débil de Blender al bundle es trazabilidad de append, no una
dependencia: se comprobó la fuente en un árbol temporal sin bundle/cache,
con únicamente `.blend` y mapas, manteniendo los datos y los 27 controles de rig.
El marcador `Render Result` está vacío; no contiene una captura. El EXIF de
los tres maestros AO contiene sólo resolución X/Y de 72 DPI. No fue necesario
modificar el `.blend` ni los mapas por privacidad.

Inventario final de rutas, tamaños, SHA-256 y exclusiones:
`build\publication\graphics05-assets\inventory.json`. Se conservan el maestro,
los catorce scripts de autoría/validación, los trece mapas y los manifiestos
necesarios. Se excluyen de publicación el bundle completo, referencias privadas,
caches, capturas/logs y copias históricas; las referencias a evidencia local
en los manifiestos históricos no implican distribuir esos archivos.

Validación acotada ejecutada con Blender `--background --factory-startup
--disable-autoexec --python-exit-code 1`: `validate_integration_contract.py`
da **27/27 rig, 19/19 estructura, 29/29 contactos y 21/21 guardas**, más diez
casos de mapas/publicación, cuatro de privacidad/metadatos y tres de fuente
aislada. `audit_publication.py` da **14/14**. Informes en el mismo directorio
del inventario; pruebas con copias temporales, sin ejecutar el exportador glTF,
reconstrucción completa ni Godot. No se atribuyen a esta limpieza nuevos
resultados nativos, FPS o aceptación artística.

**Fuentes preparadas; revisión independiente de Vasquez pendiente antes de
publicación por coordinación. R3 sigue en 3/3, sin cuarta ronda.** Se mantienen
los límites visuales de pelo, manos, acabado superficial, calzado y bajos.

## 4. Tres briefs de captura futura

Todos a **1920 × 1080 nativos, 16:9**, desde el ejecutable real una vez implementado. No son imágenes existentes ni encargos de producción en esta fase. A es el objetivo principal del bucle; B y C son comprobaciones complementarias, no autorización para tres bucles paralelos.

Para describir cámaras sin confundir ejes de autoría y runtime: origen en el centro del suelo, **u** a lo largo de los 40 m, **v** a lo ancho de los 20 m y **h** vertical. FOV indicado horizontal; registrar su conversión al configurar Godot.

La cámara elevada es virtual y puede quedar sobre la cubierta del pabellón. Prever una regla fija de visibilidad para la cubierta y pared interpuestas, conservando sus sombras y la estructura visible restante. Aplicar la misma regla en partido, referencia y capturas; no ocultar atletas, público o defectos para favorecer una evaluación.

### A. Jugada protagonista desde retransmisión, con referencia por fase

| Referencia | Gate y atletas en pista | Acción reproducible |
| --- | --- | --- |
| **A-G2** | Micro 1v1 de campo + dos porteros: **cuatro atletas**, dos por lado | Pase raso del humano de campo a su portero y devolución; pie de apoyo plantado |
| **A-G3** | Partido 5v5: **diez atletas**, cuatro de campo y un portero por lado | Pase raso entre dos compañeros de campo, con oposición y ambos porteros presentes |

Son **dos imágenes y aprobaciones distintas**, no una imagen de diez atletas aplicada a G2. Congelar dentro de cada fase cámara, resolución, acción y recuento de referencia/candidato. Todos sus atletas y elementos mayores deben estar presentes en el encuadre aprobado. Una nota de A-G2 no se hereda en A-G3; comparar cuatro contra diez no supera Tier 1.

- **Cámara:** perspectiva elevada junto a banda, posición inicial `(u=0; v=-24; h=18) m`, mirada hacia `(u=0; v=0; h=0,4) m`, FOV horizontal aproximado de 66°. Encuadre amplio de la jugada, con portería y centro como referencias; seguimiento suave, sin zoom dramático. La matriz final se congela al calibrar la referencia.
- **Acción:** la indicada en A-G2 o A-G3, nunca mezclando sus recuentos. No congelar una pose imposible solo por espectacularidad.
- **Luz/hora:** 19:30, luminarias amplias de 4300 K, relleno del pabellón y exterior frío subordinado.
- **Paleta/contraste:** equipo petróleo oscuro frente a marfil con acento terracota; porteros diferenciados. Balón claro con paneles grafito sobre madera de luminancia media.
- **Materiales:** reflejos suaves del barniz, costuras discretas, postes pintados y red estable. Público sin detalle competitivo.
- **Captura:** referencia y candidato sin HUD para comparar arte; una captura adicional con HUD prueba que marcadores e interfaz no ocultan la jugada. No modificar exposición o retirar público solo para el candidato.

### B. Atleta con balón, detalle que soporta el acercamiento

Comprobación complementaria desde G2 y repetida en G3; no sustituye la captura A de su fase.

- **Cámara:** tres cuartos de cuerpo entero, altura 1,15 m, distancia inicial 4,5 m y lente equivalente a 50 mm en sensor de 36 mm, FOV horizontal cercano a 40°. Incluir ambos pies y balón; no recortar el apoyo problemático.
- **Acción:** control con suela seguido de giro; elegir un fotograma de una secuencia realmente reproducible.
- **Luz/hora:** mismo pabellón a las 19:30 y misma base de 4300 K; aprovechar una luminaria lateral, sin un sistema de iluminación de lujo exclusivo para la captura.
- **Paleta/contraste:** uniforme petróleo, dorsal marfil, fondo grafito desaturado; silueta separada sin halo de emisión.
- **Materiales:** trama visible a distancia apropiada, pliegues en cadera/rodilla, piel natural, unión calcetín-zapatilla y paneles del balón. LOD de acercamiento reutilizable, no un modelo distinto sin presupuesto.
- **Captura:** tiempo real, sin render offline, desenfoque que esconda defectos ni retoque. Revisar también los fotogramas anterior y posterior.

### C. Editor de equipo y choque local/visitante

Comprobación de **G4**, no un requisito para iniciar G2 ni permiso para adelantar menús.

- **Cámara:** atleta completo en zona de previsualización, altura 1,1 m, distancia inicial 4 m y FOV horizontal aproximado de 44°, adaptado al rectángulo de vista real. Panel de controles de unos 600 px a la izquierda; no renderizar a 1920 px y comprimirlo silenciosamente.
- **Escena:** rincón sencillo del mismo pabellón, con una segunda previsualización ligera para comparar equipos/equipaciones. Reutilizar recursos; no construir otro escenario.
- **Luz/hora:** 19:30, iluminación neutra de 4300 K y exposición fija para juzgar color, coherente con el partido.
- **Paleta/contraste:** UI grafito/marfil; muestras con nombres, patrón y formas además de color. Foco de mando inequívoco; local, visitante y portero comparables.
- **Materiales:** exactamente el tejido, máscaras y escudo del partido. El marfil no se vuelve autoiluminado; los tonos oscuros conservan trama.
- **Captura:** interfaz funcional del ejecutable, no texto generado dentro de una imagen como prueba del editor. Mostrar un cambio de color/escudo y comprobar después su persistencia y aspecto en pista.

## 5. Referencias pendientes y prompts por fase

### Referencias visuales de FIFA / EA Sports FC

El usuario indicó afinidad con FIFA/EA Sports FC como referencia visual, salvando las distancias entre fútbol de campo y fútbol sala. Investigación en `docs\VISUAL_REFERENCES.md`, con texto oficial y las dos imágenes de comparación de Rush inspeccionadas por coordinación. Las galerías de pabellón de UEFA/FIFA/LNFS no estuvieron accesibles para inspección:

- **Cámara:** EA propone *Rush Broadcast* como cámara horizontal cercana a la acción y *Tactical* como alternativa más abierta; el composite muestra ambas desde banda. Nuestra cancha de 40 × 20 m es menor que Rush (aproximadamente 64 × 47 m). La posición y el FOV de §4.A son una **propuesta, no una medida extraída de EA ni una aprobación por imagen del usuario**.
- **Legibilidad de equipo:** FC 25 documentó en texto que los problemas de identificación de equipo en cancha pequeña son reales y requirieron soluciones de UI (ping, flechas, colores por jugador). Coherente con la propuesta de círculo/rombo/triángulo de este documento.
- **Motion Blur:** FC 26 documenta un ajuste independiente de bajo coste. Apagarlo en partido es una decisión de legibilidad de este proyecto, no una afirmación sobre la configuración predeterminada de EA.
- **Qué NO copiar de FIFA/EA:** estadio masivo, césped de campo, cámara broadcast de 11v11 (jugadores diminutos), porterías estándar, inertia de campo abierto, activos/rostros/clubs/kits licenciados de EA.
- **Fuentes primarias para que el usuario observe pabellones reales:** <https://www.youtube.com/@LNFSoficial> (LNFS) y <https://www.uefa.com/futsaleuro/> (UEFA Futsal EURO) — no inspeccionadas por esta sesión, disponibles para el usuario.

**No hay generador habilitado ni referencia aprobada.** El usuario puede aportar imágenes con derechos que cumplan A-G2/A-G3 y aprobar cada archivo; no necesitan haber sido generadas. Alternativamente, los prompts siguientes preparan una capacidad autorizada futura: no se ejecutan ni se contrata un proveedor. Una imagen generada será **referencia sintética de apariencia in-engine**, nunca evidencia del juego.

Prompt exacto para **A-G2, cuatro atletas**:

```text
Genera una única imagen objetivo con apariencia de captura de un videojuego 3D ejecutándose en tiempo real: “in-engine screenshot”, no ilustración, pintura, fotografía ni render cinematográfico offline. Salida nativa de 1920 × 1080 píxeles, relación 16:9, sin reescalado.

Es una escena de fútbol sala creíble y visualmente muy cuidada en un único pabellón pequeño de alta calidad. La cancha de madera barnizada mide 40 × 20 metros, tiene marcajes auténticos de futsal de 8 centímetros, porterías de abertura 3 × 2 metros con postes de espesor plausible y redes tensadas con anclajes. Añade bancos, protecciones, cubierta y luminarias deportivas bien construidas, pocos elementos secundarios y público moderado y desaturado.

Usa una cámara de retransmisión en perspectiva elevada desde la banda. Con el origen en el centro de la pista, u longitudinal, v transversal y h vertical, sitúala aproximadamente en u=0, v=-24, h=18 metros y dirígela hacia u=0, v=0, h=0,4 metros, con FOV horizontal de 66 grados. Encuadra ampliamente la jugada con una portería y el centro como referencias claras. La cubierta y pared interpuestas no bloquean esta cámara virtual de juego; conserva sus sombras y la estructura visible restante. No uses ojo de pez, ángulo a ras de suelo ni perspectiva exagerada.

Muestra exactamente cuatro atletas adultos de proporciones deportivas realistas en pista, todos presentes en el encuadre: un jugador de campo humano y su portero frente a un jugador de campo rival y su portero. Es la micro slice 1v1 más dos porteros, no un partido 5v5. El humano de campo viste azul petróleo oscuro y el rival, marfil con acentos terracota; ambos porteros llevan equipaciones claramente diferenciadas. Captura un pase raso del humano de campo a su propio portero, con pie de apoyo bien plantado y balón blanco con paneles grafito claramente visible. Usa anatomía coherente, zapatillas de pista, tejido con costuras y pliegues por tensión; no figuras de juguete.

Es una tarde de partido a las 19:30. La iluminación principal procede de luminarias amplias de techo de unos 4300 K, con sombras legibles y exposición equilibrada. El exterior crepuscular frío apenas aparece en los accesos. La madera miel de luminancia media presenta fibra a escala, juntas discretas y reflejos suaves y anchos del barniz; no parece mojada ni un espejo. La ropa es mate, la piel natural y las porterías son de metal pintado. Todos los materiales son físicamente plausibles y viables para un juego en tiempo real de alcance contenido.

Prioriza lectura del balón, separación de equipos, composición limpia y acabado artesanal. Evita superficies planas de low-poly, caricatura, primitivas redondeadas brillantes, aspecto de plástico procedural, ruido fotográfico, suciedad excesiva, cientos de objetos diminutos, detalle uniforme sobre toda superficie, sobreexposición, negros empastados, neón, halos, volumétricos densos, motion blur, profundidad de campo y grano. Sin HUD, rótulos inventados, marcas comerciales, marcas de agua ni métricas de rendimiento dibujadas.
```

Para **A-G3, diez atletas**, usar el mismo prompt sustituyendo únicamente el párrafo que empieza «Muestra exactamente cuatro atletas» por el siguiente. Resolver la variante antes de enviar: nunca enviar ambos recuentos en el mismo prompt.

```text
Muestra exactamente diez atletas adultos de proporciones deportivas realistas en pista, todos presentes en el encuadre: cinco por equipo, cuatro de campo y un portero por lado. Es un partido 5v5. Un equipo viste azul petróleo oscuro; el otro, marfil con acentos terracota. Diferencia claramente ambos porteros de los jugadores de campo. Captura un pase raso entre dos compañeros de campo, con oposición, pie de apoyo bien plantado y balón blanco con paneles grafito claramente visible. Usa anatomía coherente, zapatillas de pista, tejido con costuras y pliegues por tensión; no figuras de juguete.
```

Revisar cada imagen, aportada o generada, contra los fallos **sobrecargado/ruidoso** y **simplificado/de juguete**, además de cámara/acción/recuento de su fase. Archivar las referencias aprobadas en `.dream-loop\references\g2.png` y `.dream-loop\references\g3.png`; al ejecutar una fase, `.dream-loop\concept.png` será una copia byte a byte de su referencia aprobada, con el mismo hash. No sobrescribir la referencia de otra fase ni cambiar objetivos para mejorar la nota. No crear estos archivos ahora.

Obtener aprobación humana explícita del archivo de cada fase antes de construir/comparar contra él. Un brief o documento aprobado no aprueba una imagen inexistente. Registrar fase, origen y derechos, fecha, resolución nativa, SHA-256 y quién aprobó ese hash. Para generación, añadir herramienta/proveedor y versión, prompt resuelto, negativos, semilla si existe y permisos de las entradas; para imágenes aportadas, marcar lo no aplicable. No inventar metadatos ni descargar imágenes de terceros para rellenar la dependencia.

### Pase de arte experimental — 2026-09-10

**Archivos modificados:** `game/match/presentation/arena/court.gdshader`, `game/match/presentation/arena/match_arena.gd`, `game/match/presentation/athletes/athlete_view.gd`. Nuevo: `game/tests/test_match_visuals.gd`. Sin cambios en cámara, simulación ni HUD.

**Parqué:** El grano original `sin(meters.y × 270)` contiene unas 43 oscilaciones
por metro y puede producir aliasing cuando la proyección lo reduce a detalle
subpíxel. La primera hipótesis se basó en código, no en una reproducción temporal.
El cambio reduce la frecuencia a K=50 y atenúa el grano según sus derivadas de
pantalla; las juntas adaptan su transición al tamaño de píxel. `ROUGHNESS` pasa a
0,33–0,42 (antes 0,48–0,535) y `METALLIC = 0` queda explícito. La captura inicial
de 1280×720 no demuestra estabilidad en movimiento. El A/B independiente descrito
abajo mide una reducción temporal; no una eliminación universal del parpadeo.

**Iluminación:** Ambient energy 0,5 → 0,26 (más contraste en sombras). CeilingKey: energy 1,15, shadow_bias 0,015, shadow_normal_bias 0,8. Añadidas 5 `OmniLight3D` sin sombra propia en las posiciones de las luminarias decorativas existentes (y=6,9, z=−10,8, energy 0,85, range 15 m) para rebote cálido sobre coronillas y parqué. La captura muestra sombras direccionales visibles bajo todos los atletas.

**Animación:** Frecuencia de zancada `1,6 + v×0,30` (antes `1,5 + v×0,22`); elevación de rodilla `0,08 + v×0,025` (antes `0,11 + v×0,012`); inclinación de sprint `_body.rotation.x = −sprint_blend×0,095` (hasta −5,4° a velocidad de sprint); swing de brazo escala de ×0,16 a ×0,28 en vaivén anterior y de ×0,19 a ×0,34 en posterior. **Corrección 5v5:** `_keeper = id in [2,3]` (la lógica anterior `id >= 2` era incorrecta para IDs 4–9). **Tradeoff declarado:** se omitió la ruta Blender para geometría de atleta mejorada; la definición visual permanece limitada por las primitivas procedurales actuales. El pipeline `.blend → .glb → ejecutable` queda pendiente para P2.1 antes de G2.

**Verificación pass 1:** 23/23 checks headless en `game/tests/test_match_visuals.gd`. Captura GPU (broadcast, 1280×720) en directorio privado gitignored. No hay imagen A-G2 aprobada ni gate G2 alcanzado. Cámara de §4.A sigue siendo una propuesta.

### Pase de arte 2 — 2026-09-10 (mismo día, segunda iteración)

**Archivos modificados:** `game/match/presentation/athletes/athlete_view.gd`, `game/tests/test_match_visuals.gd`. Sin cambios en cámara, simulación ni HUD.

**Definición atletas — geometría aditiva (sin cambio de API pública ni de física):** añadidos LeftDeltoid/RightDeltoid (hombros, material camiseta) inmediatamente antes de Neck para ampliar silueta torso; añadidos Jaw (mandíbula) y LeftEar/RightEar (orejas) para lectura de cabeza; añadido KneeGuard (índice 6 del array `_legs`) posicionado en `_pose_leg()` +28 mm sobre rodilla en –Z local. La API pública (`configure`, `present`, `react`, `reset_pose`) y las métricas físicas (altura 1,75 m, origen en pies) se conservan sin cambios.

**Corrección skin_colors 5v5:** `skin_colors[actor_id % skin_colors.size()]` (antes `skin_colors[actor_id]` → crash por índice fuera de rango con IDs 4–9 en partidas 5v5).

**Capturas iniciales de Lambert:** cuatro imágenes broadcast y ocho de primer
plano por variante, a 1920×1080, en `tools\godot\runtime\lambert-art-g1`.
No se utilizan como prueba temporal: el script no restablecía el FOV entre
pasadas broadcast. El tamaño comprimido de un PNG tampoco mide por sí solo
ruido, estabilidad temporal ni calidad; se retira esa inferencia.

**Verificación nativa final:** 39/39, repetidos independientemente por coordinación,
con salida 0 y stderr vacío. Se ejercitan `configure()` y `present()` para IDs
0–9 y las transiciones parado/sprint/parado. No acredita por sí sola iluminación
GPU, animación realista ni métricas de apoyo del pie.

**A/B temporal independiente, 2026-09-10:** coordinación extrajo el shader original
directamente del PCK del ejecutable G1 preservado, sin reconstruirlo de memoria.
SHA-256 del shader original: `57fde582dfdba381692a55ec39b341c29fca6f67b7cbf1ccccd861a357ba3be5`;
shader corregido: `88facc312a0a5fdc0bf9cc487cf0b6ccc7a62d1d96c5a2eac758dd4ceacd67cb`.
Se reprodujeron 240 fotogramas continuos por variante con los componentes de
arena, atleta y cámara de producción, cuatro atletas, desplazamiento, sprint y
frenada. Iluminación, FOV, trayectoria, proyecciones y poses fueron idénticos:
solo se sustituyó el shader. Render nativo 1920×1080, Forward+/Vulkan en NVIDIA
RTX 2000 Ada Generation Laptop GPU.

Sobre 129 puntos del suelo visibles en toda la secuencia, el muestreo bilineal
reproyectado al mismo punto del mundo produjo 30.702 segundas diferencias
temporales de luma por variante. Media: **2,202 → 0,537** niveles equivalentes
de 8 bits; p95: **6,459 → 1,005**, una reducción del **84,4 %** en este recorrido.
El p99 aún es 5,003: no se afirma ausencia de todo artefacto ni extrapolación a
otras cámaras, resoluciones o equipos.

Evidencia local ignorada: `tools\godot\runtime\motion-independent-f4a3783e-20260910`,
con `motion.json`, `motion_analysis.json`, diez keyframes nativos y
`comparison.avi` (541 fotogramas, incluidos calentamientos, a 60 pasos/s).
Es un replay controlado de componentes visuales, no una prueba de input/física
ni un playtest humano. Movie Maker tardó 38 s en producir unos 9 s de vídeo;
sus tiempos medios no sustituyen el protocolo de FPS ni aprueban 1080p60.

## 6. Pipeline de arte portátil y reproducible

### Fuente editable y frontera de intercambio

Organización propuesta, **sin crear carpetas ni activos ahora**:

- `art\source\`: `.blend`, texturas maestras, rig de autoría y acciones editables.
- `game\assets\`: destino directo de `.glb` y mapas runtime, con nombres/materiales estables; Godot los importa desde ahí. Sin otra copia intermedia en `art\exports\`.
- Fuentes `.blend` **fuera de `game\`**; recursos importados/cachés no sustituyen las fuentes.
- `.dream-loop\`: referencias por fase, metadatos, capturas y resultados del futuro bucle; ya excluido por el tooling. No modificar `.gitignore` en esta integración.

Recomendación: **`.blend` → glTF 2.0 binario `.glb` → importador del motor**, evitando cambiar continuamente de herramientas o mantener manualmente dos versiones del mismo objeto. `.gltf` con texturas separadas es una alternativa si facilita mapas compartidos, revisión o edición del material común.

La documentación de Godot recomienda glTF; su importación directa de `.blend` llama a Blender para generar glTF y requiere Blender en el equipo de importación. Aquí se elige exportación explícita a `game\assets\`, no importación de `.blend` desde el runtime. Verificar skinning, animaciones y materiales con el importador Godot 4.7 antes de fabricar variantes; los probes GLB del tooling comprueban intercambio básico, no un atleta, rig ni contactos.

### Receta de exportación y calibración

1. **Fijar versiones.** Registrar Blender 4.5.13 LTS, exportador y Godot 4.7.2/importador realmente utilizados; instalación del motor según evidencia de Ferro. Revalidar al cambiar versiones. No dar por hecho que un `.blend` guardado por una versión posterior abre sin pérdida en una anterior.
2. **Unidades y ejes.** Una unidad de Blender representa **1 m**. Preparar escala y rotación antes de riggear, evitar escalas negativas y fijar pivotes útiles. Blender usa Z arriba; comprobar conversión a Y arriba de glTF. En Godot: Y arriba, cámara mirando a **−Z**, frente de activos orientados a **+Z**; en Blender el frente correspondiente es **−Y**. Verificar con una regla de 1 m, un atleta asimétrico, una portería y un movimiento hacia delante; no corregir cada recurso con giros arbitrarios de 180°.
3. **Geometría estable.** Mantener fuente no destructiva; evaluar modificadores y triangular consistentemente antes del horneado/exportación. Revisar normales, tangentes, caras posteriores, seams y UV. No aplicar transformaciones destructivas a un rig ya animado. Exportar desde pose de reposo correcta.
4. **PBR interoperable.** Principled BSDF con imágenes y canales reconocidos por el exportador; no confiar en que nodos procedurales complejos viajen al motor. Hornear normal y AO desde el detalle de autoría. El AO representa oclusión local, no sombras direccionales pintadas; evitar duplicarlo exageradamente en el motor.
5. **Espacio de color.** Base color y emisión en texturas sRGB; roughness, metallic, AO, máscaras y normales en datos lineales/Non-Color. glTF empaqueta **R = AO, G = roughness, B = metallic** cuando se usa ORM. Para AO, comprobar la conexión de exportación documentada (`glTFMaterialOutput`, entrada `Occlusion`), no solo su apariencia en Blender.
6. **Normal y textura.** Normal en espacio tangente, convención **+Y/OpenGL**, horneado R:+X, G:+Y, B:+Z; marcar la orientación y no invertir el canal verde por costumbre. Si otro importador requiere adaptación, verificar una superficie con relieve conocido. PNG para mapas de datos sin pérdidas; PNG/JPEG son formatos de imagen admitidos por el exportador glTF. Generar y revisar mipmaps, filtrado y compresión de GPU en el motor elegido; vigilar líneas, red, dorsales y escudo.
7. **Rig y animaciones.** Exportar huesos deformantes y root necesario mediante un preset explícito, sin controles de autoría. Hornear constraints/IK a pistas compatibles, inicialmente muestreadas a 60 Hz, con nombres, duraciones, bucles y contactos definidos. Si se usan shape keys, revisar la advertencia de Godot sobre `Export Deformation Bones Only`. Probar todos los clips: el visor de Blender no demuestra que sobrevivan al intercambio.
8. **LOD y materiales.** Mantener silueta, rodillas, pies, UV y asignaciones de kit entre niveles. No simplificar automáticamente sin revisar apoyos, red y contornos. Activar backface culling donde corresponda; doble cara solo donde sea necesaria. Evitar transparencias apiladas y materiales por accesorio. En Godot, las opciones avanzadas permiten configurar LOD y materiales externos para conservar personalizaciones al reimportar.
9. **Calibración de luz.** Usar carta neutra y muestra de madera/tejido para revisar exposición, balance de blancos y roughness. Registrar transformación de vista de Blender y tonemapping del motor; no suponer igualdad entre AgX, otros tonemappers y el ejecutable. La iluminación definitiva se calibra dentro del motor, aunque la fuente contenga luminarias.
10. **Exportar, importar y capturar.** Un preset versionado, selección explícita de colecciones, rutas relativas y una sola operación de exportación por revisión. Registrar hashes de fuentes, mapas y exportaciones, opciones de animación/tangentes/compresión e importación. Repetir desde las mismas entradas debe reproducir el resultado; investigar diferencias en vez de «arreglar» la copia importada manualmente.

La prueba de cierre es una captura **del ejecutable exportado en tiempo real**, con versión de build identificable. Un viewport de Blender sirve para autoría; un render de Cycles sirve para hornear o estudiar materiales. **Ninguno acredita la apariencia ni el rendimiento del juego.** Tampoco basta un visor de glTF o el preview del importador.

## 7. Presupuesto provisional: 1080p y 60 Hz

Equipo objetivo: **NVIDIA RTX 2000 Ada Generation Laptop GPU**, con **8188 MiB de VRAM dedicada (~8 GiB)** y controlador **595.95**, verificados por coordinación mediante `nvidia-smi` el 2026-09-09. Comando y salida exactos en `docs\MVP.md`; no se usa una estimación de Win32. CPU Intel Core Ultra 9 185H, 16 núcleos/22 lógicos; RAM 63,4 GiB según el inventario comunicado.

Esto **no acredita FPS, consumo ni GPU efectiva del ejecutable**. Registrar dispositivo/driver realmente usados, alimentación, perfil de energía, temperatura y resolución antes de medir; no inferir TGP ni potencia sostenida por el nombre o la capacidad de VRAM.

Todos los valores siguientes son **objetivos iniciales no alcanzados ni garantizados**, a revisar mediante perfilado del ejecutable. Menos triángulos no implica automáticamente mejor imagen ni más FPS.

| Recurso o métrica | Objetivo inicial | Condición de lectura |
| --- | --- | --- |
| Resolución | 1920 × 1080 nativa, escala 100 % | Sin resolución dinámica, reescalado ni generación de fotogramas para acreditar el objetivo |
| Tiempo de fotograma de trabajo | **p95 ≤ 14,5 ms; p99 ≤ 16,0 ms** | Medición técnica sin VSync ni limitador, dejando margen frente a **16,67 ms** de 60 Hz |
| GPU / hilo principal | GPU p95 ≤ 12 ms; hilo principal p95 ≤ 5 ms | Diagnóstico separado; CPU y GPU se solapan, no sumar percentiles como si fueran el tiempo total |
| Presentación a 60 Hz | Cadencia de 16,67 ms; p95/p99 ≤ 16,67 ms + 0,5 ms de tolerancia de medición | Prueba adicional con sincronización; menos del 0,1 % de intervalos > 20 ms, sin tirones recurrentes de 33,3 ms |
| Geometría visible de partido | ≤ 1,0 millón de triángulos en pase principal; ≤ 2,5 millones sumando pases | Incluir sombras/reflejos en el segundo contador; no comparar contadores distintos entre motores |
| Atleta | LOD0: 45–65 mil; LOD1: 18–28 mil; LOD2: 6–10 mil triángulos | LOD0 para cercanía, LOD1 normalmente en pista; suplentes según tamaño en pantalla y visibilidad |
| Arena y decoración | 150–350 mil triángulos visibles como punto de partida | Público/banquillos adicionales contabilizados en el total, con instancias y LOD |
| Draw calls | ≤ 250 en pase principal; ≤ 600 incluyendo sombras, extras y UI | Contar llamadas reales del renderer, no objetos de la escena |
| Texturas | Normalmente 1K–2K; 4K solo en superficies protagonistas justificadas | Reutilizar tiling/atlas; no una textura 4K diferente por atleta o equipación |
| Texturas residentes de GPU | ≤ 1 GiB inicial | Medir residencia con mipmaps y compresión, no tamaño del `.glb` en disco |
| Memoria total de GPU del juego | ≤ menor de **2 GiB** y **70 % de la VRAM dedicada medida** | En la NVIDIA observada, el límite provisional es 2 GiB. Incluye geometría, texturas y render targets; medir consumo y recalcular si cambia el dispositivo |
| Memoria de proceso | ≤ 3 GiB de conjunto de trabajo tras calentamiento | Provisional; medir también pico de carga y crecimiento tras cambiar equipos |
| Sombras/transparencia | 1–2 luces dinámicas con sombra como inicio; transparencia visible contenida | Optimizar red, público y pelo; no depender de decenas de focos con sombra |

**Protocolo:** calentar 120 s y registrar tres recorridos reproducibles de 180 s del caso más cargado **de la fase**, con semilla/estado y cámara identificados. G2 mide cuatro atletas y sus secuencias micro; G3 repite con diez, IA y reglas completas. Cubrir porterías, red, áreas, banquillos, giro de cámara y kits disponibles; comprobar las tres dificultades al introducirlas en G3/G4, sin adelantar menús para medir G2. Medir posteriormente una sesión de mando de 10 minutos para detectar temperatura, carga irregular y tirones.

Conservar distribución de frame times, p95/p99, FPS observados, fotogramas perdidos, tiempos CPU/GPU y memoria. No acreditar «60 FPS» mediante una media aislada, una etiqueta sobre una imagen o el contador del editor.

Si falla: buscar primero culling, instancias, sobrecoste de pases, reutilización de materiales, sombras, público y reflejos. **No sacrificar primero el balón, los pies, los contactos o la respuesta.** Cada optimización vuelve a las mismas capturas y secuencias; un perfil visual inferior debe declararse, no hacerse pasar por el objetivo aprobado.

## 8. Dream-loop: uso acotado y crítico independiente

La skill oficial y su MIT están vendorizadas **sin modificaciones** en `.github\skills\dream-loop`, commit `d113b78bd8143d6c4e2b46840c1a881139bcc084`; procedencia en `UPSTREAM.json` y verificación de Ferro en `docs\TOOLING.md`. Instalada no significa ejecutada ni descubierta en toda sesión del CLI. Este documento y `.squad\skills\futsal-art-quality\SKILL.md` complementan el original, no lo sustituyen.

Conservar `SKILL.md` y `LICENSE` intactos. Una actualización exige revisar el nuevo commit y sus hashes; no descargar una rama mutable y llamarla revisada.

### Entrada y comparación justa

No ejecutar el bucle sin imagen objetivo aprobada, motor/importador operativos, capacidad de captura del ejecutable, medición real de rendimiento y crítico independiente disponible. Esta entrega solo prepara esas condiciones.

En cada ronda futura:

1. Trabajar sobre los bloqueos de mayor impacto; realizar una autoinspección honesta antes de consumir una crítica.
2. Capturar el ejecutable contra la referencia aprobada de **esa fase**, con la misma resolución, proporción, cámara, acción, número de atletas, iluminación, exposición, HUD y perfil gráfico. Registrar matriz/FOV, tiempo o tick y hashes. En referencias generadas, distinguir cámara pretendida de la cámara real calibrada; no inventar metadatos.
3. Entregar al crítico de contexto limpio la referencia, captura actual y, desde la segunda ronda, captura/veredicto anterior. No alimentarlo con elogios del constructor. Un autojuicio puede orientar, pero no sustituye el requisito de independencia.
4. Adjuntar mediciones separadas de FPS/frame time. Una imagen no contiene evidencia temporal.
5. No retocar capturas, ocultar defectos con recortes, renderizar a resolución mayor, cambiar el objetivo a mitad de ronda ni presentar Blender como juego.

### Escalera 0–10 con cinco niveles bloqueantes

Entregar al crítico el **prompt upstream íntegro** de `.github\skills\dream-loop\SKILL.md`, sección Judge. La tabla siguiente es una guía de lectura, no una rúbrica alternativa ni permiso para modificar el prompt o sus techos.

| Nivel | Rango / techo mientras falla | Puerta |
| --- | --- | --- |
| 1. Forma | 0–3 / techo 3 | Cámara, composición y elementos mayores presentes; posiciones aproximadamente dentro del 10 % del ancho/alto y escala dentro del 25 % del objetivo |
| 2. Luz y color | 3–5 / techo 5 | Dirección, exposición, sombras, paleta, contraste, reflejos y atmósfera global coherentes; sin blancos o negros destruidos |
| 3. Materiales y superficies | 5–7 / techo 7 | Cada superficie se reconoce; roughness, textura y relieve creíbles; protagonistas sin apariencia de bloques, plástico o primitivas blandas |
| 4. Detalle fino | 7–9 / techo 9 | Costuras, bordes, contactos, red y alineación precisos; materiales convincentes también al inspeccionarlos |
| 5. Equivalencia visual | 9–10 | Comparación lado a lado y ampliada sin diferencias significativas respecto al objetivo |

No promediar para saltarse puertas. **Una nota ≥ 8 requiere resolver por completo los niveles 1–3 y avanzar en detalle; no implica automáticamente que todo el nivel 4 esté superado.**

El crítico devuelve nota, mayor nivel completamente superado, estado de las directivas previas (`LANDED`, `PARTIAL`, `NOT DONE`), bloqueos de la siguiente puerta y hasta cuatro indicaciones adicionales. Cada indicación identifica elemento, modificación y magnitud verificable; mantener pendientes entre rondas y justificar cualquier inversión de criterio. No emitir notas sobre imágenes que no existen. **Puntuación actual: no evaluada.**

### Salida, atasco y gasto

- Salida visual solo con **nota ≥ 8 Y FPS reales aceptables**, incluidos los objetivos de p95/p99. La aceptación del juego exige además las pruebas de movimiento y mando de la sección 9.
- Si la imagen supera 8 pero no el rendimiento, optimizar con mínima pérdida y volver a evaluar; no declarar finalizado.
- **Límite del proyecto: máximo 3 rondas por gate y parada tras 2 sin mejora**; también por falta de entrada, error repetido o presupuesto agotado. La señal upstream de no ganar un punto completo en dos rondas sirve para diagnosticar estancamiento, no para autorizar rondas extra.
- Si se atasca, detener y proponer un cambio estructural acotado de activo/material/luz/composición para un nuevo encargo. Cambiar objetivo o cámara exige nueva aprobación; no hacerlo para eludir Tier 1. No reiniciar el contador automáticamente.
- **Presupuesto de APIs pagadas: 0**. Un generador necesita autorización de proveedor, coste y límite; hasta 3 intentos de referencia solo si se autorizan expresamente. La ruta de referencia aportada no requiere contratar una API. No hay generación ni producción de assets en esta entrega.
- No prolongar automáticamente, multiplicar críticos ni abrir bucles paralelos. Agotar presupuesto no convierte un trabajo insuficiente en aprobado: conservar evidencia y estado pendiente para decidir el siguiente bloque.

El MCP comunitario de Blender puede exponer ejecución arbitraria de código. Ferro debe limitar su implementación a loopback/`localhost`, sin exposición a red, con revisión del código ejecutado, acceso mínimo al proyecto y proveedores externos de generación desactivados. No se conecta ni ejecuta ese endpoint en esta planificación.

## 9. Puertas de calidad del plan y revisión en movimiento

Se usan exactamente los **G0–G5 de `docs\DEVELOPMENT_PLAN.md`**, no otra numeración artística. G1 está autorizado; las pruebas automáticas de sus componentes no cierran los gates humanos ni los visuales posteriores.

| Puerta | Hito y evidencia necesaria |
| --- | --- |
| G0 — Preparación técnica | Stack elegido, herramientas/exportación y contratos con evidencia/revisión. La referencia aprobada es entrada de G2; su ausencia no impide una micro slice gris autorizada |
| G1 — Sensación micro | 1 humano de campo, 1 rival de campo y 2 porteros; movimiento, balón, cámara y mando validados. Calibrar metros/ejes y contactos sin fingir arte final |
| G2 — Arte integrado micro | Round-trip `.blend` → `.glb` → ejecutable con PBR/rig/reimportación, cuatro atletas y referencia A-G2 aprobada; crítico independiente ≥ 8 **y** rendimiento, movimiento y lectura verificados |
| G3 — Partido 5v5 | Diez atletas, reglas e IA; referencia A-G3 aprobada y repetición de crítica, rendimiento, movimiento/mando. No heredar la nota de cuatro atletas |
| G4 — Slice coherente | Plantillas de 12, editor/local/visitante/porteros, equipos rápidos y tres dificultades conservan calidad; capturas B/C, cambios persistentes y regresiones visuales revisados |
| G5 — Consolidación | Exportación reproducible, fuentes y derechos trazables, memoria estable y pruebas repetibles; repetir lo pertinente tras cambios de motor, activos o renderer |

### Criterios medibles, todavía no alcanzados

Revisar vídeo del ejecutable a 60 FPS, velocidad normal y fotograma a fotograma. La métrica espacial necesita instrumentación en el motor, no estimaciones en centímetros a partir de una imagen. Cubrir ambos pies, giros a ambos lados, frenadas, pases, tiros, controles con suela y portero.

| Comprobación | Objetivo inicial y muestra |
| --- | --- |
| Pie plantado | En ≥ 100 apoyos, desplazamiento residual en mundo p95 ≤ 2 cm y ningún apoyo > 5 cm; excluir solo arrastres de suela intencionados etiquetados |
| Suelo y extremidades | Ninguna penetración visible > 1 cm durante más de 2 fotogramas; revisar transiciones y LOD, no solo poses clave |
| Contacto balón-pie | En ≥ 50 pases, 20 tiros y 20 controles repartidos entre pies, separación visual respecto al punto de contacto ≤ 3 cm y desfase con evento de simulación ≤ 1 tick de 60 Hz |
| Balón y cámara | Diámetro proyectado ≥ 8 px en ≥ 95 % de fotogramas de juego sin oclusión física; cero pérdidas artificiales > 100 ms por efectos, HUD o reflejos |
| Equipos y selección | ≥ 95 % de aciertos al identificar equipo y atleta controlado en 50 muestras variadas por participante, incluyendo escala de grises y modos accesibles |
| Respuesta local al mando | Entrada → primer cambio visual pertinente: p95 ≤ 83 ms y p99 ≤ 100 ms; medir con instrumentación o cámara de alta frecuencia, separando respuesta inicial del tiempo intencional hasta golpeo |
| Experiencia humana | G1/G2: al menos 3 participantes y 10 minutos de micro slice cada uno. G3/G4: repetir 10 minutos por dificultad; mediana objetivo ≥ 4/5 en claridad/respuesta y registro de fallos, aparte del gate de sensación del MVP |

La cámara propuesta se ajusta antes de fijar la referencia si el balón resulta demasiado pequeño. Preferir encuadre/seguimiento, paneles contrastados y marcador accesible discreto antes que deformar su tamaño físico. Rechazar ghosting, pops de LOD y moiré de redes que solo aparezcan en movimiento. Una filmación a 60 FPS sirve para revisión visual; no acredita por sí sola latencias subfotograma.

**Dream-loop no evalúa por sí solo** la sensación de control, intención de pase, inteligencia colectiva, variedad o justicia de las tres dificultades. Tampoco descubre errores de autoridad, latencia, pérdida de paquetes o reconciliación del futuro cliente-servidor. Esas capacidades requieren playtests, telemetría y, en la fase multijugador, pruebas de red específicas. La belleza de un fotograma y una nota alta nunca sustituyen dichas evidencias.

## 10. Fuentes verificadas

Consulta e integración realizadas el 2026-09-09. Documentación Godot fijada a la rama 4.7 elegida; versiones instaladas y pruebas se acreditan en TOOLING.

- **Dream-loop, skill oficial:** <https://github.com/achimala/dream-loop/blob/d113b78bd8143d6c4e2b46840c1a881139bcc084/SKILL.md>. Blob revisado `f69872cfcde583be54d920ff75494b5d1befa93e` (archivo, no commit); vendorizado intacto.
- **Licencia MIT de dream-loop:** <https://github.com/achimala/dream-loop/blob/d113b78bd8143d6c4e2b46840c1a881139bcc084/LICENSE>. Copyright 2026 Anshu Chimala; blob `dd54a3e60d5fe9e2296c4745c5b826d74158c852`.
- **Blender 4.5, exportador glTF 2.0:** <https://docs.blender.org/manual/en/4.5/addons/import_export/scene_gltf2.html>. PBR reconocido, ORM, AO, normales tangentes +Y, emisión, culling y restricciones del intercambio.
- **Blender 4.5 LTS, publicación oficial:** <https://www.blender.org/releases/4-5/>. Familia de autoría; instalación exacta 4.5.13 acreditada en TOOLING.
- **Godot 4.7, formatos 3D:** <https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html>. glTF recomendado y funcionamiento de importación `.blend`.
- **Godot 4.7, consideraciones de exportación:** <https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html>. Ejes, triangulación, pose de reposo e iluminación en motor.
- **Godot 4.7, importación avanzada:** <https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/advanced_import_settings.html>. LOD y sustitución por materiales externos.

Los presupuestos, encuadres y umbrales de este documento son propuestas del proyecto, no garantías de esas fuentes.
