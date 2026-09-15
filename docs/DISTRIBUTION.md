# Distribución de candidatos nativos

Alcance autorizado el **15 de septiembre de 2026**: preparar releases
**Windows x86_64, Linux x86_64 y macOS Universal2** de `0.4.0-preview`.
Esto no amplía el gameplay de §4.3, no completa el MVP y no aprueba arte,
sensación humana, mando físico o FPS. El pipeline construye candidatos:
coordinación gestiona el repositorio, commit y tag; **publica el release sólo
después de la verificación conjunta y QA**.
Ningún script ni workflow de este encargo crea releases o ejecuta push.

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
se extrae el template release del destino. La caché Windows existente en
`tools\godot\.cache` se puede reutilizar; no se reinstala el entorno anterior.

## Contrato del build

La entrada es `game\project.godot`: de ahí se obtienen nombre, versión, escena
principal e input schema. El tag, si se proporciona, debe ser exactamente
`v` + versión: **`v0.4.0-preview`**. No se cambia la versión para hacer coincidir
un tag. `--tag` identifica la versión prevista: **no exige que ese tag Git exista
ni lo crea**. Fuera del modo local explícito, el commit debe ser el `HEAD` consumido y
las fuentes, tooling y licencia utilizados no pueden tener cambios pendientes.

La raíz Git efectiva debe ser la raíz fuente resuelta, respetando la comparación
de rutas de cada OS: una copia dentro de una carpeta ignorada no hereda el commit
del repositorio padre. No basta `git status`: se cotejan los bytes consumidos con
los blobs de `HEAD`, incluidos el tooling ejecutado y la licencia. Se rechazan
archivos ignorados adicionales y cambios ocultos con `assume-unchanged` o
`skip-worktree`. Se normaliza CRLF/LF únicamente en los formatos de texto
declarados; los assets LFS expandidos deben corresponder al SHA-256 y tamaño
del pointer comprometido.

Cada build:

1. Fija un snapshot de fuente y las huellas de los EXE históricos presentes.
   Rechaza punteros LFS sin resolver. Copia el proyecto a un directorio privado,
   excluyendo `.godot`; no importa sobre el árbol de trabajo original.
2. Extrae el editor y template verificados, configura **sólo la copia privada**
   con la ruta del template y ejecuta importación nativa. No usa `Common.ps1`,
   inventarios Windows ni el diagnóstico de Blender/Foundation.
3. Ejecuta los smokes fuente, exporta con **`--export-release`**, prepara avisos
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

- `futsal-v0.4.0-preview-windows-x86_64.zip`
- `futsal-v0.4.0-preview-linux-x86_64.zip`
- `futsal-v0.4.0-preview-macos-universal.zip`

Cada candidato lleva un `.sha256`, un `.build.json` y `proof\<plataforma>`.
La metadata conserva commit o su ausencia explícita, motor, template, plataforma,
snapshot de fuente, contenido/hash del ZIP, cuatro recorridos y limitaciones.
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
python -m tools.release build --platform windows-x86_64 --tag v0.4.0-preview `
  --cache .\tools\godot\.cache --output .\build\release\local-dispatch-final `
  --allow-uncommitted

# Auditoría pasiva del ZIP y de sus evidencias; no ejecuta Godot.
python -m tools.release audit --archive `
  .\build\release\local-dispatch-final\dist\windows-x86_64\futsal-v0.4.0-preview-windows-x86_64.zip
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
python -m tools.release build --platform windows-x86_64 --tag v0.4.0-preview
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
input obligatorio `version` (default `v0.4.0-preview`), en el repositorio público
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
gh workflow run release.yml --repo jmanuelcorral/futsal --ref main -f version=v0.4.0-preview
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
checkout usa `persist-credentials: false`. No hay credenciales Apple,
PAT de publicación, secrets propios ni permisos de escritura.
Coordinación consume los tres artefactos y el índice del **mismo run**, comprueba
QA y ejecuta su publicación final con `gh` fuera de este workflow, creando el tag
y release sobre el **SHA exacto que pasó**, no sobre un `main` que haya avanzado.
El workflow no crea ni mueve etiquetas.

Para auditar conjuntamente una descarga existente:

```powershell
python -m tools.release verify --directory .\build\release\downloaded `
  --commit <SHA-del-run> --tag v0.4.0-preview `
  --index .\build\release\verified\release-index.json
```

Los candidatos que declaran commit necesitan el checkout limpio de ese SHA
para acreditar su procedencia. Cada snapshot archivado se compara con la fuente
esperada de ese commit; no basta que los tres paquetes coincidan entre sí.
Los candidatos locales con `commit=null` conservan auditoría pasiva, pero nunca
acreditan un commit ni pasan como conjunto publicable.

## Evidencia y límites de esta entrega

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

Linux/macOS y la ejecución alojada del workflow quedan **pendientes de CI nativo**;
la unidad sintética del auditor no los sustituye. La revisión independiente
del nuevo tooling/paquetes corresponde a Vasquez. La aprobación previa de las
fuentes 0.4 no aprueba por sí sola este nuevo pipeline multiplataforma.

Referencias oficiales verificadas:

- [Godot 4.7.2 y checksums](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).
- [Exportar macOS: Universal2 y ad-hoc sin Developer ID](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html).
- [Licencias y avisos de terceros](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).
- [Runners estándar gratuitos de repositorios públicos](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
- [Abrir apps de desarrolladores no identificados](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unidentified-developer-mh40616/mac).
