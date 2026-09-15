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
