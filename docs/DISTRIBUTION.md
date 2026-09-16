# Distribución de candidatos nativos

Alcance gráfico autorizado el **16 de septiembre de 2026**: preparar una nueva
prerelease **Windows x86_64, Linux x86_64 y macOS Universal2** de
`0.5.0-preview`, con las fuentes gráficas R3 y **input schema 3**.
La `0.4.0-preview`, su tag/commit y sus paquetes se conservan como históricos.
Esto no amplía el gameplay de §4.3, no completa el MVP y no aprueba arte,
sensación humana, mando físico o FPS. El pipeline construye candidatos:
coordinación gestiona el repositorio, commit y tag; **publica el release sólo
después de la verificación conjunta y QA**.
Ningún script ni workflow de este encargo crea releases o ejecuta push.
Esta preparación no es publicación ni validación nativa de 0.5: coordinación
cierra el snapshot tras la higiene de fuentes y solicita revisión independiente.

## Herramientas y fuentes fijadas

`tools\release\manifest.json` fija **Godot 4.7.2 standard**, nunca Mono/.NET.
Los tres editores y el TPZ oficial completo están fijados por **SHA-512 y tamaño**,
cotejados con `SHA512-SUMS.txt` del release `4.7.2-stable`.
Los avisos del motor proceden del commit Godot
`ed1daf0bf001b61586d9930840f2f1394092c079`; también tienen pin SHA-512.
No se modifica `tools\godot\release.json`.

Se requiere **Python 3.11 o posterior**, Git y conexión HTTPS a GitHub para los
archivos que no estén en caché. Se usa sólo la biblioteca estándar de Python:
no `pip`, SDK adicional, Node del proyecto, servicio externo o instalación
global del motor. Los runners estándar ya suministran Python/Git; macOS
también necesita los comandos nativos `codesign` y `lipo`.

La caché se valida por bytes completos en cada uso. Un archivo incorrecto
**bloquea el build**, no se reemplaza silenciosamente. Las descargas usan
archivos parciales propios, tamaño máximo, plazo de 600 s y ningún reintento
automático. El TPZ de **1.281.349.702 bytes** se descarga completo, aunque sólo
se extrae la plantilla declarada para el destino. La caché Windows existente en
`tools\godot\.cache` se puede reutilizar; no se reinstala el entorno anterior.

En macOS, el miembro `templates/macos.zip` se extrae directamente al **HOME
privado del build**, bajo
`Library\Application Support\Godot\export_templates\4.7.2.stable\macos.zip`,
antes de invocar el editor. Godot comprueba primero
esa ubicación estándar incluso con `custom_template/release`. No se instala
en el HOME real del runner ni se usa `XDG_DATA_HOME` como sustituto en macOS.
Windows y Linux conservan su directorio temporal `work/templates`.

La fuente compartida activa
`[rendering] textures/vram_compression/import_etc2_astc=true`: Universal2
requiere la opción de **importación del proyecto**, no sólo
`texture_format/etc2_astc` del preset. El configurador macOS exige el booleano
`true` antes de importar. Se conserva Forward+ y no se cambian los presets,
las políticas de firma ni los oráculos de gameplay.

### Modo declarado por plataforma

| Plataforma | Plantilla oficial | Exportación |
|---|---|---|
| Windows x86_64 | `windows_release_x86_64.exe` | `--export-release` |
| Linux x86_64, preview experimental | `linux_debug.x86_64` | **`--export-debug`** |
| macOS Universal2 | release del ZIP `macos.zip` | `--export-release` |

La excepción Linux está autorizada por el MRP del
[bug Godot #87626](https://github.com/godotengine/godot/issues/87626), abierto
en la comprobación de coordinación del 15 de septiembre de 2026.
Es un **workaround explícito con la plantilla DEBUG oficial 4.7.2**, no una
build release optimizada ni evidencia de FPS. No cambia la versión del motor,
los pins globales, Popup nativo, `embed_subwindows`, presentación o gameplay.
No hay whitelist, motor personalizado ni reducción de los smokes.

El manifest fija `buildType` para los tres destinos. Linux selecciona
`templates/linux_debug.x86_64`, con SHA-256
`1a291d3d15e4180b60b0af96cf6458f11fe143636d76575ddf1e23d1a3f24f2e`,
y declara `engineWorkaround`. El loader rechaza combinaciones incoherentes
de tipo/miembro y debug fuera de Linux. El pipeline sólo permite ese debug
en versiones `-preview`, comprueba el pin del miembro extraído y configura
`custom_template/debug`; Windows/macOS mantienen `custom_template/release`.
La CLI selecciona este modo desde el manifest: no necesita un flag adicional.

## Contrato del build

La entrada es `game\project.godot`: de ahí se obtienen nombre, versión, escena
principal e input schema. El tag, si se proporciona, debe ser exactamente
`v` + versión: **`v0.5.0-preview`**. No se cambia la versión para hacer coincidir
un tag. `--tag` identifica la versión prevista: **no exige que ese tag Git exista
ni lo crea**. Fuera del modo local explícito, el commit debe ser el `HEAD` consumido y
las fuentes, tooling y licencia utilizados no pueden tener cambios pendientes.

Los runners PowerShell distinguen la identidad fuente actual de la evidencia
histórica: `Get-GodotExpectedProjectIdentity` exige `0.5.0-preview`/schema 3.
`config\toolchain.json` conserva el cierre real 0.4 y su EXE `af23…`;
no se relabelan sus flags ni sus pruebas como aceptación 0.5. Los lectores
mantienen los contratos explícitos de 0.3/0.4 donde corresponde.

La raíz Git efectiva debe ser la raíz fuente resuelta, respetando la comparación
de rutas de cada OS: una copia dentro de una carpeta ignorada no hereda el commit
del repositorio padre. No basta `git status`: se cotejan los bytes consumidos con
los blobs de `HEAD`, incluidos el tooling ejecutado, la licencia y
`THIRD_PARTY_NOTICES.md`. Se rechazan
archivos ignorados adicionales y cambios ocultos con `assume-unchanged` o
`skip-worktree`. Se normaliza CRLF/LF únicamente en los formatos de texto
declarados; los assets LFS expandidos deben corresponder al SHA-256 y tamaño
del pointer comprometido.

Los sidecars Godot **`.import` y los `.json` del juego** son texto UTF-8:
el snapshot y el cotejo contra blobs usan la misma normalización CRLF → LF.
`.gitattributes` fija `text eol=lf` para esos formatos incluso con
`core.autocrlf=true`, y su propia política es una entrada textual consumida
y cotejada con el commit. Esto no reserializa JSON, ordena claves ni ignora
cambios de contenido. **PNG queda fijado como `-text`; GLB y blend mantienen LFS y
`-text`**, con comparación binaria exacta y validación de tamaño/hash del pointer.
No se renormalizan los assets protegidos del árbol vivo ni el índice principal.

Corregir la interpretación de metadata puede cambiar `sourceSnapshotSha256`
aunque los archivos físicos sean idénticos. El freeze nuevo registra ambas
huellas sobre los mismos bytes; los snapshots y logs del EXE anterior no se
reescriben ni se relabelan como pruebas de la nueva política. La selección
documental de 261 archivos se conserva, añadiendo sólo los deltas EOL revisados.

Cada build:

1. Fija snapshots de juego y avisos, y las huellas de los EXE históricos presentes.
   Rechaza punteros LFS sin resolver. Copia el proyecto a un directorio privado,
   excluyendo `.godot`; no importa sobre el árbol de trabajo original.
2. Extrae el editor y template verificados, configura **sólo la copia privada**
   con la ruta del template y ejecuta importación nativa. No usa `Common.ps1`,
   inventarios Windows ni el diagnóstico de Blender/Foundation.
3. Ejecuta los smokes fuente, exporta con el **modo declarado por plataforma**, prepara avisos
   y ZIP, lo extrae en una instalación temporal y ejecuta ambos smokes otra vez
   **desde el binario del ZIP extraído**.
4. Coteja bytes, PCK, permisos, enlaces, arquitectura, evidencias y preservación
   del original. Sólo entonces mueve el directorio candidato a `dist`.
   Un destino existente se rechaza; no hay sobrescritura o promoción a la activa.

El preset **0, Windows Desktop**, conserva su configuración y ruta histórica.
La CLI de release siempre proporciona una ruta de exportación aislada.
Los presets adicionales son **Linux x86_64** y **macOS Universal**.
`build\windows\FutsalG1.exe` y las copias G1/0.2/0.3/0.4 no son destinos.

Los procesos se observan mediante el objeto/handle `subprocess.Popen` original.
Salida 0 no basta: se exige **EOF de stdout y stderr**, salida acotada y reportes
de la invocación. Un hijo que herede pipes no provoca un drenaje final ilimitado:
la limpieza tiene presupuesto de **1 s**. No se recuperan testigos con una
consulta tardía del PID ni se matan procesos ajenos. Importación y exportación
tienen límites de 240/300 s; cada recorrido tiene 180 s y conserva los watchdogs
internos originales del driver (60/120 s).

En Windows se mantiene una solicitud de disponibilidad **System + Execution**
ligada a un handle, liberada ante éxito/error antes de entregar el candidato.
No solicita display para estas pruebas headless ni modifica `powercfg`.
Linux/macOS no cargan ninguna API de Windows.

## Recorridos obligatorios, iguales en los tres sistemas

| Recorrido | Fuente | ZIP extraído |
|---|---:|---:|
| `--smoke-test` | 201 checks | 218 checks |
| `--gameplay-smoke` | 1080 checks | 1097 checks |

Son identidades **literales del productor revisado**, no umbrales que permitan
recortar checks. El oráculo `tools\release\smoke-contract.json` conserva sus
nombres, orden, campos principales, formas de casos y hashes normalizados de
los drivers/main. El build no lo regenera. Cambiar un productor requiere
actualizar el contrato con evidencia y revisión; no bajar el contador para pasar.
El binding 0.5 apunta al driver legacy actualizado y al host R3 real
`game\match\match.gd`; conserva el driver gameplay y las cuatro listas de checks
de 0.4 sin modificarlas. Este cotejo estático no acredita nuevas ejecuciones.

Ambos recorridos conservan micro **1v1 + porteros** y preview **5v5**. Gameplay
exige **28 casos y 20 observaciones**, catálogo completo, input teclado/mando/
mouse real, snapshots/roles/foco, manifiesto concordante y **cero PNG headless**.
Un subset autoconsistente no es un recorrido completo. Se rechazan JSON con
claves duplicadas, números no finitos, tipos coercionados, checks duplicados,
stdout/archivo distintos, errores, warnings o identidad ajena. No hay una lista
de allowances distinta por OS.

Las comparaciones entre JSON de stdout, archivo, manifiesto y prueba archivada
son recursivas y conservan los tipos: `true` no equivale a `1`, ni `false` a `0`.
Las guardas semánticas compartidas exigen modos/contadores enteros y flags
booleanos. Una sola política de diagnósticos sirve al lector vivo y al auditor,
incluido `Parse Error`; permitir el texto informativo de `codesign` en stderr
no permite errores ni warnings.

El protocolo usa **`--fixed-fps 60` sólo para reproducción diagnóstica**.
No es una medición de rendimiento. Abrir el juego normalmente no usa smoke,
diagnóstico ni fixed-fps. El nuevo release sólo recibe validación headless en
este pipeline: no hereda pruebas gráficas de los EXE debug anteriores.

## Paquetes, metadata y firma

Los nombres son:

- `futsal-v0.5.0-preview-windows-x86_64.zip`
- `futsal-v0.5.0-preview-linux-x86_64.zip`
- `futsal-v0.5.0-preview-macos-universal.zip`

Cada candidato lleva un `.sha256`, un `.build.json` y `proof\<plataforma>`.
La metadata conserva commit o su ausencia explícita, motor, template, plataforma,
snapshot de fuente, contenido/hash del ZIP, cuatro recorridos y limitaciones.
La información interna de este pipeline es `BUILD.json`; debe coincidir con
el `.build.json` externo. En Linux ambos declaran **`buildType=debug`**, el
miembro de plantilla, su SHA-256 y el workaround upstream. El auditor exige
`--export-debug` en la prueba `export-debug`, rechaza flags mezclados y verifica
el mismo preset. Windows/macOS conservan `buildType=release` y `export-release`.
La variante canónica siempre define `buildType`, `templateEntry`,
`templateSha256` y `engineWorkaround`. En release los tres campos de procedencia
son `null`: se admite también su ausencia histórica, independientemente en
`BUILD.json` y `.build.json`, pero **ningún valor no-null sin acreditación**.
Se rechazan incluso rutas o hashes plausibles, el miembro/pin debug de Linux,
booleanos, números, cadenas vacías y contenedores. `buildType` sigue siendo
obligatorio y exacto. Debug exige siempre los cuatro valores exactos fijados.
El productor y los dos lectores consumen esa misma variante; CLI e índice
proyectan sólo después de validarla. `sha256` continúa siendo el hash del ZIP,
nunca el de la plantilla.
El `BUILD_INFO.json` del paquete R3 local separado no se modifica.
Desde 0.5, `BUILD.json` y `.build.json` también deben concordar en
`thirdPartyNotices` y `sourceDocumentsSha256`; el auditor valida ambos antes
de proyectarlos en CLI e índice. Su contrato de contenido se detalla abajo.
Los logs, JSON y manifiestos nativos permanecen junto a sus hashes, no sólo un
`passed=true`. Las rutas dentro de los reportes son las de la invocación original:
auditarlas después **no reconstruye un proceso vivo ni demuestra una nueva ejecución**.

El ZIP usa nombres/orden deterministas, fecha fija y modos Unix explícitos.
Se verifica ida/vuelta con bytes y metadata. Conserva el PCK separado de Linux,
el PCK/bundle macOS, exec bits y symlinks internos. Rechaza escapes, symlinks
absolutos/cíclicos/colgantes, duplicados y archivos especiales.
Esto hace reproducible el **empaquetado del mismo payload**; no promete que Godot
produzca binarios idénticos entre máquinas/compiladores o ejecuciones distintas.

Windows no tiene certificado Authenticode. macOS usa el **firmador ad-hoc
integrado de Godot**, con notarización desactivada. Se verifican las slices
Mach-O reales **arm64 + x86_64**, dependencias universales, `lipo` y
`codesign --verify --deep --strict`, también después de extraer el ZIP.
No hay Apple Developer ID, firma de distribución Apple ni notarización.
El runner `macos-15` es ARM64: el runtime se prueba nativamente en ARM64;
la inclusión/estructura de x86_64 se verifica, **no se afirma haber ejecutado
esa slice en un Mac Intel**.

Gatekeeper puede bloquear una descarga ad-hoc. La documentación del paquete
remite al procedimiento oficial de Apple para autorizar **una app concreta y
confiable**; no se ofrecen comandos para desactivar Gatekeeper globalmente.

## Licencias

El paquete incluye **`GODOT_LICENSE.txt` y `GODOT_COPYRIGHT.txt`** oficiales,
con todos sus avisos; no se sustituye el texto por una etiqueta “MIT”.
Esto cubre los avisos del motor y sus terceros, **no asigna licencia al juego**.
Desde `0.5.0-preview` es obligatorio incluir también
**`THIRD_PARTY_NOTICES.md` completo**, copiado byte por byte desde la raíz
fuente. Incluye la procedencia de Human Base Meshes de Dan Ulrich/CC0.
No se sustituye por un resumen ni por los avisos del motor. Se exige un archivo
regular, UTF-8, no vacío y de como máximo 1 MiB. No se añaden capturas privadas,
referencias FIFA, inventarios, historiales o fuentes `.blend` al payload.

El descriptor `thirdPartyNotices` fija `source` y `packaged` al nombre raíz,
`bytes` entero estricto, `sha256` de los bytes empaquetados y
`normalizedSha256` del texto UTF-8 con CRLF normalizado a LF.
`proof\<plataforma>\source-documents.json` contiene exactamente
`{"THIRD_PARTY_NOTICES.md": "<hash normalizado>"}`; su digest canónico es
`sourceDocumentsSha256`. El snapshot de juego sigue separado, sin cambiar
su formato. Los hashes brutos pueden diferir por EOL entre checkouts nativos:
la copia sigue siendo íntegra y el contenido normalizado debe corresponder
al blob del commit consumido, o a la fuente local para un candidato sin commit.
Tres snapshots de avisos iguales entre sí pero ajenos a la fuente se rechazan.
Los paquetes históricos anteriores a 0.5 conservan ausencia/null de estos
campos; no pueden inventar nueva procedencia no-null.

Si coordinación añade una licencia raíz (`LICENSE`, `LICENSE.txt` o
`LICENSE.md`), se copia como `GAME_LICENSE.txt` y se registra su hash.
Si no existe, `licensePolicy=not-defined` lo declara explícitamente; no se
inventa una licencia propietaria, MIT ni otra para el código/assets propios.
La decisión de licencia y autorización de publicación corresponde a coordinación.

## Comandos locales

Desde la raíz del repo, en Windows:

```powershell
python -m unittest discover -s .\tools\release\tests -v

# Candidato local: permite checkout todavía no cerrado, sin inventar commit.
python -m tools.release build --platform windows-x86_64 --tag v0.5.0-preview `
  --cache .\tools\godot\.cache --output .\build\release\local-graphics05-candidate `
  --allow-uncommitted

# Auditoría pasiva del ZIP y de sus evidencias; no ejecuta Godot.
python -m tools.release audit --archive `
  .\build\release\local-graphics05-candidate\dist\windows-x86_64\futsal-v0.5.0-preview-windows-x86_64.zip
```

En un host Linux o macOS, el mismo módulo acepta respectivamente
`--platform linux-x86_64` o `--platform macos-universal`, con Python 3.11+ nativo.
La selección debe corresponder al host: no se presenta una exportación cruzada
desde Windows como prueba de macOS/Linux.

`--allow-uncommitted` deja `commit=null` y `publishableCandidate=false`.
No puede usarse en GitHub Actions ni pasar la verificación conjunta de un release.
Sin ese flag, `--commit <SHA>` debe corresponder al checkout limpio.
Para repetir una ejecución local se elige **otro subdirectorio** de
`build\release`; el script no borra ni reemplaza candidatos anteriores.

### Desde el clon público

Los comandos de release y sus unidades **no necesitan `.squad`, `.copilot`,
`.mcp.json`, agentes privados, `local.json` ni informes en `runtime`**.
Tampoco requieren el bootstrap local de Blender/MCP/Godot. El oráculo literal
está incluido en `tools\release\smoke-contract.json`; la referencia histórica
que contiene no se abre como archivo. `tools\godot\release.json` sí es fuente
pública: permite cotejar los pins históricos, no describe una instalación local.

Una vez publicado el commit que incluye este tooling, desde un checkout limpio
se puede ejecutar:

```powershell
python -m unittest discover -s .\tools\release\tests -v
python -m tools.release build --platform windows-x86_64 --tag v0.5.0-preview
```

Se acredita el `HEAD` real y se crea `build\release\cache` si hace falta.
Sin `--cache`, los archivos oficiales ausentes se descargan desde los URLs
fijados; con ese argumento se reutilizan sólo archivos cuyos bytes coincidan
con el manifest. No hay que generar un `local.json` ni copiar inventarios,
EXE debug o resultados antiguos. El mantenedor puede usar `freeze_contract`
con nueva evidencia revisada para cambiar el oráculo; **no es un paso de
instalación, build ni CI**.

## GitHub Actions e integración

`.github\workflows\release.yml` se activa **sólo por `workflow_dispatch`**, con
input obligatorio `version` (default `v0.5.0-preview`), en el repositorio público
`jmanuelcorral/futsal`. No tiene trigger `push`, tampoco para tags: la publicación
posterior de la etiqueta no vuelve a construir los paquetes.
No se han activado ni modificado los workflows históricos de Squad.

Coordinación puede lanzar el primer CI en `main` después de integrar el código
revisado; **no necesita crear un tag antes**. El input se transmite mediante
una variable de entorno a `--tag` en build y verificador, nunca se inserta como
código ejecutable. Ambos exigen el SHA de la invocación y la misma versión;
un input distinto de `project.godot` se rechaza antes de importar/exportar.
Un build con deltas locales sigue necesitando `--allow-uncommitted` y no atribuye
esas modificaciones al baseline público.

Comando de coordinación, una vez publicado el workflow revisado:

```powershell
gh workflow run release.yml --repo jmanuelcorral/futsal --ref main -f version=v0.5.0-preview
```

La matriz usa runners **estándar públicos** `windows-2025`, `ubuntu-24.04` y
`macos-15`, máximo **tres builds simultáneos**, timeout 30 minutos y sin runners
pagados. Después hay un job de auditoría, nunca concurrente con los builds:
descarga y exige exactamente los tres ZIP/version/commit/fuente, comprueba
checksums y pruebas originales, y produce `release-index.json` y `SHA256SUMS`.
No publica releases. Los artefactos exitosos se retienen siete días;
las pruebas de fallo, tres.

Checkout/upload/download de GitHub están fijados a commits completos en el
manifest y workflow. Todos los jobs tienen `contents: read`;
checkout usa `persist-credentials: false` y **`lfs: true` tanto en build como
en verify**, para cotejar los assets reales con sus pointers SHA/tamaño.
No hay credenciales Apple,
PAT de publicación, secrets propios ni permisos de escritura.
Coordinación consume los tres artefactos y el índice del **mismo run**, comprueba
QA y ejecuta su publicación final con `gh` fuera de este workflow, creando el tag
y release sobre el **SHA exacto que pasó**, no sobre un `main` que haya avanzado.
El workflow no crea ni mueve etiquetas.

Para auditar conjuntamente una descarga existente:

```powershell
python -m tools.release verify --directory .\build\release\downloaded `
  --commit <SHA-del-run> --tag v0.5.0-preview `
  --index .\build\release\verified\release-index.json
```

Los candidatos que declaran commit necesitan el checkout limpio de ese SHA
para acreditar su procedencia. Cada snapshot archivado se compara con la fuente
esperada de ese commit; no basta que los tres paquetes coincidan entre sí.
Los candidatos locales con `commit=null` conservan auditoría pasiva, pero nunca
acreditan un commit ni pasan como conjunto publicable.

## Evidencia y límites de esta entrega

### Preparación gráfica 0.5, separada de la publicación 0.4

Evidencia de preparación en `build\publication\graphics05-preparation`.
La suite portable ejecutó **111/111 pruebas** sobre versiones, avisos,
metadata/auditoría, proceso/EOF, snapshots y guards LFS existentes.
Las fixtures Git son locales y sintéticas; no son pruebas de ejecución nativa.
El contrato conserva exactamente **201/218/1080/1097** checks. No se ha
reexportado, promovido ni publicado ningún ejecutable en esta preparación.
Los helpers PowerShell pasaron **489/489**, **248/248** y **298/298** checks,
con sintaxis de diez scripts y actionlint 1.7.12 sin diagnósticos. Son fixtures
sintéticas, incluidas sus imágenes y procesos PowerShell propios, no Godot.
Se conserva el intento runtime cortado por el límite externo inicial de 240 s;
el recorrido completo con trazas terminó en 268,968 s con un presupuesto externo
de 600 s. No se modificaron los watchdogs, plazos ni oráculos nativos.
El handoff registra también la corrección de una etiqueta de fixture duplicada
y el cotejo final, sin convertir estos checks en aceptación de la preview.

Pendientes para coordinación: higiene final de fuentes por Lambert, snapshot
exacto revisado por Vasquez, validación nativa de los tres destinos y publicación
de una nueva prerelease sólo después de ese cierre. La aprobación técnica local
del EXE R3 histórico no se convierte en aprobación artística, humana o de FPS,
ni acredita otros binarios construidos posteriormente.

Las secciones siguientes conservan las evidencias y rechazos **históricos 0.4**.

### Corrección R3 de tooling: contrato de procedencia release

La fuente aislada está en
`build\release\platform-modes-ci34990490983-r3\source`, extraída del ZIP
inmutable R2 y corregida sólo en tooling/tests/documentación. Conserva los
nueve deltas sobre 5de; el juego no cambia respecto de R2. **Esta R3 no es
una ronda artística ni otro export de la preview de atletas.**

Se reprodujeron **12 éxitos incorrectos** con el contrato R2: seis en CLI
audit y seis en CLI verify/índice, sobre fixtures Windows/macOS con metadata
externa alterada. Incluían `{templateEntry:true, templateSha256:7}`, miembro/pin
Linux debug y `engineWorkaround` plausible. La corrección no filtra la salida:
la variante release declara los tres `null` y el mismo validador tipado exige
esos valores o ausencia tanto fuera como dentro del ZIP. El resto de
`BUILD.json` conserva su coincidencia exacta; no se admiten otros campos extra.

Se ejecutó desde la copia aislada
`python -m unittest tools.release.tests.test_release tools.release.tests.test_audit tools.release.tests.test_cli -v`:
**69/69**, con seis métodos nuevos. Incluye **20** combinaciones release
ausencia/null, **204** mutaciones release en metadata externa, interna o ambas
coherentemente alteradas, **51** mutaciones debug y **cuatro** omisiones de
campos debug obligatorios. Las regresiones nuevas no sustituyen el auditor
ni el verificador por mocks: CLI audit rechaza **24** casos y CLI verify
rechaza **16** sin escribir índice ni `SHA256SUMS`; cuatro controles CLI
release y el conjunto de tres plataformas admiten ausencia/null.

La auditoría pasiva R3 también acepta el Windows nativo histórico `4af542…`,
con las tres salidas de procedencia `null`; ZIP y metadata permanecen intactos.
No se repitieron Godot, WSL, exports o smokes. La auditoría Linux real con R2
comunicada por coordinación sigue siendo evidencia heredada aprobada, no una
ejecución nueva de Ferro. No se modifican permisos NTFS ni oráculos.
La fuente sigue siendo local, `sourceCommit=null`, no publicable; queda la
relectura acotada de Vasquez y después la integración/CI por coordinación.

### Histórico R2: proyecciones corregidas, contrato release rechazado

R2 añadió `templateEntry` y `templateSha256` a CLI e índice y resolvió la
omisión Linux. No cerraba todavía el contrato de esos campos en release:
aceptaba procedencia externa no acreditada. Por ello su ZIP `2311d111…`
y parche `d0bce2e…` se conservan como **NO_GO_PRE_CI por ese P2**, sin
invalidar su auditoría Linux real ni reabrir el resto de las correcciones.

La copia histórica está en
`build\release\platform-modes-ci34990490983-r2\source`: conserva los mismos
nueve deltas sobre `5de1baea195b8d10ba7845938b0a90f59a6d3071`, sin incorporar
el juego vivo ni cambiar flags, productores, contadores o permisos.
Se reprodujeron las dos omisiones con las regresiones reforzadas antes de
corregir las salidas. Después se ejecutó desde esa copia
`python -m unittest tools.release.tests.test_cli tools.release.tests.test_audit -v`:
**26/26**. Cubren los valores exactos de miembro/hash en CLI Linux e índice
de tres fixtures, su separación del hash del ZIP y la compatibilidad con
metadata release sin esos campos. No son nuevas ejecuciones nativas.

El freeze anterior `b3ed5e6…` y su parche `364a52a…` se conservan como
**entrega de tooling rechazada por esa omisión P2**, no como GO vigente.
Sus 94/94 unidades son evidencia histórica, no una repetición de toda la
suite en R2. El recurso Linux aprobado que se produjo con aquella fuente
se conserva por separado de este rechazo de las salidas JSON.
Aquella copia sigue siendo local, `sourceCommit=null`, no publicable.

### Integración Mac + workaround Linux tras el MRP

Coordinación ejecutó `build\publication\popup-export-repro\comparison.json`
en Ubuntu WSL real, con el mismo proyecto mínimo y cinco ciclos de
`OptionButton`. El template release dejó conexiones `focus_entered` y
`tree_exited` tras cerrar y terminó con salida 1; debug las limpió y terminó
con salida 0. Ambos informes identifican Godot 4.7.2 oficial y ambos EOF.
Esta evidencia es **heredada y leída pasivamente**: Ferro no repitió el MRP
ni el pipeline Linux.

La fuente histórica de integración está en
`build\release\platform-modes-ci34990490983-fix\source`, basada en 5de más
las correcciones Mac y los deltas de tooling Linux. **94/94 unidades** pasaron
desde esa copia: las 77 previas, ocho de macOS y nueve nuevas de modo Linux.
Cubren miembro/pin/flag/slot de plantilla, prohibición de debug fuera de la
preview Linux, README explícito y rechazos del auditor ante metadata o
`BUILD.json` discordantes y flags release/debug mezclados.

Se verificaron los dos miembros Linux del TPZ fijado y se extrajo/configuró
el debug real: **73.703.800 bytes**, SHA-256 `1a291d3…`.
El miembro release conserva **73.519.416 bytes**, SHA-256
`d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63`.
Se cotejaron `custom_template/debug`, `--export-debug` y los campos que recibirá
el paquete **sin ejecutar ese comando**. Se preserva el PCK separado del
preset Linux; no se confunde con `embed_subwindows`.

El auditor de aquella entrega también aceptó el Windows release histórico `4af542…`,
sin modificarlo ni volver a ejecutarlo. Los JSON de aquel directorio registran
las unidades, la comprobación offline y esa auditoría pasiva.

Posteriormente, coordinación ejecutó el pipeline completo en Ubuntu WSL
sobre la fuente `b3ed5e6…`: source **201/201 y 1080/1080**, export con
`--export-debug`, paquete **218/218 y 1097/1097**, salida 0, ambos EOF y
stderr vacío. Vasquez dio **ARTIFACT_APPROVE técnico local** al ZIP de
**27.884.424 bytes**, SHA-256
`b9fd9564743f811514a412567a3add0786660ea12270b478b82d0ef00a54c8bb`,
en `source\build\release\linux-native\dist\linux-x86_64` de aquella entrega.
El ELF coincide byte a byte con la plantilla debug oficial `1a291d3…`.
Su auditoría completa pasó en WSL; Ferro cotejó pasivamente ZIP, ELF y
metadata, sin repetir Godot.

La auditoría desde Windows difiere únicamente en los modos de los archivos
de evidencia sobre NTFS: WSL registra `0755`, Windows observa `0644`.
**No se corrigen, normalizan ni falsean esos permisos** para dar verde.
No es un fallo de streams, rutas o hashes; la CI sobre ext4 será independiente.
El paquete conserva `commit=null` y no es publicable. Esta aprobación técnica
local no acredita CI, optimización, FPS, calidad artística ni aceptación humana.
R3, af23, productores, listas, contadores y presets permanecen intactos.

### Corrección macOS del CI 34990490983

El export macOS de `5de1baea195b8d10ba7845938b0a90f59a6d3071` terminó con
salida 1 y ambos EOF completos. Sus diagnósticos señalan la ausencia de
`macos.zip` en el perfil privado y la importación ETC2/ASTC desactivada.
El preset ya contenía `texture_format/etc2_astc=true`; esa opción no sustituye
la configuración del importador. La fuente oficial fijada confirma que
`has_valid_export_configuration` comprueba primero el ZIP estándar y exige
ETC2/ASTC para Universal2 o arm64.

La corrección instala la plantilla en esa ubicación del perfil y añade
**una única línea ASTC** a `game\project.godot`. La comprobación byte a byte
confirma que el archivo vivo no recibió otros cambios. Para publicar sobre
5de se usa el parche de esa línea, **no el archivo vivo completo**, que también
contiene TAA y sombras de la iteración artística posterior.

La copia `build\release\macos-ci34990490983-fix\source` parte sólo de 5de más
los deltas macOS autorizados; no modifica la fixture Git de comparación ni
hereda su procedencia. Se ejecutó
`python -m unittest tools.release.tests.test_release -v`: **32/32**, con
**ocho regresiones nuevas** de ubicación estándar/versionada, HOME privado,
ausencia de fallback al HOME real, rechazo de sobrescritura, ASTC obligatorio
y conservación de Forward+/Universal2/ad-hoc. Los recorridos de extracción
no macOS conservan ubicación y bytes.

También se extrajo el miembro real del TPZ oficial, verificado por su pin
SHA-512, y se cotejaron sus bytes y las cabeceras de ambas plantillas:
debug y release contienen **arm64 + x86_64**.
`macos.zip`: **123.597.580 bytes**, SHA-256
`88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792`.
La configuración privada consumió ese archivo con ASTC habilitado y el
perfil temporal quedó eliminado.

Estas pruebas se ejecutaron **desde Windows**, sin arrancar Godot ni exportar
R3. No son una exportación ni una ejecución macOS nativa: ambas requieren
la próxima CI. `unit-result.json`, `official-template-check.json` y el handoff
con parches para 5de están en esa carpeta de evidencia.
El diagnóstico Linux y su MRP corresponden a coordinación. La ampliación
posterior de tooling descrita arriba integra exclusivamente el workaround
debug autorizado; no modifica ni repite sus pruebas nativas.

### Primer CI nativo: run 34965436939

El run de `d5b8b956a976796fb75128d93cbdd1141df9f301` arrancó correctamente
la matriz con los shells literales de d5. **No produjo paquetes publicables**;
el colector quedó omitido.

| Job | Fallo observado | Estado |
|---|---|---|
| Windows `104368667126` | 75/76 unidades; el test de contención comparaba `RUNNER~1` con la ruta larga devuelta por `resolve()` | Corregida la expectativa canónica, conservando los rechazos de raíz y escape |
| macOS `104368667259` | 75/76 unidades; el mismo test comparaba `/var` con `/private/var` | Misma corrección portable, sin saltos por OS |
| Linux `104368667268` | Unidades completas; fuente 201/1080 y paquete legacy 218; gameplay empaquetado 193/196, detenido en G31 antes de los 28 casos | Causa en G31, no en el lector Python; corrección y validación local descritas abajo |

En `game\diagnostics\gameplay_smoke.gd`, G31 utilizaba
`ProjectSettings.globalize_path("res://")`. Godot documenta que esa operación
no proporciona una raíz física válida en proyectos exportados. Con raíz vacía,
la condición rechaza cualquier padre absoluto POSIX porque empieza por `/`.
Una fixture nativa mínima con el motor/template Windows fijado confirmó la raíz
vacía en export y la raíz válida en editor. `--path` tampoco lo corrige: el
template oficial está compilado sin soporte para overrides de ruta.

Coordinación corrigió la selección de raíz física: se conserva la del editor;
cuando está vacía se usa el directorio del ejecutable y, en macOS, se protege
todo el bundle `.app`. La contención exige rutas absolutas no virtuales,
normaliza separadores y `..`, y conserva el límite de componente y la
comparación conservadora sin distinguir mayúsculas. Los cuatro checks G31
y los contadores **201/218/1080/1097** no cambian. No se sustituye el paquete
por ejecución desde editor, rutas ficticias o un subset de casos.

La corrección de tests pasa **77/77 unidades locales Windows** desde la copia
aislada de d5, con los 76 anteriores y una regresión adicional de alias/escape.
La evidencia descargada y los probes están en
`build\release\ci-34965436939`; no se importó ni modificó el juego vivo.
Esta comprobación local no acredita una repetición nativa de macOS/Linux.

### Primera integración G31: histórica y rechazada

**Vasquez rechazó este intento** por identificar el bundle y vetar rutas virtuales
antes de normalizar separadores, `..` y mayúsculas. Sus 20 casos de rutas no
cubrían esas variantes. El freeze SHA-256
`c84e8fae374160ead06ada4fe41ebe416712e685660e0944426cf0830c9b9672`
y el ZIP Windows `34e235…` se conservan **como históricos rechazados, no como GO**.
Las cifras siguientes documentan lo ejecutado entonces, no una aceptación.

`build\release\g31-04-validation\source` parte del archivo de d5, cotejado con
los blobs Git y la normalización CRLF/LF declarada. Incorpora **sólo cinco
deltas**: los dos archivos de coordinación
`game\diagnostics\gameplay_smoke.gd` y `game\tests\test_match_integration.gd`,
la corrección de `tools\release\tests\test_release.py`, el binding de
`tools\release\smoke-contract.json` y esta documentación.
No consume los cambios artísticos del juego vivo ni sus nuevos assets,
`project.godot` o `match.gd`. La copia final está en `frozen-source` y en
`futsal-0.4.0-preview-g31-source.zip`, junto a la evidencia.

En ese intento se actualizó **únicamente el hash del productor gameplay** a
`ce8fbc9877dfc4e7dae1b44783156141f6990c0598c63273947f287a2d1596ca`.
Los demás productores, las listas literales y los formatos permanecen iguales.
La prueba de integración existente añade los **20 casos puros** de selección
y contención de coordinación; no hay nuevo runner ni cambio en `Test-MicroSlice`.

| Ejecución Windows histórica, insuficiente para aceptación | Resultado |
|---|---:|
| Unidades portables, incluidos los 76 tests de d5 | 77/77 |
| `test_match_integration.gd`, incluidas las 20 pruebas de rutas | 224/224 |
| Smokes fuente legacy + gameplay | 201/201 + 1080/1080 |
| Smokes desde el ZIP extraído legacy + gameplay | 218/218 + 1097/1097 |
| Guardas iniciales G31 en fuente y ZIP extraído | 4/4 en cada uno |

La integración registra `integration_errors=[]` y `command_refusals=[]`;
sus eventos nativos son **614 key, 168 joy_button y 222 joy_motion**.
Los procesos terminaron con salida 0 y ambos EOF, sin errores ni warnings.
Cada recorrido gameplay completa **28 casos y 20 observaciones, con cero PNG**.
La auditoría pasiva del nuevo ZIP coteja sus **28 archivos de prueba**.
Las solicitudes Windows System + Execution quedaron liberadas.

La comprobación de callers conservó **13 invocaciones: cinco de esa ejecución**
(cuatro smokes Windows y una integración) y **ocho históricas**
(cuatro del Windows anterior y cuatro del Linux fallido), no 13 ejecuciones nuevas.
Sus reportes están fuera de las raíces protegidas; el fallo histórico de Linux
no se convierte en éxito. Se inspeccionaron también los layouts de
`Invoke-Game`, `Get-GodotGameplayEvidencePaths` y el build macOS: las pruebas
usan directorios separados del proyecto/binario, nunca internos al bundle. El layout macOS
y sus casos puros no equivalen a una ejecución nativa en ese sistema.
No se detectó ningún caller que requiriera relajar G31.

El candidato está en
`build\release\g31-04-validation\source\build\release\local-g31\dist\windows-x86_64`.

| Archivo | Bytes | SHA-256 |
|---|---:|---|
| `futsal-v0.4.0-preview-windows-x86_64.zip` | 39.608.715 | `34e23587c87b39a9519d2e780a61191ce6e34276f6beda0737600fccfada61e7` |
| `Futsal.exe` dentro del ZIP | 109.656.184 | `4159ae511084449e6766d7d05a512a7dc7dfb1045f54d02b6310708d1d4ce254` |

Es **local y no publicable**: `commit=null`, `publishableCandidate=false`.
No se hicieron commits, push, dispatch ni promoción de la activa. Se conservan
el ZIP anterior `9c412…`, los cinco EXE históricos/activa y el manifest anterior.
`unit-result.json`, `integration-result.json`, `audit-result.json`,
`caller-validation.json`, `freeze.json` y los logs de `proof` registran esta
ejecución. La revisión independiente de Vasquez la rechazó; sus resultados no
se reutilizan para aprobar el candidato corregido siguiente.
No se declara aceptación artística, humana, de FPS ni firma Windows.

### Segunda integración G31: normalizar antes de decidir

Coordinación corrigió únicamente los mismos dos GDScript. Ahora
`runtime_output_root` normaliza separadores y `..` **antes** de identificar
`Contents/MacOS`, comparando esos componentes sin distinguir mayúsculas.
`output_is_outside_runtime` normaliza y pasa a minúsculas **antes** de exigir
ruta absoluta y vetar `res:`/`user:`; mantiene la protección de `/` y el límite
de componente. Ferro incorpora esos archivos sin modificar su semántica.

El test de integración conserva los 20 casos originales y añade **14
regresiones: 34 casos de rutas, 13 de selección y 21 de contención**.
Cubren `MacOS/../MacOS`, `./`, `CONTENTS/MACOS`, barras Windows y esquemas
virtuales con barras o mayúsculas tanto en el padre como en la raíz.
No hay nuevo runner ni cambios en `Test-MicroSlice`.

La fuente nueva está en `build\release\g31-r2-04-validation\source`, de nuevo
**d5 más cinco deltas exactos**, sin consumir otros archivos del juego vivo
ni arte. El único cambio del oráculo es el hash normalizado del productor
gameplay:
`2e9803f14c7d3dff5fede94ce32586c03f37f6b66c8b305032005f1e51592d9c`.
Se conservan las listas, formatos y contadores **201/218/1080/1097**.

| Nueva ejecución Windows aislada | Resultado |
|---|---:|
| Unidades portables | 77/77 |
| Integración existente, con los 34 casos de rutas | 238/238 |
| Smokes fuente legacy + gameplay | 201/201 + 1080/1080 |
| Smokes del ZIP extraído legacy + gameplay | 218/218 + 1097/1097 |
| Guardas iniciales G31 en fuente y paquete | 4/4 en cada uno |

La integración registra `integration_errors=[]`, `command_refusals=[]` y
**614 key, 168 joy_button, 222 joy_motion**. Todos estos recorridos terminaron
con salida 0, ambos EOF y sin diagnósticos. Gameplay conserva **28 casos,
20 observaciones y cero PNG headless**. El auditor comprueba los **28 archivos
de evidencia** del paquete. Las solicitudes Windows quedaron liberadas.

La revisión de callers separa expresamente **cinco recorridos actuales**
(los cuatro smokes y la integración) de **ocho históricos** (Windows `9c412…`
y el CI Linux fallido), más **tres layouts estáticos**. No son 13 ejecuciones
nuevas. No se detectan reportes internos al proyecto/binario ni al layout del
bundle. Los casos puros y ese layout no acreditan runtime macOS/Linux.

El nuevo ZIP está en
`build\release\g31-r2-04-validation\source\build\release\windows-r2\dist\windows-x86_64`.

| Archivo | Bytes | SHA-256 |
|---|---:|---|
| `futsal-v0.4.0-preview-windows-x86_64.zip` | 39.608.620 | `4af54241b5db84c87724ccceda3799bd94ba35e098b394adccd66a3710ab96c5` |
| `Futsal.exe` dentro del ZIP | 109.656.152 | `a28ea02d1161e99f574945c2cefa470bf2269be91b51846fa2ef5d055485ce22` |

La copia final queda en `frozen-source` y
`futsal-0.4.0-preview-g31-r2-source.zip`, dentro de la nueva carpeta de evidencia.
`freeze.json` y `handoff.json` conservan los hashes raw/LF/blobs, comandos y
resultados; `caller-validation.json` separa la procedencia de cada caller.
Se preservan los doce históricos comprobados, incluidos c84/ZIP34e235
rechazados, ZIP9c412, af23 y los freezes anteriores.

Este segundo candidato sigue **local y no publicable**: `commit=null`,
`publishableCandidate=false`. No se tocó el índice ni se hicieron commits,
push, dispatch o promoción del ejecutable. Quedan pendientes la nueva revisión
de Vasquez y la CI nativa de los tres sistemas sobre el commit que cierre
coordinación. No se concede aceptación artística, humana, de FPS ni de firma.

### Corrección pre-CI de procedencia, tipos y diagnósticos

Tras reproducir los tres hallazgos de Vasquez, la fuente corregida quedó aislada
en `build\release\frozen-04-12fb5d6-corrected\source`, derivada exclusivamente del
freeze original y de los deltas permitidos de tooling/documentación.
**75/75 unidades** pasan desde esa copia, incluidas las **51 originales**.
Las nuevas pruebas usan repositorios Git temporales con identidad/configuración
por invocación, nunca commits en el repositorio del juego.

Se rechazaron el falso commit ascendente, la suciedad ignorada/oculta y tres
snapshots iguales pero ajenos al checkout. Las cuatro variantes mantienen sus
identidades **201/218/1080/1097**. Se cubren los cambios de tipo `mode:true`,
`ok:1`, `frames_drawn:false`, `headless:1` y `requested_mode` booleano, tanto
asimétricos como concordantes entre stdout y archivo, además del manifiesto.
`Parse Error` se rechaza en stdout y stderr aun actualizando contadores y hashes.

El auditor corregido aceptó el **ZIP Windows existente 9c412… sin modificarlo**.
Sobre una copia de sus pruebas reales rechazó **20 mutaciones** con hashes
actualizados: 14 de stdout, cuatro de `requested_mode` y dos de `Parse Error`.
`validation.json`, `native-proof-mutations.json` y los logs de `proof` están junto
al nuevo snapshot. No se ejecutó Godot ni se reexportó gameplay en esta corrección;
los límites, formatos de producto y oráculos permanecen iguales.
El freeze original, su ZIP y la activa af23 se conservan.

### Exportación Windows anterior, conservada y re-auditada

Se ejecutaron los tres comandos locales anteriores: **51/51 pruebas unitarias**,
build release Windows y auditoría pasiva del paquete final. Las unidades incluyen
procesos reales/EOF acotado, power request Windows, mutaciones de ambos protocolos,
ZIP/permisos/symlinks y colección sintética de exactamente tres plataformas.
Ocho unidades nuevas cubren dispatch desde `main` sin tag, versión/SHA vinculados,
rechazo de eventos automáticos y ejecución de los bloques Python reales del
workflow para comprobar que transmiten el input a build y verificador.

El candidato final está en `build\release\local-dispatch-final\dist\windows-x86_64`.
Fuente: **201/201 + 1080/1080**. ZIP extraído: **218/218 + 1097/1097**.
Los cuatro recorridos terminaron con salida 0, ambos EOF, sin diagnósticos,
28 casos/20 observaciones gameplay y cero PNG. La auditoría cotejó el archivo,
los bytes del ejecutable extraído y los **28 archivos de evidencia**.
Su resultado está en `build\release\local-dispatch-final\audit-result.json`.
La solicitud System + Execution quedó liberada.

| Archivo | Bytes | SHA-256 |
|---|---:|---|
| `futsal-v0.4.0-preview-windows-x86_64.zip` | 39.607.805 | `9c412c2bc98236a47576ba132d0a82653cb9f64686db9c21d56ff3ecc0d86336` |
| `Futsal.exe` dentro del ZIP | 109.655.464 | `627a117bdb6b59c1daa0abe153a4f8a24f1d0a17ab435227245fcfaf840e01d4` |

Este build usó editor/TPZ de la caché verificada, sin instalación global.
Es **local, no publicado**: `commit=null`, `publishableCandidate=false`,
`licensePolicy=not-defined`, `technicalReviewPending=true` en la auditoría.
No se debe etiquetar como artefacto de un commit/CI que todavía no lo construyó.
La ejecución cotejó `--commit 12fb5d695026900c4ae952b0a48bd4166e07c4c3`
como baseline, pero usó `--allow-uncommitted`: los deltas de release pendientes
de QA **no quedan atribuidos a ese commit público**.
Se cotejaron de nuevo las cinco huellas G1/0.2/0.3/0.4/activa y el antiguo
`tools\godot\release.json`: todos intactos; activa y copia 0.4 siguen en
`af23eb5c41453a108ad1f53d63a5590575b607b59a1d49a1f60ff6b079ce2a0f`.

El candidato anterior `local-final` (43 unidades, ZIP SHA-256
`fd01c2fa60fe08652781c56203a5a0f0234863547c07b6b40ec826d166ebe110`),
la primera exportación completa `local-v3` y los dos intentos previos permanecen
preservados. Aquellos intentos se detuvieron en el **lector Python**, no en el
juego: se corrigieron la fase serializada como string y la diferencia entre
envelopes de observación y cierre, incorporadas a sus negativas.
No se cambió GDScript, ni se rebajaron checks, ni se aceptaron errores del motor.

También se comprobó una **copia aislada de los 188 archivos publicables**, sin
memorias, configuración local, cachés, informes ni EXE anteriores, y con la
búsqueda del Git padre bloqueada. Se verificó que los imports procedían de esa
copia: **43/43 unidades**, build release y auditoría completos; fuente
**201/1080** y ZIP extraído **218/1097**, con ambos EOF y disponibilidad liberada.
Se proporcionó únicamente la caché oficial verificada mediante `--cache`,
sin nueva instalación ni dependencia de sus inventarios vecinos.
No hizo falta modificar los scripts.

Evidencia local:
`build\release\standalone-public-3317ef9b880c46de8c66f286cb0af7ec\result.json`.
El ZIP de esa comprobación tiene **39.607.811 bytes**, SHA-256
`2b4e434cd64be99db8c45bb4bd2fb2054502cce1ae20759a619b1ac911b4a023`.
Fue una copia del árbol publicable, **no un clon remoto del repositorio entonces
vacío**, y registra `commit=null`. No reemplaza los otros candidatos,
las copias históricas ni una futura ejecución CI del commit publicado.

La repetición completa del workflow en los tres sistemas queda **pendiente de
CI nativo**; la unidad sintética del auditor no la sustituye. La revisión independiente
del nuevo tooling/paquetes corresponde a Vasquez. La aprobación previa de las
fuentes 0.4 no aprueba por sí sola este nuevo pipeline multiplataforma.

Referencias oficiales verificadas:

- [Godot 4.7.2 y checksums](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).
- [Exportador macOS del commit fijado: plantilla estándar y requisitos de textura](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/platform/macos/export/export_plugin.cpp).
- [Exportar macOS: Universal2 y ad-hoc sin Developer ID](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html).
- [Licencias y avisos de terceros](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).
- [Runners estándar gratuitos de repositorios públicos](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- [Abrir apps de desarrolladores no identificados](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac).
