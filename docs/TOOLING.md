# Herramientas locales: Blender, MCP, dream-loop y Godot

Verificación inicial: **9 de septiembre de 2026, Windows x64**. Blender/MCP están
instalados y aprobados; sus pins no cambian. Tras autorizar el MVP, el tooling de
Godot separa el **diagnóstico técnico independiente** de la validación de la
**microdemo G1 histórica: un humano de campo, un rival IA y dos porteros IA**.
El **10/9** se validaron `0.2.0-preview` y `0.3.0-preview`, conservadas como
históricas con sus propios artefactos, hashes e informes. El **14/9** el ejecutable
activo `build\windows\FutsalG1.exe` contiene **`0.4.0-preview`, Futsal — Laboratorio
5v5, input schema 3**: coordinación completó fuente, exportado y arranque normal
de af23 posterior a la promoción del All 196.
**Revisión técnica cerrada por Vasquez** (`technicalReviewPending=false`):
SOURCE_APPROVE de las fuentes y PACKAGE_APPROVE estructural de `af23…`.
La copia versionada del EXE y sus veinte PNG **ya fueron
publicados localmente y cotejados por coordinación antes de C1/C2**; esta
actualización sólo confirma ese hecho, no repite ni sobrescribe la publicación.
Los resultados históricos del bootstrap no prueban el partido. La inspección de
legibilidad del HUD no equivale a art score: el bucle visual no se ha ejecutado y
los gates humanos, artísticos y de rendimiento siguen pendientes.

**El paquete técnico 0.4 está cerrado.** La revisión identificó dos bloqueos:
**C1**, drenaje final sin límite cuando un hijo no identificado hereda los pipes;
**C2**, activación del exportado antes de validarlo. Se detectaron en revisión
estática; C1 se reprodujo después en el wrapper completo con pipes heredados.
Son independientes del episodio de Modern Standby documentado, no causas
atribuidas a otros incidentes. Coordinación corrigió ambos y completó **All 196/196,
Foundation 915/915 y ProcessNative 110/110**. Vasquez aprobó las seis fuentes C1/C2,
Trace Native y el último oráculo de metadatos corregido, además de la estructura
del paquete. El helper posterior pasó 247/247; no altera los 235 del All.
La promoción verificó `af23…` idéntico y no lo reescribió. El **All 191 anterior
a C1/C2** permanece como origen de los veinte PNG ya publicados; los 912/88
anteriores también se conservan como históricos.
Coordinación también completó el arranque normal posterior a esta promoción:
exit 0, stderr vacío y EOF estricto. El arranque af23 anterior se conserva como
histórico. **No quedan hallazgos de fuente abiertos en este cierre técnico**;
esta edición documental registra los veredictos, no ejecuta etapas ni concede gates.

## Estado y versiones

| Componente | Instalado / fijado | Estado |
| --- | --- | --- |
| Blender | **4.5.13 LTS**, build `daeeeca98fb0` | Ejecutable real comprobado; exportación GLB comprobada |
| Addon MCP | upstream `5f8ddaf6e987c4aa0c3467fcc548838b28f64477`, addon 1.6, protocolo 5 | Instalado, activado y guardado en preferencias; arranque del socket explícito |
| Servidor Python | `blender-mcp==1.9.1`, SDK `mcp==1.30.0` | MCP stdio comprobado contra Blender real |
| Python de MCP | **3.12.13**, gestionado por uv | Entorno aislado; no modifica Python 3.14 del sistema |
| uv | **0.11.21** comprobado | Dependencias transitivas fijadas con hashes en `tools\mcp\uv.lock` |
| Copilot CLI | **1.0.84-3** comprobado | Reconoce la entrada de repositorio y el lanzador desde subdirectorios |
| dream-loop | `d113b78bd8143d6c4e2b46840c1a881139bcc084`, MIT | Skill y licencia instalados con bytes upstream exactos; disponibles al recargar/reiniciar Copilot |

**Instalado no significa ejecutándose.** La prueba cierra sus procesos. El socket de Blender queda **verificado bajo demanda**, no como servicio residente. Para utilizarlo, hay que mantener abierto el lanzador de la siguiente sección.

Las rutas resueltas de esta máquina se conservan en los inventarios ignorados:

- `tools\blender\local.json`: ejecutable, versión y SHA-256 del binario.
- `tools\mcp\local.json`: intérprete, uv, addon y hashes.
- `tools\mcp\copilot.local.json`: configuración Copilot con rutas absolutas.

Ubicaciones de instalación:

```text
%LOCALAPPDATA%\Programs\Blender\blender-4.5.13-windows-x64\blender.exe
%APPDATA%\Blender Foundation\Blender\4.5\scripts\addons\blender_mcp.py
%APPDATA%\Blender Foundation\Blender\4.5\config\userpref.blend
<repositorio>\tools\mcp\.venv\Scripts\python.exe
<repositorio>\tools\mcp\.cache\python\...
```

No se añadieron rutas personales a la configuración compartida ni se modificó el `PATH`.

## Instalar o reproducir

Requisitos ya presentes en esta máquina: **PowerShell 7.2+**, `uv`, `git` y `curl.exe`. Los scripts fallan de forma explícita si faltan herramientas; no ejecutan instaladores opacos ni actualizan dependencias a `latest`.

Desde la raíz del repositorio:

```powershell
pwsh -NoProfile -File .\tools\blender\Install-Blender.ps1
pwsh -NoProfile -File .\tools\mcp\Install-Mcp.ps1
pwsh -NoProfile -File .\tools\dream-loop\Install-DreamLoop.ps1
```

Los tres pasos son repetibles. La segunda ejecución se comprobó sin cambiar versiones, hashes del addon ni la configuración `squad_state`.

### Procedencia de Blender

- Se comprobaron registro, rutas de instalación enfocadas y paquetes WinGet instalados: no había Blender.
- El catálogo WinGet de `BlenderFoundation.Blender.LTS.4.5` ofrecía **4.5.10** y MSI WiX. Se eligió el ZIP oficial **4.5.13**, más reciente, instalado por usuario sin UAC, reinicio ni reemplazar otras versiones.
- `tools\blender\release.json` fija URL, versión y SHA-256. El instalador contrasta además el manifiesto de checksums oficial, **antes de extraer o ejecutar** el binario.
- SHA-256 del ZIP: `b5fdf800ce65fa2f209e8f68d02667e4d720fa1c42f247c72d1882ab04decba6`.
- El ZIP se elimina tras instalar; `-KeepArchive` permite conservarlo en la caché ignorada.
- `-BlenderPath 'C:\ruta\blender.exe'` permite registrar explícitamente una instalación existente de la versión fijada. Una versión distinta produce un error, no una actualización silenciosa.

### Dependencias y addon

`Install-Mcp.ps1` ejecuta `uv sync --locked --no-build --python 3.12.13`. No ejecuta builds de paquetes fuente. El wheel publicado coincide, en los diez archivos revisados, con los blobs del commit indicado en `tools\mcp\upstream.json`. Su SHA-256 es:

```text
ede3aed34926f77142b8f00ee4f8544f68067d2dc747da8295d1c456171355b2
```

**Modificación local documentada del addon:** upstream abre el socket al registrar el addon y deja el consentimiento de telemetría activado por defecto. `configure_blender.py` aplica cinco sustituciones verificadas: consentimiento predeterminado falso, opción de autoarranque predeterminada falsa, decisión de autoarranque por escena falsa, alternativa sin escena falsa y enlace exclusivo del listener real. En Windows se exige `SO_EXCLUSIVEADDRUSE` antes de `bind`, sin `SO_REUSEADDR`; la comprobación previa de puerto no sustituye esa exclusividad. No se modifica el paquete Python instalado.

El addon resultante tiene SHA-256:

```text
dffe5bbe59283094499fd10c83650e23db7f736e8742109cdf03da7eecae507d
```

Se guarda la activación y el consentimiento desactivado en `userpref.blend`. Si hay preferencias previas, se conserva una copia `userpref.blend.futsal-before-mcp.bak` **junto a ellas**, nunca en Git. Solo se admiten el upstream fijado, el resultado actual o la revisión anterior expresamente enumerada en `upgradeFromSha256` de `tools\mcp\upstream.json`; cualquier addon desconocido se rechaza. La migración conserva los respaldos originales y es repetible. No se reemplaza `startup.blend` ni se habilita globalmente la autoejecución de Python.

**No ejecutar `uvx blender-mcp install-addon` ni actualizaciones automáticas sugeridas por upstream:** perderían la versión o la política local. Para actualizar, revisar un nuevo pin, checksums, lockfile y parche; repetir todas las pruebas.

## Utilizar en la próxima sesión

### Terminal A: Blender y su socket

```powershell
pwsh -NoProfile -File .\tools\mcp\Start-BlenderMcp.ps1
```

Abre **una nueva instancia de Blender con interfaz gráfica**, comprueba su PID y la respuesta TCP en `127.0.0.1:9876`, y permanece unido a ese proceso. Upstream rechaza `--background` para el socket porque necesita el bucle de eventos de la interfaz.

Para abrir un archivo propio expresamente:

```powershell
pwsh -NoProfile -File .\tools\mcp\Start-BlenderMcp.ps1 -BlendFile 'C:\ruta con espacios\escena.blend'
```

Se usa siempre `--disable-autoexec` y un script de arranque conocido. Las integraciones externas se desactivan también al cargar otra escena durante esa sesión. Guarda el trabajo antes de cerrar Blender o pulsar Ctrl+C. El lanzador solo cierra el proceso que él creó; no mata procesos por nombre. Si el puerto está ocupado, falla sin reemplazar ninguna sesión existente.

### Terminal B: Copilot

```powershell
pwsh -NoProfile -File .\tools\mcp\Start-Copilot.ps1
```

El lanzador genera/actualiza únicamente la entrada `blender` de `tools\mcp\copilot.local.json`, cambia a la raíz del repositorio y ejecuta:

```powershell
copilot --additional-mcp-config '@C:\ruta-del-repositorio\tools\mcp\copilot.local.json'
```

No modifica `~\.copilot\mcp-config.json`, servidores globales ni permisos de aprobación.

**Copilot CLI sí reconoce actualmente `.mcp.json` del repositorio.** Se comprobó con:

```powershell
copilot mcp get blender --json
```

Resultado: `source: "workspace"`, `enabled: true`, origen `.mcp.json`, seis herramientas. Las rutas de esta configuración compartida son relativas a la raíz; usa el lanzador para evitar problemas al trabajar desde subdirectorios o mover el checkout. Copilot exige la confianza habitual en la carpeta; no se evita ese control.

La entrada existente `squad_state` se conserva sin cambios (`npx -y @bradygaster/squad-cli@0.10.0 state-mcp`). En Copilot, `/mcp` permite inspeccionar la conexión y `/skills` permite comprobar `dream-loop` después de reiniciar o recargar skills.

Las seis herramientas expuestas son:

```text
get_addon_status
get_scene_info
get_object_info
get_viewport_screenshot
execute_blender_code
disable_telemetry
```

El wrapper elimina las otras **22 de las 28** herramientas upstream del registro MCP; no se limita a ocultarlas en la interfaz de Copilot.

## Verificar

Prueba integral independiente, con escena de fábrica y limpieza del proceso:

```powershell
pwsh -NoProfile -File .\tools\mcp\Test-BlenderMcp.ps1
```

Equivalente a través del lanzador normal:

```powershell
pwsh -NoProfile -File .\tools\mcp\Start-BlenderMcp.ps1 -SmokeTest
```

La prueba **abre una ventana gráfica nueva**, no toca una sesión existente y usa el **SDK oficial MCP por stdio**, leyendo la configuración generada de Copilot. Ejecuta `initialize`, `tools/list` y **7 `tools/call` reales**, incluidos dos `get_scene_info`, consulta de objeto, lectura de opciones, rechazo de `import os` y captura PNG. No sustituye MCP por una prueba de socket directo.

Resultados iniciales observados:

- **17/17 comprobaciones MCP**; protocolo negociado `2025-11-25`.
- **28 herramientas upstream / 6 expuestas**.
- Escena antes y después idéntica: **3 objetos** (`Camera`, `Cube`, `Light`), sin duplicados.
- Addon 1.6 / protocolo 5, `up_to_date: true`, consentimiento falso.
- Poly Haven, Hyper3D/Rodin, Hunyuan3D, Sketchfab y Poly Pizza: **los cinco desactivados**.
- PNG de viewport válido de **256 × 107**; no representa concept art ni una validación artística.
- Verificación aparte con Blender en segundo plano: preferencias persistidas y **GLB real de 860 bytes**, con un único triángulo de prueba. El GLB se elimina después.
- Los PID propios de Blender y del servidor stdio terminaron; **0 listeners en el puerto 9876** después de la prueba.
- **26/26 pruebas Python**, sin omisiones: 14 de herramientas, 7 de configuración/migración y 5 del listener con sockets reales de Windows. Sintaxis del conjunto Blender/MCP/skill: **8/8 PowerShell** y **8/8 Python**.
- Arranque simultáneo comprobado también con dos lanzadores reales: ambos superan la precomprobación antes de iniciar Blender, pero solo uno anuncia disponibilidad. El otro termina con puerto ocupado y sin anunciar una escena disponible. El ganador completa los 17 controles MCP; ambos procesos propios se cierran.
- Una operación adicional por MCP creó geometría temporal, exportó un **GLB válido de 868 bytes** y restauró la escena original. Prueba de modelado/exportación, no evidencia de calidad artística.

La prueba aísla también la recuperación automática `quit.blend` de Blender en un directorio propio y lo elimina al terminar. Las sesiones normales conservan sus archivos de recuperación dentro de su directorio de sesión ignorado.

Evidencia local ignorada: `tools\mcp\runtime\smoke-result.json`, `blender-verification.json`, `server-policy.json`, `last-session.json` y logs de sesión. Son resultados fechados, no un monitor de disponibilidad actual.

Pruebas unitarias de pins, configuración, ocupación de puerto, timeouts y limpieza de procesos:

```powershell
.\tools\mcp\.venv\Scripts\python.exe -m unittest discover -s .\tools\mcp -p 'test_*.py' -v
pwsh -NoProfile -File .\tools\dream-loop\Install-DreamLoop.ps1 -VerifyOnly
```

Para verificar una sesión que tú ya abriste, sin iniciarla ni cerrarla:

```powershell
pwsh -NoProfile -File .\tools\mcp\Test-BlenderMcp.ps1 -ExistingSession
```

Hazlo con Blender inactivo y sin otro cliente MCP concurrente. La captura es de esa sesión; no uses esta variante si contiene información que no quieras mostrar al cliente.

## Límites de seguridad

- Solo **loopback IPv4 `127.0.0.1:9876`**. No se habilitó `0.0.0.0`, HTTP público ni reglas de firewall.
- `DISABLE_TELEMETRY=true` es la variable upstream comprobada que desactiva también los contadores anónimos. Quitar solo el consentimiento en Blender **no** basta. Se aplican ambos controles.
- `BLENDER_MCP_SAFE_MODE=1` activa la validación AST del servidor. Se comprobó el rechazo de una importación de `os`. **No es un sandbox**: Blender conserva permisos del usuario, y operadores de guardado/importación/exportación siguen pudiendo acceder a archivos.
- El socket del addon no tiene autenticación y acepta Python desde procesos locales; el modo seguro protege la ruta MCP, **no** conexiones directas al socket. Mantén el socket cerrado cuando no lo uses y trata cualquier código/archivo externo como no confiable.
- No se configuraron claves, pruebas gratuitas, servicios de pago, descargas de assets ni subidas. Poly Haven, Sketchfab, Poly Pizza, Hyper3D/Rodin y Hunyuan3D quedan fuera hasta una autorización explícita y revisión de la política.
- El servidor upstream crea un identificador local incluso con telemetría desactivada. El wrapper redirige ese estado y los archivos de trabajo a `tools\mcp\runtime`; no se transmite. La opción de consentimiento se recuerda como rechazada solo en ese estado local.
- Instalar no deja servicios residentes. No se cambian preferencias globales de autoejecución, software ajeno, ramas ni commits.

## dream-loop: instalado, no ejecutado

Se incluyen únicamente `SKILL.md`, `LICENSE` y `UPSTREAM.json` en `.github\skills\dream-loop`. El instalador verifica tamaño, SHA-256 y SHA de blob Git. No instala paquetes `npx`, generadores ni librerías de assets. Si un checkout de Windows convierte LF a CRLF, ejecutar el instalador normal restaura exclusivamente esa conversión cuando el resultado coincide exactamente con el pin; no sobrescribe otras modificaciones.

La skill requiere una **referencia visual aprobada** o un generador autorizado, revisión con visión, capturas reales del producto y medida de FPS. En este entorno **no hay una API de generación de imágenes habilitada** ni una referencia aprobada. Por tanto:

1. La instalación está terminada; recargar/reiniciar Copilot permite descubrirla.
2. El bucle visual **no está operativo de principio a fin** y no se ha iniciado.
3. Antes de utilizarlo, aportar una referencia aprobada o autorizar/configurar un generador, disponer del producto ejecutable y fijar el FPS objetivo.
4. La salida de éxito upstream exige **nota ≥ 8 y FPS aceptable**; instalar Blender no demuestra ninguno de esos criterios.

Los archivos de trabajo de esa futura actividad irán a `.dream-loop`, ignorado por Git.

## Fuentes y mantenimiento

- [Blender 4.5: archivos oficiales](https://download.blender.org/release/Blender4.5/) y [checksums 4.5.13](https://download.blender.org/release/Blender4.5/blender-4.5.13.sha256).
- [Blender MCP: README del commit revisado](https://github.com/ahujasid/blender-mcp/blob/5f8ddaf6e987c4aa0c3467fcc548838b28f64477/README.md). Integración de terceros, **no oficial de Blender Foundation**.
- [Paquete publicado blender-mcp 1.9.1](https://pypi.org/project/blender-mcp/1.9.1/).
- [Configuración MCP de Copilot CLI, incluido el repositorio](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers).
- [Ubicaciones oficiales de agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills).
- [dream-loop: skill revisada](https://github.com/achimala/dream-loop/blob/d113b78bd8143d6c4e2b46840c1a881139bcc084/SKILL.md).

`config\toolchain.json` mantiene el inventario compartido sin rutas personales. Las cachés, entornos, logs, configuraciones locales y resultados de pruebas están excluidos de Git.

## Godot: entorno fijado, diagnóstico independiente y versiones del laboratorio

**Entorno verificado, separado de la aceptación de producto.** Godot **4.7.2 standard**
se ejecutó como `4.7.2.stable.official.ed1daf0bf`. Se mantiene la decisión
`Forward+ / Vulkan / GDScript tipado / Jolt a 60 Hz`, sin instalar la edición .NET
de Godot ni un SDK adicional. Los helpers Win32 usan el runtime ya incluido en PowerShell.
El proyecto `game\project.godot` está aislado del equipo Squad, MCP, entornos Python
y cachés del repositorio: Godot no importa ni exporta la raíz completa.

### Instalar y repetir

```powershell
pwsh -NoProfile -File .\tools\godot\Install-Godot.ps1
```

- Primero se buscaron instalaciones enfocadas en `PATH`, carpetas habituales y
  registro: no había Godot. El instalador reutiliza rutas verificadas si ya existen.
- `tools\godot\release.json` fija versión, edición, URLs y **SHA-512** del ZIP y TPZ.
  Ambos se contrastan con `SHA512-SUMS.txt` de la release oficial **antes de extraer
  o ejecutar**. No se confía en una URL, un nombre de archivo o un inventario solo.
- ZIP oficial: **86.013.866 bytes**. TPZ standard: **1.281.349.702 bytes**; se extraen
  únicamente `version.txt` y las **12 plantillas/binarios Windows**, no Android,
  Linux, macOS ni plantillas .NET.
- Se comprueban además los hashes de los archivos extraídos. Si un archivo existente
  es distinto, se rechaza sobrescribirlo. No hay fallback a versiones sin verificar.
- Se permite `-GodotPath 'C:\ruta\Godot_v4.7.2-stable_win64.exe'` para registrar un
  binario oficial idéntico. No se ejecuta para averiguar su versión antes de validar
  su contenido contra el ZIP oficial. También se admite un `.exe` renombrado:
  `godot.exe` se empareja con `godot_console.exe`, conservando los bytes oficiales.
  Un archivo distinto que ya ocupe el nombre del wrapper se rechaza sin sobrescribirlo.
- Los archivos de descarga quedan en `tools\godot\.cache`, ignorados, para repetir
  la comprobación sin descargar de nuevo aproximadamente 1,37 GB. `-RemoveArchives`
  los elimina después de verificar; la siguiente instalación tendrá que descargarlos.
- Se comprobó una segunda ejecución: misma versión, rutas y hashes de ambos
  ejecutables y de todas las plantillas. Solo cambia la fecha del inventario local.

La regresión `pwsh -NoProfile -File .\tools\godot\tests\Test-InstallerReuse.ps1`
comprueba 13 condiciones mediante el instalador real, incluidos alias explícito,
descubrimiento por `PATH`, repetición y preservación de archivos ajenos. Restaura el
inventario original byte por byte y elimina sus copias temporales. Ejecutarla sin
otros instaladores o validaciones de Godot concurrentes.

Ubicaciones de esta instalación:

```text
%LOCALAPPDATA%\Programs\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe
%LOCALAPPDATA%\Programs\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe
%APPDATA%\Godot\export_templates\4.7.2.stable
<repositorio>\tools\godot\local.json
```

No requiere UAC, MSI, modificación de `PATH` ni ajustes globales de GPU.
`local.json` guarda las rutas personales y hashes realmente comprobados; no se
versiona. Las ejecuciones posteriores también comprueban la integridad de Godot.

### Abrir el editor, el laboratorio o el diagnóstico

Desde la raíz:

```powershell
# Editor, por defecto
pwsh -NoProfile -File .\tools\godot\Start-Godot.ps1

# Main del laboratorio; nunca sustituye silenciosamente el bootstrap
pwsh -NoProfile -File .\tools\godot\Start-Godot.ps1 -RunGame

# Pantalla diagnóstica explícita: no empieza un partido
pwsh -NoProfile -File .\tools\godot\Start-Godot.ps1 -Diagnostic
```

El lanzador resuelve el proyecto desde su propia ubicación, mantiene el proceso
adjunto y registra logs en `tools\godot\runtime`. Cierra su ventana o pulsa Ctrl+C
para terminar solo esa ejecución; guarda antes cualquier trabajo de edición.
El **2/2 histórico** de `tools\godot\runtime\launcher-smoke.json` comprobó el
editor y el antiguo bootstrap mediante ventanas responsivas; no se presenta como
prueba del nuevo modo jugable. `-RunGame` exige nombre **Futsal — Laboratorio 5v5**,
versión `0.4.0-preview`, input schema **3** y main
`res://match/match.tscn`; si faltan, falla sin abrir el diagnóstico.

El bootstrap, siempre `res://bootstrap/bootstrap.tscn`, muestra
**“Diagnóstico técnico independiente de la microdemo”**. La fuente actual declara
`0.4.0-preview` e input schema v3. Foundation **915/915** verificó el diagnóstico
aislado posterior a C1/C2, preservando la activa. El 912/912 anterior al último
ajuste UI permanece histórico; ninguno sustituye al recorrido del partido.
Informa motor, renderer, GPU y física de esa ejecución, no del juego. Conserva
las nueve acciones anteriores (WASD/stick, Shift/RT, Ctrl/LT, J/A, K/B, Esc/Start)
y añade regate L/X. Teclado y mando declaran `device=-1` para aceptar cualquier dispositivo.
Las flechas físicas añaden cuatro pares press/release a las acciones de movimiento;
no sustituyen WASD ni crean acciones paralelas. El diagnóstico no decide entre
PASS y SWITCH: esa interpretación pertenece al input/autoridad del partido.
**En esta pantalla** solo se diagnostican bindings; los comandos de juego,
el balón, la cámara y el HUD pertenecen al main del laboratorio, no al bootstrap.

Se declara explícitamente Forward+ y se desactiva
`rendering/rendering_device/fallback_to_opengl3`. No se sustituye a escondidas por
Compatibility. En esta máquina Godot escogió automáticamente **NVIDIA, índice 0**.
Si otra máquina escoge Intel y se desea NVIDIA, primero comprobar los índices en
el log `--verbose` y pasar `-GpuIndex N` al lanzador o al test; no copiar un índice
entre máquinas ni cambiar preferencias de Windows.

### Jugabilidad 0.4 — cierre técnico revisado de fuente y exportado

**Estado del 14/9: pipeline corregido verificado; af23 conservado y revisión técnica cerrada.**
Coordinación completó el `All` final **196/196**, `ok=true`, en **766,223 s**:
`tools\godot\runtime\preview-20260914T173159Z-2299ed7ae9a849a1a0cbcf7a43d4f930\result.json`.
El informe conserva `gameplayValidated=true`, `productGatesAccepted=false` y
dependencias pendientes vacías. Estos son resultados de esa ejecución:
esta actualización de tres documentos/configs no vuelve a ejecutar Godot,
helpers, GUI ni exportación.
El alcance sigue siendo §4.3 en micro y preview: no carrera, XP, editor de
equipo, red, tarjetas o ventaja, ni promoción automática de G2/G3.

El All anterior **191/191, 745,096 s**, en
`tools\godot\runtime\preview-20260914T161724Z-92b1a73a68a944c49b48ddf4d2bf2d52\result.json`,
se conserva como origen de la publicación existente, no como último cierre del
pipeline. Ambos validaron los mismos **103563688 bytes / SHA af23…**.

`Common.ps1`, pipeline, lectores y bootstrap diagnóstico requieren
**0.4.0-preview / input schema 3**. El diagnóstico
añade `dribble` con `KEY_L`/`JOY_BUTTON_X`, conservando nueve acciones anteriores
y flechas; `config\input-schema.json` fija ese contrato de bindings, no reemplaza
el InputMap que mantiene Hicks.

La 0.3.0 completa se trasladó, sin alterar sus datos, a
`playerControlValidation` con `historical=true`: conserva **125/819/72**,
identidades, capturas y revisión. `previousPreviewValidation` sigue siendo 0.2.0
y `g1Validation` no cambia. En `previewValidation` 0.4, runtime/GPU están
verificados; humano/arte/FPS siguen en false. Vasquez concedió **SOURCE_APPROVE**
y **PACKAGE_APPROVE estructural** para el alcance de esta entrega.
No se hereda la aprobación técnica de 0.3 para esta entrega.

#### Artefacto, arranque y resultados de la candidata af23

- Activo: `build\windows\FutsalG1.exe`, **103563688 bytes**, SHA-256
  `af23eb5c41453a108ad1f53d63a5590575b607b59a1d49a1f60ff6b079ce2a0f`.
- Copia publicada: `build\windows\FutsalPreview-0.4.0.exe`, byte-idéntica:
  **103563688 bytes** y el mismo SHA `af23…`. Es la publicación anterior a C1/C2,
  preservada sin sustituirla por la evidencia nueva.
- Candidato validado:
  `tools\godot\runtime\preview-20260914T173159Z-2299ed7ae9a849a1a0cbcf7a43d4f930\candidate\FutsalG1.exe`.
  Candidato, activa y copia fija mantienen **103563688 bytes / SHA af23…**.
  El resultado registra `artifactPromotion.promoted=true`,
  `reusedIdentical=true` y `backup=""`: verificó la identidad sin reescribir
  la activa ni crear un backup innecesario; conserva el candidato original.
- Arranque normal **posterior a la promoción del All 196**, del mismo EXE:
  **240 frames de render solicitados**, sin smoke, diagnóstico ni `--fixed-fps`,
  exit **0**, stderr **0 bytes**, `OutputComplete=true`,
  `StdoutComplete=true`, `StderrComplete=true` y power request liberado.
  Forward+/Vulkan y la **RTX 2000 Ada Generation Laptop GPU** constan en stdout.
  Evidencia:
  `tools\godot\runtime\coordinator-normal-04-promoted-4de8288e7ced411daeba4443b859fc68\result.json`.
  Conserva **103563688 bytes / SHA af23…** y no acredita input humano ni FPS;
  no se midió rendimiento a partir de esos frames.
  El mismo informe registra los **cinco EXE** (activa, copia 0.4, G1, 0.2 y 0.3),
  sus bytes/hashes y **20 capturas publicadas verificadas**. Coordinación confirmó
  además el cotejo de fuentes, la decodificación de los PNG y el catálogo literal
  de su manifiesto, sin sobrescribir la publicación del All 191.
- Arranque af23 anterior a la promoción, conservado como histórico:
  `tools\godot\runtime\coordinator-normal-04-final-a93753b0cfb1423caca88dc2fd799755\result.json`.
  No se reutiliza como si fuera el arranque nuevo.
- `ProcessNative` más reciente: **110/110**, posterior a C1, en
  `tools\godot\runtime\process-completion-29396b2f68c44bc08ae3792459f066f1\result.json`.
  El **88/88** anterior se conserva en
  `tools\godot\runtime\process-completion-47a9eb6b9ec944059ea4d817ca66ca20\result.json`.
  Son pruebas de procesos, no nueva aceptación de gameplay. El helper PS del
  All 196 pasó **104/104**; los **82/82** pertenecen al All 191 histórico.
- Foundation más reciente: **915/915**, en
  `tools\godot\runtime\20260914T172559Z-fd6d611755a44e9fbdf0bf0ad5e21eac\result.json`.
  Native bootstrap **256/256**, fuente headless/render **116/120** y EXE
  diagnóstico **118/122**. Usa su propio
  `diagnostic-artifact\FutsalG1.exe`, SHA `af23…`, con `artifactPromoted=false`;
  el hash de la activa anterior `af23…` permanece igual. No publica ni acredita
  por sí solo el cierre del All.
- Foundation **912/912** anterior al último ajuste de `RestartPanel`:
  `tools\godot\runtime\20260914T154640Z-a8fb03f28e4b445aabbcdec7b899f019\result.json`,
  SHA `3c01150618bdf7a1c882649c7dd3642c478187037f45ee41d55d01289480c00d`.
  Se conserva como historia de entorno/diagnóstico, no del artefacto activo.

Conteos observados dentro del `All` final **196/196**; **no se suman al runner ni son
constantes de aceptación para futuras revisiones**:

| Etapa | Resultado |
|---|---:|
| Helpers PS: disponibilidad / promoción | **17/17 · 49/49** |
| Helpers PS: MicroSlice / contrato y bindings / presentación | **482/482 · 235/235 · 89/89** |
| Helpers PS: runtime / native / procesos | **293/293 · 395/395 · 104/104** |
| Input schema / helpers del smoke / guards del default | **8/8 · 47/47 · 5/5** |
| Simulación / preview / integración micro / integración preview | **345/345 · 567/567 · 204/204 · 176/176** |
| HUD / Desarrollo / cambio de jugador | **682/682 · 747/747 · 345/345** |
| IA táctica / reglas puras / reglas físicas | **176/176 · 329/329 · 1522/1522** |
| Cámara / integración nativa de jugabilidad / guía | **8339/8339 · 698/698 · 158/158** |
| Gestos / visual | **190/190 · 230/230** |
| Smoke legado fuente: headless / renderizado | **201/201 · 206/206** |
| Smoke legado EXE: headless / renderizado | **218/218 · 223/223** |
| Gameplay fuente: headless / renderizado | **1080/1080 · 1120/1120** |
| Gameplay EXE: headless / renderizado | **1097/1097 · 1137/1137** |

Cada recorrido gameplay conserva **28 casos y 20 observaciones**: **20 PNG reales
1920×1080 por proceso renderizado**, cero PNG en headless. Fuente y EXE gráficos
registran NVIDIA RTX 2000 Ada Generation Laptop GPU, Forward+/Vulkan.
Los cuatro recorridos gráficos, incluidos los legados, observaron el bloque
exacto opt-in del loader Vulkan: los dos gameplay gráficos tienen **332 bytes
de stderr por ruta**, no stderr vacío. No se permitió otro diagnóstico.

El guard `no-ticks` es una negativa de fixture: al congelar deliberadamente la
simulación también detiene su muestreador de input, evitando reenviar el mismo
comando en tick 0. Conserva la barrera del default productivo y la prueba nativa
de input separada; no oculta rechazos reales ni amplía allowances.

**Revalidación completada:** un intento anterior posterior a C1/C2 paró **5/6**, en unos
23 s, por el assert de preparación de `tests\Test-GameplayValidation.ps1` que
exigía runtime/GPU false y EXE 0.3. Coordinación corrigió exclusivamente ese test
con **22 negativas** sobre G1/0.2/0.3, versión y gates: **235/235** dentro del
All 196, frente a las 213 anteriores.
Helpers no depende de que existan archivos runtime ignorados. No se restituyen
valores falsos ni se concede QA. El intento fallido queda histórico, no describe
el cierre actual. `metadataConsumerUpdatePending=false`,
`metadataConsumerValidationPending=false` y `pipelineRevalidationPending=false`
registran la ejecución completada. `technicalReviewPending=false` corresponde
al veredicto independiente recibido después, no al mero resultado de los tests.

**Regresión del oráculo posterior al All:** Vasquez detectó que `-cne` podía
aceptar un booleano o una colección como versión. La nueva negativa reprodujo el
fallo (**230/232**) antes de corregir las tres guardas con `-isnot [string]`,
sin convertir los valores. El helper conserva las 235 comprobaciones y añade
**12 negativas** —true, false, array de una versión y array repetido, en cada uno
de los tres campos—: **247/247**, con el wrapper real, EOF completo y stderr vacío,
en `tools\godot\runtime\metadata-oracle-final-51a2792fd9ea416ca2e101fe1cad9b6a\result.json`.
Esta ejecución sintética es posterior al All 196: no cambia sus 235 checks del
helper ni implica otra exportación. El binario af23 y su publicación tienen
**PACKAGE_APPROVE estructural** de Vasquez. La última corrección del oráculo,
SHA `ADB44207E3B275D64A519E9C09FB97E2CEC7C531FC88A48A72B3B374CC3285D9`,
tiene **SOURCE_APPROVE**; se cierra así el último hallazgo de fuente.

**C1 y C2 en el pipeline verificado:** las **77 etapas** registradas por el All
196 tienen `outputComplete=true`, `stdoutComplete=true` y `stderrComplete=true`.
El drenaje de limpieza ante error queda acotado a **1 s**, sin ampliar los plazos
de ejecución **native 120 s / runtime 300 s** ni reconstruir testigos desde JSON.
`All` exporta a `runPath\candidate\FutsalG1.exe` y valida el candidato completo;
libera la solicitud de disponibilidad antes de la promoción de la activa.
En este cierre `powerAvailability.released=true` y la promoción reutilizó el
artefacto byte-idéntico. Si debe reemplazar una activa distinta, la promoción
atómica preserva una copia previa byte-verificada para restauración manual; **ese
reemplazo no ocurrió aquí**, como muestra `backup=""`. Foundation conserva su
EXE diagnóstico aislado y nunca publica. La revisión independiente aprobó este
alcance técnico; no sustituye los gates humanos, artísticos o de rendimiento.

#### Disponibilidad de la validación y rendimiento de helpers

`PowerAvailability.ps1`, usado por **`Test-Godot.ps1` y `Test-MicroSlice.ps1`**,
crea una solicitud Win32 ligada al proceso/handle con `PowerCreateRequest`:
**SystemRequired + ExecutionRequired**, y **DisplayRequired** cuando el recorrido
incluye GUI. Se libera mediante `PowerClearRequest` y cierre del handle en
`finally`, también ante errores/adquisición parcial. Su helper pasó **17/17**;
Foundation 915 y el `All` 196 registran adquisición y liberación. La corrección de
disponibilidad no modificó `Common.ps1`; la corrección C1 posterior es independiente.
No se cambió `powercfg` global, no se provocó suspensión, no
se usó red ni se aumentaron los límites **native 120 s / runtime 300 s**.

La causa observada se limita al `All` fallido
`preview-20260914T145408Z-6fb4ba8e5507484387b933a3e4602123`: Kernel-Power **506**
a `2026-09-14T14:56:57.9377186Z` (`Idle Timeout`) y **507**
a `15:02:06.5918006Z` (`Input Touchpad`) documentan **308,654082 s de Modern Standby**
durante native. Al reanudar venció su plazo wall sin modificar. Evidencia:
`tools\godot\runtime\coordinator-suspend-diagnosis-aefa37adf93b4d37a5ff41683861ba7c\result.json`.
No se atribuyen a esta suspensión los demás retrasos históricos, incluido el
outlier de cámara de 821 s. Las solicitudes tampoco se presentan como cambio
permanente de política de energía o garantía frente a cualquier suspensión.

Antes se midieron y eliminaron dos costes concretos de PS: búsqueda de checks
con `Where-Object` sustituida por recorrido equivalente sin caché del lector,
y preparación de negativos runtime reducida de siete a dos serializaciones con
los mismos bytes y clones independientes. Se conservaron todos los checks,
añadiendo seis y dieciséis regresiones. El `All` 196 registra **40,461 s**
para native 395/395 y **145,795 s** para runtime 293/293.
Los **38,290 / 127,904 s** del All 191 quedan como evidencia anterior de los
mismos helpers, no como tiempos del cierre más reciente.
No se deduce de ellos una causa universal de variabilidad ni FPS del juego.

Los tres probes aislados posteriores al timeout terminaron en
**37,592 / 33,970 / 35,402 s**, sin reproducirlo. Sus marcas opt-in se emiten
**antes** de cada tramo; el observador tomó CPU, señal kernel y Tasks de ambos
pipes del handle original, sin recuperar PID ni editar Common. Se conservan
`ferro-helper-perf-894a482549b34a15a9a780230c535a32\final-audit.json` y
`ferro-native-intermittent-4d7a52debd084418bc407383c58f1c07\final-audit.json`,
bajo `tools\godot\runtime`. Su diagnóstico entonces no resuelto permanece
histórico; la correlación posterior con eventos de energía no se inventa retrospectivamente.

Referencias Microsoft verificadas para la corrección:
[PowerCreateRequest](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powercreaterequest),
[PowerSetRequest](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powersetrequest) y
[PowerClearRequest](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-powerclearrequest).

#### Productores obligatorios y menor objetivo nativo

`gameplay-contract.json` registra, sin contar la mera existencia del archivo
como éxito:

- `test_match_ai_tactics.gd`, `test_match_rules.gd` y `test_match_gameplay_rules.gd`.
- `test_match_camera.gd`, `test_match_gameplay_runtime.gd` y `test_match_aim_guide.gd`.
- `test_match_gestures.gd`, ya publicado por Lambert, es obligatorio: no vuelve
  a ser opcional si el archivo desaparece.

Core, preview, player-control, HUD, Desarrollo, visual e integraciones anteriores
permanecen obligatorios en sus recorridos. Los nuevos tests deben emitir checks
tipados, únicos y verdaderos, resultados coherentes y fallos vacíos. Solo los
productores legados aún sin `checks[]` conservan esa excepción;
si incluyen el array, también se valida. La regresión visual 0.4 ya publica el
array completo y también debe incluirlo. No se autorizan negativas nuevas por
coincidencia entre dos campos inventados: hacen falta constructor, retorno real
y diagnósticos exactos del productor. No se añade una excepción amplia de Jolt.

**`-Scope Gameplay`** ejecuta únicamente las siete suites nuevas, sin GUI ni
exportación; `Components`/`All` también las exigen. **`-Scope GameplayRuntime`**
es el objetivo mínimo del driver productivo: parsea ambos drivers y ejecuta solo
fuente headless mediante el mismo lector estricto, sin exportar ni capturar PNG.
Ambos conservan helpers y lock exclusivo. Son objetivos acotados del runner,
no nuevas ejecuciones de esta actualización documental.
El descubrimiento admite un marcador literal impreso o el método tipado literal
`_test_marker()`, rechazando expresiones calculadas y marcadores ambiguos.

La CLI y el decoder ya no son dependencias ficticias. Permanecen las guardas
reales de fuentes, versión/esquema, contrato y diagnósticos.
`GameplayNativeValidation.ps1` ya consume los constructores reales de IA,
reglas puras/físicas, cámara, integración de jugabilidad y guía. **Cámara y
`gameplay-runtime` nativo son failures-only en consola**: serializan todos los
`checks[]`, pero imprimen únicamente fallos. Sus lectores no exigen ni inventan
líneas `PASS` y rechazan éxitos paralelos fabricados. Los demás productores que
imprimen checks mantienen la correspondencia exacta con sus líneas `PASS`,
sin duplicados ni abortos. Esta excepción de transporte no se traslada al smoke
`FUTSAL_GAMEPLAY_SMOKE`, que sí imprime sus checks.
La clasificación mantiene cero diagnósticos/refusals y suma su polaridad desde
los checks; sus grupos y tamaños se contrastan con las matrices declaradas en
la fuente actual, no con un total histórico de autor. Las negativas físicas
unen alcance/modo, actor, código, mensaje esperado/observado y aserción real;
las faltas exigen escenarios de colisión y no un contador simulado.

El HUD conserva sus 16 rechazos originales y seis de selección, y su fuente
añade quince rechazos exactos de `present_restart`: **37 ocurrencias esperadas,
agrupadas en nueve mensajes distintos**. Cada
rechazo nuevo conserva la presentación y tiene una identidad contextual única.
La guía declara **15** errores de `WorldAimGuide.present`; tiene su propia
familia exacta, sin permiso para otros errores. La integración de jugabilidad
declara solo **un** warning exacto, `Ejercicio de entrenamiento no válido`, y
cuatro refusals de autoridad enlazados a secuencia repetida/pase prohibido en
READY, dos por modo: **dos `ERR_UNAUTHORIZED` (4)** con
`Launch refused: launch_rule` y dos `ERR_INVALID_PARAMETER` (31) de secuencia.
Se cotejan `command_refusals` y `expected_command_refusals`, actor 0, código,
mensaje, etiqueta de modo y aserción nativa. Las dos señales de autorización
**no son dos líneas `ERROR`**. Solo el warning anterior tiene permiso exacto
en stdout/stderr; no se añade ninguna allowance de error o warning.
Son contratos de fuente cotejados con fixtures y con las salidas nativas del
`All` citado, no permisos genéricos derivados de un contador.

La cámara conserva **33 casos**, incluidos dos de encuadre broadcast en ambos
extremos, bandas y focos 0/2, y exige sus dieciséis trazas modo/esquina/pase-o-tiro, con ticks de
entrada 0–60 y retorno 0–46, sin huecos ni muestras duplicadas. Se recomputan
profundidad/proyección desde el pose real y las ocho esquinas del volumen del
balón. El constructor nativo publica `screen` **normalizado**, no en píxeles;
`sphere_in_frame=true` no basta.
La revisión de Lambert añade `look_target` y `tracked_ball` como arrays de
tres números finitos, no cadenas `Vector3`. El lector admite campos aditivos
y exige los dos que publica ahora `get_camera_state()`. Comprueba que el
objetivo produce la orientación real y no coincide con el ojo. En el runtime,
el punto seguido coincide con el balón interpolado de `BallView`, no se fuerza
al snapshot físico; en las trazas nativas coincide con `sample.ball`.
La declaración de seguimiento no sustituye las comprobaciones de profundidad,
proyección y volumen completo, ni permite omitir el tick 31. No se fija la
fórmula de interpolación interna ni cambia el contrato de FOV/45 ticks.
La integración exige el catálogo completo, el default antes del primer reset,
input nativo y progresión de las extremidades con el contexto del host.
Los mensajes F07/F11 del control de jugador corresponden al contrato 0.4;
un replay explícito `-ProjectVersion '0.3.0-preview' -InputSchemaVersion 2`
conserva los mensajes históricos y nunca se acepta como ejecución 0.4.

**Finalizador heredado resuelto:** el contraejemplo de cámara se exige únicamente
si `legacy-counterexample` pertenece a `expected_cases`. Permanece obligatorio
en los 33 casos de cámara; no se añade artificialmente a los **41 casos** de la
suite hija `gameplay-runtime`. Ambos finalizadores exigen unicidad de checks.
Los 8339/8339 y 698/698 finales no omiten ni convierten en válido un fallo.

El menú usa navegación e input GUI reales y catálogo 12×2, con APIs separadas
para ayuda persistente y rechazo visible en READY. Mouse motion y botones se
despachan con `Viewport.push_input(event, true)` en coordenadas locales; teclas
y mando conservan `Input.parse_input_event`, dispositivo 0. Aplicar conserva el
check compuesto anterior y tres checks separados: petición única, ejercicio
solicitado y cierre del modal. No se sustituye el recorrido por una señal directa.

**Dos paneles distintos:** `RestartFeedbackPanel`, la ayuda/rechazo pequeño,
se reubicó abajo a la derecha; el `RestartPanel` grande recibió un ajuste de layout
**sólo durante córner**, preservando su presentación normal. **`EventPanel` no se movió.** Las regresiones
nativas llevaron HUD a 682 y cámara a 8339. Coordinación inspeccionó los ocho
PNG finales de córner de fuente: porterías completas sin paneles delante del gol.
Esto acredita esa legibilidad, no un art score ni aceptación de G2/G3.

**F12 medido, no sólo contadores:** se muestrean frames de proceso consecutivos
durante al menos 50 ticks de autoridad, con tope 6000. El productor serializa
`camera_handoff_motion`: ticks, frames, consecutividad, máximo desplazamiento,
mínimo producto escalar de la orientación, avance X del foco, visibilidad de
balón/portero y fase/cámara/selección finales. El lector valida sus tipos y valores,
no sólo un check de éxito. En `player-control.json` del All 191
(`preview-20260914T161724Z-92b1a73a68a944c49b48ddf4d2bf2d52`): **ticks 5–55,
121 frames, máximo 0,370381 m, mínimo dot 1,0 y avance X 2,700163 m**, portero 2
seleccionado, balón/portero visibles, PLAYING y broadcast. Se mantienen los límites
de **<1 m por imagen y dot >0,999**. Son observaciones resumidas por el productor,
no un array publicado de poses por frame ni una medición de FPS.

Las mutaciones productivas previas de coordinación conservan rojos/restauraciones
reales: HOME **26/42 → 42/42**, contexto del host **1028/1080 → 1080/1080** y salto
de cámara **337/339 → 345/345**. En esta última el salto fue **3,234552 m** y la
restauración NORMAL **0,610015 m**, 117 frames consecutivos sobre 50 ticks.
`tools\godot\runtime\coordinator-gameplay-mutations-936460716aed433c85a1bcb7da91f6de\coordinator-mutation-proof.json`
registra la restauración de sus 94 hashes por caso y los intentos no aceptados.
No sustituye al All final ni atribuye el outlier de 821 s a una causa no demostrada.

El protocolo sigue siendo la misma CLI, 28 casos, 20 momentos y manifiesto.
Cada check adicional debe ser único, booleano y respetar **su transporte real**;
no se sustituye comportamiento por contadores. La huella canónica vincula el
contrato, no un inventario de fuentes ni una aprobación independiente del candidato.
Las fuentes y PS permanecen fuera de este encargo de tres documentos.
El All 196 y el arranque normal posterior completaron las ejecuciones del cierre.
Vasquez aprobó las fuentes, el último oráculo y la estructura del paquete af23.
La publicación local anterior está confirmada; ni ésta ni la revisión técnica
equivalen a una aceptación humana, artística o de FPS.

El consumidor exige ahora también las aserciones reales de rechazo visible y
continuidad del plazo para cada negativa de autoridad de Newt. En el smoke
productivo exige el feedback real de K en meta y de J en la sexta acumulada,
incluida la ayuda persistente. **El constructor actual del smoke no publica
refusals esperados:** hereda `command_rejections` vacío de `match_smoke.gd`.
Sus rechazos contextuales proceden del adaptador, sin enviar el pase/tiro
prohibido a la autoridad. Por tanto, las dos señales de la suite nativa no
se trasladan al smoke ni se inventan campos de expectativa para aceptarlas.

**Historial de preparación PS, no conteos finales:** el pase posterior a aquella
revisión obtuvo **124/124** fixtures del consumidor nativo
y **204/204** del decoder runtime, ambos exit 0. Prueban faltantes/excesos,
actor/código/mensaje/modo incorrectos, feedback omitido, diagnósticos `ERROR` o
`WARNING` indebidamente derivados de señales y aserciones adicionales con/sin
su línea `PASS`. No fijan un total de checks del productor.
Evidencia y testigos originales de los dos procesos PowerShell:
`tools\godot\runtime\gameplay-ready-accounting-cc584cf913c247e38395b68de2c68799\result.json`.
`nativeGameplayValidated=false`; no se ejecutó Godot ni se modificaron fuentes
de juego, binarios o hashes de productores.

Históricamente, el pase PS posterior al contrato aditivo de cámara obtuvo **137/137** fixtures del
consumidor nativo y **218/218** del decoder runtime, ambos exit 0. Incluye
vectores ausentes, mal tipados y no finitos, seguimiento/orientación incoherentes,
balón detrás pese a metadatos concordantes, omisión coordinada del tick 31 y
aceptación de claves adicionales sin fijar el inventario completo.
Evidencia con testigos originales de procesos PowerShell:
`tools\godot\runtime\gameplay-camera-tracking-96cab362688943e2820c76fc1acdd799\result.json`.
El informe mantiene `nativeGameplayValidated=false`; las dieciséis trazas de
Godot y las capturas productivas corresponden a las verificaciones de coordinación.

**G02, finalización HOME por regate:** la guarda usa el origen real del balón y
la velocidad física del regate, incluida la inercia, tanto al aceptar como al
ejecutar el comando; no prohíbe todo regate aliado. Cubre el contraejemplo actor
X=16,9 / balón X=17,45 que antes lanzaba hacia gol a 7,8 m/s, y cambios de
dirección antes del contacto. Mantiene regates legales, finalizaciones del
seleccionado/AWAY/portero y desvíos accidentales. La suite completa tiene
**1522 checks, 74 negativas exactas y 17 grupos**; conserva los 1224 checks
anteriores. `finishing_guards` pasó de 38 a 336; `dribbles` conserva 72.
El lector exige el conjunto completo de grupos, terminación y watchdog sin
pendientes: una selección parcial autoconsistente no vale como full.

**G10, identidades físicas:** se confirmó que
`match_smoke.gd::_restart_evidence` ya serializa `launch_contact_id`. El decoder
runtime conserva la identidad entre lanzamiento, foco, `taken`, snapshot y
manifiesto; no cambia ese recurso congelado. El lector físico valida el entero
original incluso sin segundo contacto. Para `native_second_contact` exige
`contact_id`, `tick`, `actor_id` y `surface: "athlete"` reales y tipados.
La identidad nueva debe ser distinta, no mayor por una supuesta relación con
el reloj; no se infiere un campo ausente ni se aplica tolerancia `t+1`.
Los escenarios de continuidad del lanzamiento del portero y nuevo toque del
sacador son obligatorios en ambos modos, enlazados a sus aserciones nativas
de separación, pausa, indirecto y ausencia de acumulación de falta.

Durante la preparación, la ampliación del consumidor físico superó
**175/175 fixtures PS, exit 0**:
faltantes, sentinelas inválidos, IDs iguales, tipos incorrectos, actor/superficie
ajenos y evidencia sin aserción correspondiente se rechazan. Evidencia:
`tools\godot\runtime\gameplay-g10-identity-ab75327bd1e94bf5b00cb0bcb3aaf11d\result.json`.
Conserva `nativeGameplayValidated=false`. Los totales planificados del core o
las reglas no se publican como resultados nativos observados.

El contrato canónico **§4.3 completo** se leyó, incluidos sus
overrides y el contexto interpolado del atleta. No hubo intento ni denegación
de herramienta sobre el archivo temporal enlazado anteriormente; esa ruta
no es una dependencia pendiente. `gameplay-contract.json` fija las 32 definiciones
de aceptación y los doce valores de `TrainingExercise` contra el documento real,
con SHA-256 de **toda la sección §4.3**, UTF-8, CRLF→LF y trim:
`742ceff7db550b834b42c265265336accdd56e9783f8b6e47c5baf26b9df06a1`.
No se vinculan sólo las tablas ni se modifica `gameplay-contract.json` en este cierre.
Un cambio posterior del contrato falla explícitamente hasta revisarlo; no se
confunde con ausencia del contrato. Los fixtures de DTO cubren colocación mínima
de 60 ticks, plazo de 240 con límite estricto, penalti sin cuenta y decisión
explícita de acumuladas: penalti/indirecto/vencimiento no incrementan.
La proyección reglamentaria conserva Z y modifica X; la extensión solo admite
penalti/DFKSAF. L/X comparte regate/elección contextual. La fuente de Hicks y el
handoff posterior confirman Ctrl + A/D o ←/→ / LT + stick lateral, hasta 30°/s,
solo en `RESTART_AIM` propio: detalle ya confirmado, aunque el texto original
del diseño lo dejase a su implementación. Es funcionalidad de 0.4, no de la copia histórica 0.3.

`Assert-GodotGameplayFoulTuning` consume los campos canónicos de `MatchTuning`,
sin imponer un campo nuevo al JSON de Hicks. El manifiesto coteja sus tipos,
defaults y límites con la tabla publicada: `foul_challenge_window_ticks=18`
(entero 1–60), `foul_min_closing_speed=0.8` (0.1–4.0 m/s) y
`foul_reckless_closing_speed=9.5` (2.0–20.0 m/s, estrictamente mayor que el mínimo).
Rechaza ausencias, booleanos, cadenas numéricas, NaN/infinito, fracciones de tick
y umbrales fuera de rango/invertidos. `-RequireDefaults` distingue una prueba del
inicio normal de un tuning alternativo legal; no convierte el helper en prueba
física ni cambia campos propiedad de Bishop o decisiones de Hudson.

Las aserciones negativas de clasificación pueden producir **cero diagnósticos**:
su polaridad no crea permisos `ERROR`/refusal. Los fixtures comprueban ese caso y
siguen rechazando allowances o errores inesperados aunque los checks sean true.
Ningún total provisional del autor de IA se fija como conteo de la suite 0.4.

`Read-GodotGameplayRuntimeReport`, en `GameplayRuntimeValidation.ps1`, consume el
constructor real, no una adaptación supuesta: `FUTSAL_GAMEPLAY_SMOKE`, alcance
`playable-gameplay-runtime-smoke` y objeto anidado `gameplay`. La única CLI es
**`--gameplay-smoke --report-path=<absoluto>`**, sin `--capture-path`.
El runner lanza cuatro procesos diferenciados: fuente/artefacto ×
headless/renderizado, además de los cuatro recorridos del smoke legado.

El lector exige 28 identidades y orden reales: catorce por modo, con `before`,
`after` y `completion` en los diez momentos capturables. Comprueba arranque normal
0/10/9 **antes de cualquier setup**, seis casos de foco previos y cuatro pases de
saque/meta, intención/IA efectiva, acciones legales y secuencias, eventos completos
vinculados al historial, colocación/plazos, reloj efectivo, pulsación/liberación,
carga y afinado, dirección física del regate y transferencia atómica de pase.
La liberación de Aplicar se registra **antes** de despachar el reset y aún lleva
el tick anterior: solo las entradas posteriores a ese par usan el reloj nuevo.
La regla no permite otro retroceso temporal. Al ocultarse, la guía debe borrar
todos sus metadatos de lanzamiento, además de esconder sus dos mallas.
Coteja cámara real, profundidad/proyección y opciones HOME visibles, guía/ball
renderizado/velocidad, identidad de cada atleta, contexto de snapshot y matrices
de manos/pies, contacto y progresión posterior. No acepta solamente `passed=true`.
G01–G32 se prueban **combinando** suites nativas y runtime: estos 28 casos no son
64 banderas de aceptación ni sustituyen faltas/contactos/táctica del core.

#### Diagnósticos de presentación verificados, con negativas explícitas

Los prefijos leídos en los constructores reales son **`FUTSAL_GESTURE_TESTS`**
y **`FUTSAL_VISUAL_TESTS`**. `Read-GodotPresentationReport` exige checks únicos
y verdaderos, las comprobaciones de finalización y `duplicate_checks` vacío.
Valida `native_errors` de `OS.Logger`: contadores enteros, entradas reales
tipadas, errores de script/shader y warnings a cero.

En gestos coteja, además, `expected_error_counts`,
`observed_expected_error_counts`, cada entrada normal del logger, las dos
aserciones de rechazo/pose por caso y los diagnósticos externos completos.
`Get-GodotGestureExpectedErrors` obtiene ocurrencias de las llamadas literales
`_expect_error` y comprueba el prefijo real de `AthleteView`. El All final cotejó
**12 diagnósticos intencionales** dentro de gestos 190/190; no son el total
de aserciones nativas ni errores inesperados. Enum, NaN/INF, dirección, duración, interpolación, evento
y contexto tienen cobertura mínima explícita; nuevas razones requieren revisión.

`Assert-GodotOutput` conserva una familia **separada y exacta** de errores de
presentación. No admite mensajes cambiados, faltantes/excesos ni una autorización
genérica de `ERROR`. Los errores de carga anteriores a `_initialize` se revisan
en stdout/stderr, incluido `SHADER ERROR`, aunque el logger reporte cero.
Se preservan los errores HUD exactos y el único bloque Vulkan conocido, opt-in;
no se incorpora ninguna excepción Jolt. Visual 230/230 conserva sus checks y
logger limpios; los resultados de fuente se distinguen de los recorridos del EXE.

#### Capturas aisladas por invocación

Se exigen los escenarios del driver en **ambos modos** y veinte contextos gráficos por recorrido
renderizado: cuatro preparaciones de córner, tiro cargado, saque del portero
preparado/liberado y contactos de enganche izquierdo/derecho/cambio de ritmo.
Las identidades reales tienen forma `m0/corner_pos_x_neg_z` y `m1/...`; están
registradas en `runtimeCaseNames`. Los antiguos helpers de normalización de
capturas solo prueban estructuras auxiliares, no son el gate runtime.

Cada ejecución recibe directorios distintos, por ejemplo:

```text
tools\godot\runtime\<run>\gameplay-source-rendered\report.json
tools\godot\runtime\<run>\gameplay-source-rendered\report-gameplay-captures\manifest.json
tools\godot\runtime\<run>\gameplay-artifact-rendered\report.json
tools\godot\runtime\<run>\gameplay-artifact-rendered\report-gameplay-captures\manifest.json
```

Un directorio preexistente se rechaza. Se validan alcance de rutas absolutas,
ausencia de enlaces/reparse points, frescura, SHA-256, decodificación PNG real
**1920×1080** y variación de imagen. No se duplican modo/ejercicio/ruta/hash para
aparentar veinte capturas. Se cotejan los mismos objetos de observación en caso,
manifiesto y registro de imagen, incluido tick, fase, catálogo/esquina, selección,
reanudación y cámara/input. Distingue `PASS` con
`KEEPER_THROW` de tiros con pie, y eventos `DRIBBLE` de enganche/cambio de ritmo,
sin admitir ticks futuros ni actor incorrecto. Exige evento aceptado al liberar
o tocar; no inventa uno durante preparación/carga. Headless conserva veinte
observaciones, pero **cero PNG**, `capture_complete=false` y ninguna aceptación
visual. Renderizado exige veinte archivos distintos y ninguna evidencia extra.
Report/manifest tienen lectura UTF-8 estricta, tamaño acotado y frescura; los
testigos de salida pertenecen a handles originales, nunca a una consulta tardía
del PID ni a una identidad inventada por el JSON.
Ni veinte PNG ni una lista `passed=true` bastan para aprobarlo.

La publicación local en `build\evidence\0.4.0-preview\gameplay` **ya contiene
20 PNG y `manifest.json`**, cotejados y abiertos por coordinación antes de C1/C2.
La copia `build\windows\FutsalPreview-0.4.0.exe` existe con los mismos bytes/hash
af23 de la entrega. El manifiesto publicado y
`tools\godot\runtime\preview-20260914T161724Z-92b1a73a68a944c49b48ddf4d2bf2d52\coordinator-capture-verification.json`
son byte-idénticos y conservan la procedencia del EXE, no de imágenes de fuente.
Los veinte PNG proceden de
`gameplay-artifact-rendered\report-gameplay-captures\manifest.json` del All 191.
Los veinte PNG de cada recorrido gráfico del All 196 permanecen en su propio
directorio de ejecución y no sustituyen la publicación anterior.
**No se vuelve a copiar ni sobrescribir esta publicación.** Este cierre documental
sólo registra el hecho anterior; no añade una operación o aprobación de QA. Los presets
existentes siguen excluyendo tests/probes y conservando los drivers de diagnóstico.
Los smokes fuente/EXE, headless/render, usan **`--fixed-fps 60` sólo como reproducción
diagnóstica**; no acreditan 60 FPS. El arranque normal conserva tiempo real.

```powershell
# Referencia de helpers PS; no ejecutados por esta actualización documental
pwsh -NoProfile -File .\tools\godot\tests\Test-GameplayValidation.ps1
pwsh -NoProfile -File .\tools\godot\tests\Test-PresentationValidation.ps1
pwsh -NoProfile -File .\tools\godot\tests\Test-GameplayRuntimeValidation.ps1
pwsh -NoProfile -File .\tools\godot\tests\Test-GameplayNativeValidation.ps1
pwsh -NoProfile -File .\tools\godot\tests\Test-MicroSliceValidation.ps1
pwsh -NoProfile -File .\tools\godot\tests\Test-ProcessCompletion.ps1

# Objetivos nativos acotados, sujetos a coordinación; no órdenes ejecutadas aquí
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Gameplay
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope GameplayRuntime
```

#### Historial de preparación 0.4, anterior al cierre técnico del 14/9

**Baseline serial previo a la revisión READY: 1014/1014 comprobaciones exclusivamente PowerShell,
las seis suites con exit 0**, después de la vinculación final G10:

| Suite de fixtures/probes PS | Resultado observado |
|---|---:|
| Consumidores de contratos nativos (`Test-GameplayNativeValidation`) | 108/108 |
| Regresiones del lector legado (`Test-MicroSliceValidation`) | 373/373 |
| Contrato/DTO/bindings (`Test-GameplayValidation`) | 181/181 |
| Diagnósticos de presentación (`Test-PresentationValidation`) | 89/89 |
| Procesos PowerShell propios (`Test-ProcessCompletion`) | 66/66 |
| Decoder/rutas runtime (`Test-GameplayRuntimeValidation`) | 197/197 |

Evidencia consolidada, con stdout/stderr íntegros, resultados medidos y testigos
de salida capturados desde cada handle original:
`tools\godot\runtime\gameplay-tooling-final-7d51f524f3454d91a2cced9b4233585d\result.json`.
En el mismo directorio, `integrity.json` registra **21/21 parseos PS** sin ejecutar
sus rutas nativas y **9/9 comprobaciones de preservación**: los tres registros
históricos, cuatro EXE G1/0.2/0.3 y las dos imágenes históricas 0.2/0.3.
En aquel snapshot coincidía su huella canónica y las cinco aceptaciones de 0.4
permanecían false. Es el estado histórico de preparación, no el del candidato actual.

El decoder ejercita cuatro protocolos sintéticos completos con procesos
PowerShell propios reales. Incluye variantes negativas de identidad/handles,
checks/casos, input/foco, frontera temporal de Aplicar, lado del enganche,
cámara/proyección normalizada, volumen del balón, contacto/poses, metadatos de
guía oculta y episodio de lanzamiento. Rechaza PNG faltante, repetido, uniforme,
desfasado o de resolución incorrecta. Los PNG sintéticos se eliminan. El informe
conserva `nativeGameplayValidated=false`: esos 1014 checks no son suites Godot,
ejecuciones productivas, capturas GPU ni aceptación de gameplay.

Historial de preparación, no conteos nativos: los helpers gameplay pasaron antes
84/84, 144/144, 178/178 y 179/179; el decoder pasó 181/181 y después 192/192.
Se conservan los informes anteriores, por ejemplo
`tools\godot\runtime\gameplay-helper-03950cceeeef4188bc295af9f0502974\result.json`
y `tools\godot\runtime\gameplay-runtime-helper-2051c05290374fdcac85794ba3d3af83\result.json`.
La nueva huella canónica se vinculó tras releer §4.3 completo, incluida la
superficie de ayuda/rechazo de saque del HUD; G01–G32 permanecen iguales.
Se releyó de nuevo al publicarse `RestartState.launch_contact_id`: el decoder
exige ahora ese entero también en el constructor real de Hicks y conserva su
identidad en golpeo, foco, `taken` y snapshot posterior. Una preparación no puede
inventar contacto previo; el segundo toque se resuelve por episodio y separación
física, no por una tolerancia fija de ticks.
La guarda rechazó primero **1/2, exit 1**, en
`gameplay-helper-00d5092fb3dc4974ac41311d4b30195c`, sin ocultar el cambio.
La primera comprobación del contrato publicado rechazó **1/2, exit 1** al
cambiar su huella durante la publicación de `sync_context` del atleta:
`gameplay-helper-97bebe96aa3549939a30c6891fd8c9e0\result.json`, bajo el mismo
directorio runtime. Se releyó §4.3 completo y se actualizó la vinculación;
no se deshabilitó la guarda.
En aquel paso ambos EXE 0.3 tenían **103387808 bytes** y SHA-256
`6fe42916e7d91309044758439b96c48324ce967d1597f3f24872ff6dbd9192f6`
sin modificar las imágenes históricas. Hoy esos bytes corresponden a la copia
fija `FutsalPreview-0.3.0.exe`; la ruta compatible `FutsalG1.exe` contiene 0.4.
Se conservan testigos de handles
originales, UTF-8/CP437, límites I/O, nonzero/timeouts,
lock exclusivo, ruta diagnóstica interna del exportado y negativas del default.
La secuencia final sigue siendo de coordinación: probe serial → foundation →
`All` como última exportación → arranque normal del EXE. Coordinación completó
ProcessNative 110, Foundation 915, All 196 y el arranque normal posterior
`coordinator-normal-04-promoted-4de8288e7ced411daeba4443b859fc68`.
El arranque af23 anterior permanece documentado con su propia procedencia;
esta edición no ejecuta estas etapas. La revisión final de Vasquez está cerrada
para fuentes y estructura del paquete, sin conceder los gates de producto.

Archivos de este primer paso: `Common.ps1`, `Test-Godot.ps1`,
`Test-MicroSlice.ps1`, `MicroSliceValidation.ps1`, nuevo
`GameplayValidation.ps1`/`gameplay-contract.json`, `GameplayRuntimeValidation.ps1`;
`GameplayNativeValidation.ps1`;
fixtures `GameplayRuntimeFixtures.ps1`, `Invoke-GameplayFixtureChild.ps1`,
`Test-GameplayRuntimeValidation.ps1`,
`Test-GameplayValidation.ps1`, `Test-MicroSliceValidation.ps1`,
`Test-PresentationValidation.ps1`,
`Test-GameplayNativeValidation.ps1`,
`Test-DefaultEntrypoint.ps1`, `Test-ArchivedPlayerControlReports.ps1`,
`test_input_schema.gd` y `test_match_smoke.gd` bajo `tools\godot\tests`;
`game\bootstrap\bootstrap.gd`, `config\input-schema.json`,
`config\toolchain.json`, README y este documento. No se editaron
`project.godot`, main, drivers de gameplay ni código de los productores.

### Cambio de jugador y pase — 0.3.0 histórica, cerrada y archivada

**Estado: cierre independiente completado; FINAL APPROVE de Vasquez, incluidos
tooling, driver, informes y ejecutable.** App **Futsal — Laboratorio 5v5**, versión
`0.3.0-preview`, input schema **2**. `Assert-GodotProjectConfiguration` comparte
guardas exactas entre lanzador, pipeline y runner; un proyecto 0.2/schema 1 no
se aceptaba ni se sustituía por diagnóstico en esa entrega. Las guardas activas
ya requieren 0.4/schema 3; el cierre actual se documenta por separado y no
hereda las pruebas ni el FINAL APPROVE de esta entrega histórica.

#### Identidad y evidencia final de 0.3.0

- Salida usada entonces: `build\windows\FutsalG1.exe`; el nombre compatible
  ahora contiene **0.4.0**, no la entrega histórica.
- Copia fija: `build\windows\FutsalPreview-0.3.0.exe`.
- Bytes conservados de 0.3.0: **103387808 bytes**, SHA-256
  `6fe42916e7d91309044758439b96c48324ce967d1597f3f24872ff6dbd9192f6`.
- Main `res://match/match.tscn`, preview 10/9/seleccionado inicial 0 y micro
  conservada; intención IA separada de IA efectiva.
- Captura original publicada: `docs\images\player-control-5v5.png`, **1920×1080**,
  **867165 bytes**, SHA-256
  `7f4133e40e18a76431ee60d52487fd18dbf1b5ab6024f743e8dfaa3b6ad9cdf1`.
  Copiada sin cambios desde `artifact-rendered.png` del `All` siguiente; no se
  sobrescribe `docs\images\preview-5v5.png`, que pertenece a 0.2.0.

Cierre ejecutado y verificado independientemente por **coordinación**, no nuevas
ejecuciones nativas de este archivado:

| Etapa | Resultado observado |
|---|---|
| Procesos, incluidos probes nativos | **72/72** |
| Foundation/diagnóstico y pipeline | **819/819**; no es aceptación de gameplay |
| Runner `All` | **125/125**, `ok=true`; 196,082 s de ejecución |
| Fixtures PS / procesos PS dentro de `All` | **344/344 · 66/66** |
| Esquema de input / helpers del driver | **8/8 · 47/47** |
| Core micro / core preview | **335/335 · 545/545** |
| HUD / negativas del default / integración micro | **407/407 · 4/4 · 197/197** |
| Desarrollo / integración preview / control de jugador | **377/377 · 160/160 · 343/343** |
| Visual nativo | **197/197** |
| Main fuente headless / Vulkan | **200/200 · 205/205** |
| Ejecutable headless / Vulkan | **211/211 · 216/216** |

Son conteos archivados, **no expectativas estáticas para 0.4**. Fuente y ejecutable
renderizados usaron **NVIDIA RTX 2000 Ada Generation Laptop GPU**, Forward+/Vulkan,
con PNG 1080p. No se deducen FPS de los tests ni del tiempo total.

Evidencia:

- Procesos: `tools\godot\runtime\process-native-final-coordinator-20260910.log`.
- Foundation: `tools\godot\runtime\20260910T125019Z-992355bdb1854f9299c9c326d2b49ad9\result.json`.
- `All`: `tools\godot\runtime\preview-20260910T125136Z-e1c673eea36d4d7da851107ec822dfa1\result.json`.
- Arranque normal: `tools\godot\runtime\control-normal-candidate-20260910\`.
  Coordinación observó el **objeto `Process` original terminado, exit 0**, sin
  diagnóstico ni smoke. Su `stderr.log` tiene **0 bytes** y el stdout archivado
  identifica el mismo renderer/GPU, sin marcador de smoke.

Ferro comprobó en este paso los manifests y los bytes de binarios/PNG, sin volver
a ejecutar Godot, GUI, exportaciones o tests nativos. El cierre **0.3.0** se conserva
ahora en `playerControlValidation`, con enlace a la copia fija; `previousPreviewValidation`
continúa siendo **0.2.0** y `g1Validation` permanece intacto. La preparación anterior
se conserva en `preparationHistory`, no se reescribe como un éxito retrospectivo.

**Límites y diagnósticos:** runtime y GPU están verificados; aceptación humana,
arte final y FPS continúan **false**. Los renders finales registraron el bloque
Vulkan de loader permitido expresamente; no se califican todos los logs como
stderr limpio. La observación transitoria de QA sobre el **límite de jobs de Jolt
sigue siendo incierta**: no se le asigna una causa/reproducción no demostrada ni
se permite como advertencia genérica. Las políticas estrictas no cambian.

#### Historial de preparación y correcciones de 0.3.0

El ejecutable anterior está preservado por coordinación en
`build\windows\FutsalPreview-0.2.0.exe`, **103371984 bytes**, SHA-256
`a728d5f961b80db4a1f0ea56a8547481044f323d017cd3b9fb32522edb132176`.
`previousPreviewValidation` conserva todos sus resultados y aprobación, añade
`historical=true` y el enlace a esa copia. `g1Validation` no cambia.
Durante la preparación, `previewValidation` estuvo **pendiente 0.3.0**, con
runtime/GPU/humano/arte/FPS en false y sin reutilizar resultados anteriores. La
salida activa no se alteró hasta el cierre de coordinación documentado arriba.

Los fallos intermedios permanecen como historial, no como permisos para diluir
los checks: etiquetas repetidas de core/preview, corregidas por **Newt** con
contextos reales; evidencia de negativas inicialmente **41/93**, completada por
Newt hasta **93** casos (91 retornos reales de API y dos diferidos; 51
notificaciones y 42 retornos reentrantes sin notificación); los **cinco** nombres
duplicados del driver, corregidos por coordinación mediante propósito explícito
en cada transición; y la agregación **98/99** por consulta tardía de PID,
corregida mediante handles/testigos originales. Sus resultados anteriores no se
borran ni se convierten en verdes inventados.

#### Contrato y cobertura exigida

- J/A sin balón selecciona HOME cercano al controlado, desempate por ID; con
  dirección, cono de 35°. El portero es elegible, también en micro `0↔2`.
- Con posesión, J/A pasa y transfiere foco al receptor de la **patada aceptada**,
  con balón aún libre; no basta una orden encolada, un pase fallido o una intercepción.
- Flechas/WASD/stick se muestrean al construir el comando. Movimiento/sprint no
  se detienen por cambiar foco; carga/pulsaciones no migran. Mantener/echo no
  repite. Las barreras de pausa/foco/desconexión siguen siendo estrictas.
- `selected_actor_id` identifica el único HOME humano; `HUMAN_ID=0` solo indica
  identidad/default. El inicio previo a drills sigue exigiendo **0, diez cuerpos
  y nueve IA efectivas**, antes de cualquier start del driver.
- `ai_intent_actor_ids` conserva preferencias completas; `ai_actor_ids` es
  intención menos seleccionado. Defaults `[0..9]` / `[0..3]`; el seleccionado
  puede figurar como preferencia latente. `[]` sigue apagado al cambiar foco;
  deseleccionar nunca habilita una IA ausente de intención.
- Desarrollo incluye campo local `[0]` en micro y `[0,4,6,8]` en preview: ya no
  es «no aplica». Reinicio/saques conservan intención y vuelven a seleccionado 0;
  pausa, pausa de gol y fin conservan el foco durante esa fase.
- Conservar los drills anteriores, añadiendo pase manual a portero/devolución,
  portero IA fuera de foco, todo apagado, secuencias crecientes, movimiento
  continuo y HUD/identidad reales. Un recuento de nodos no prueba estas conductas.

`game\tests\test_match_player_control.gd` y su marcador
**`FUTSAL_PLAYER_CONTROL_TESTS`** son obligatorios tanto en `Components` como
en `All`; no existe un skip aprobado. Los totales se leen del informe nativo,
con tipos/errores estrictos, nunca se anticipan. Las listas actor/humano de los
fixtures PowerShell y GDScript ahora dependen del seleccionado, incluidos ambos
porteros y la IA efectiva.

El informe nativo de esa suite ya tiene consumidor preparado contra su fuente:
`complete=true`, F01–F12 en orden, versión/schema exactos, eventos reales de
teclado/mando/ratón, errores inesperados vacíos y negativas identificadas por
código/actor/mensaje del core. Sus eventos de foco deben cubrir ambos modos,
pase a portero y devolución manual, cambio sin balón e intención vacía; el pase
aceptado no concede posesión al transferir. **La primera comprobación aquí
descrita validó fixtures del consumidor; la ejecución independiente final de
343/343 está identificada arriba.** El contador de rechazos del core se coteja
con sus líneas nativas `PASS expected refusal:`, no con el 27 histórico.

**Esquema consolidado integrado:** `Read-GodotGameReport` exige identidad,
default/modos/IA/PNG y `Assert-GodotFocusChangesReport`. Ya no existe la parada
incondicional por esquema pendiente. Todos los fixtures de juego, incluidos los
de cabecera Vulkan/PNG, pasan por ese lector completo, no por el lector base.
La nueva suite nativa y las siguientes seis pruebas del driver son obligatorias:

| Caso exacto del driver | Modo | Selección | Entrada real |
|---|---|---|---|
| `preview_off_ball_neutral` | Preview | 0 → 4 | J |
| `preview_off_ball_directional` | Preview | 0 → 8 | J y flecha izquierda en el mismo frame |
| `preview_pass_field` | Preview | 0 → 4 | A |
| `micro_pass_keeper` | Micro | 0 → 2 | J |
| `micro_keeper_manual_return` | Micro | 2 → 0 | A |
| `micro_keeper_ai_return` | Micro | 0 → 0 | Portero autónomo, sin pulsación humana |

Se cotejan snapshots tipados, intención/IA efectiva, dueño del balón, secuencias
**por actor**, clock a 60 Hz y ausencia de nuevos starts dentro de cada recorrido.
Los eventos deben coincidir con la ventana completa del historial de producción:
no basta copiar dos eventos y omitir un cambio de foco. El pase humano exige
PASS seguido de FOCUS_CHANGED en el mismo frame, balón todavía libre, vuelo y
recepción física posterior, sin perder el foco del receptor. El portero
controlado retiene posesión los 45 ticks que exige la prueba antes de su pase
manual; la devolución IA no puede transferir foco. Se comprueban movimiento
inmediato del nuevo seleccionado, flechas, parada al liberar y restauración final
a preview 10/9/seleccionado 0. El informe de la suite nativa usa su propio esquema
de eventos, distinto de estos seis registros de runtime.

El mapa de desarrollo usa el mensaje real nuevo del core
`AI intent IDs must be unique active actors`. Sus ocho casos de advertencia/seis
rechazos se derivan de una lista cerrada de negativas, con texto/código exactos
independientes del autoreporte. Una etiqueta y un mensaje inventados que coincidan
entre sí no se autoautorizan. Un test que aún trate `[0]` como intención inválida
queda como dependencia de productor: debe usar un ID desconocido/inactivo.
PlayerControl exige las **siete** negativas reales, en orden y con su actor exacto
(incluido ID 8 en la reentrada F08). El HUD requiere **22** diagnósticos: los 16
anteriores más seis líneas exactamente
`ERROR: MatchHUD.set_selected_actor: se requiere identidad válida y control humano de un actor local.`
El contador JSON también debe ser entero y coincidir con esa política. Faltantes,
excesos, variantes de texto, otras advertencias/errores o exit no cero fallan.
Permanecen UTF-8 reader/writer y el probe CP437, watchdog,
informe incompleto fallido, lock/PID propios y la excepción opt-in de **un único**
bloque Vulkan; no supresión genérica.

#### Comandos y resultado de preparación

Historial operativo de 0.3.0; este paso de archivado no ejecuta estos comandos
ni autoriza adelantar las validaciones de 0.4 sin su contrato.

```powershell
# Permitido en preparación: fixtures PS, tipos, metadatos, parsing y UTF-8
pwsh -NoProfile -File .\tools\godot\tests\Test-MicroSliceValidation.ps1
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Helpers

# Solo relee JSON/log originales; NO lanza Godot ni acredita una ejecución nueva
# El archivo original de Hicks descrito abajo provoca exit 1, no un verde normalizado
pwsh -NoProfile -File .\tools\godot\tests\Test-ArchivedPlayerControlReports.ps1

# Helper aislado: añade/restaura flechas solo en el InputMap de este proceso
# No ejecutarlo si otra validación posee tools\godot\runtime\test.lock
. .\tools\godot\Common.ps1
$godot = Get-GodotInstallation
& $godot.consolePath --headless --path .\game --audio-driver Dummy --fixed-fps 60 `
  --script "$PWD\tools\godot\tests\test_input_schema.gd"

# Reservados a coordinación, después de recibir/integrar los contratos finales
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Components
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope All -AllowKnownVulkanLayerWarning
```

Primera fase de esta preparación: baseline PowerShell **147/147**; después,
**215/215**, incluida autovalidación del informe y probes UTF-8/CP437. La
autovalidación detectó un bloque nuevo ejecutado dos veces; se corrigió su alcance,
sin aceptar nombres duplicados ni inflar el total. Evidencia de esa fase:
`tools\godot\runtime\control-preparation-37ccebd248934a239e33f1d0cb5ecb48\`.

**Cierre de consumidores consolidado, observado por Ferro:**

| Comprobación ejecutada | Resultado |
|---|---|
| Fixtures PowerShell completos | **344/344**, exit 0; 21,536 s de etapa |
| Runner `Helpers` | **2/2**, exit 0 |
| Helper headless de esquema | **8/8**, 176 despachos, exit 0 |
| Helper headless de snapshots/driver | **47/47**, exit 0 |
| Parse nativo de ambos helpers | Sin errores, exit 0 |
| Cierre incompleto deliberado del helper | **0/1**, `ok=false`, exit **1** esperado |

Los helpers no instancian el main. La prueba de esquema modifica/restaura solo su
InputMap local. Las negativas PS cubren metadatos, defaults previos a cualquier
setup, omisión/reordenación de eventos, foco/posesión prematuros, IA latente,
secuencias/clock, vuelo/recepción, portero manual/IA y errores exactos. Un fallo I/O
de fixture no cuenta como negativa aprobada; las violaciones de compartición de
Windows al reemplazar esos archivos tienen reintentos acotados.

Evidencia final:

- PS/runner: `tools\godot\runtime\preview-20260910T104452Z-7e6e65de0a514904b808a12583d986d0\result.json`.
- Helpers: `tools\godot\runtime\control-isolated-f1ad495aa9d1411f97b9ff4a8e159bc7\result.json`.
- Relectura original: `tools\godot\runtime\control-archive-consumers-7cd5c6352e134903bb554a74141b55f3\result.json`.

**Defecto concreto del informe de Hicks, sin modificar su código ni evidencia:**
la relectura de `.validation\hicks-player-control\` acepta los informes
PreviewIntegration **160/160** (ocho advertencias/seis rechazos exactos) y
PlayerControl **343/343** (siete rechazos exactos). Son conteos del archivo del
autor, **no suites nativas ejecutadas de nuevo por Ferro**. El lector de producción
rechaza `match-smoke.json`/`.log`, aunque declaran 200/200: contienen **200 entradas
pero solo 195 nombres únicos**. Cada uno de estos cinco nombres aparece dos veces,
con el prefijo común exacto `development mode 1 `:

- `pause exposes the real HUD`
- `visible Desarrollo button exists`
- `native Enter opens development without resuming`
- `real signal starts exact mode with default AI`
- `visible HUD mirrors authority`

En aquel driver el contexto se generaba en `match_smoke.gd::_change_mode`; el
recorrido lo invocaba dos veces para preview. No se renombraron ni descartaron entradas en los archivos
originales para fabricar un verde. Los subcontratos de default/modos/IA/foco de
ese JSON sí superan su comprobación semántica separada, pero **no anulan el rechazo
del informe completo**. La relectura termina **6/7, exit 1**; comprueba SHA-256 de
los seis JSON/log antes/después. Usa timestamp/PID/exit históricos declarados:
no acredita frescura de una nueva ejecución, PID vivo ni salida nativa observada.

En aquel cierre, la validación conjunta quedaba pendiente de coordinación y de
corregir el informe del productor. En ese encargo no se ejecutaron el main, suites de autores,
GUI, exports, All/Components ni instaladores. Ambos ejecutables 0.2.0, activo y
preservado, se reconfirmaron byte-idénticos con el hash/tamaño de arriba.

La primera ruta exportada sigue siendo `-- --diagnostic-bootstrap`; las plantillas
oficiales no admiten reemplazar el main con una ruta CLI. El editor conserva el
bootstrap explícito. Exclusiones PCK, GPU/cabecera real, PNG 1080p fresco,
modo PLAYING sin modal, identidad de ejecutable y versión siguen exigidos.
No se añaden XP, red, dificultades ni aprobaciones de producto.

#### Corrección de agregación por identidad de proceso — 10/9

Coordinación corrigió posteriormente los contextos duplicados del driver y
verificó las etapas nativas, fuente y ejecutable. Su `All`
`preview-20260910T110805Z-dbf951cfbb96483992aaab79fb2b4296` terminó **98/99**
por la consulta tardía `Get-Process` del PID de un parse ya terminado, no por una
prueba de juego fallida. No se atribuye ese caso a una reutilización concreta de PID.

`Common.ps1` conserva ahora el handle original del lanzador y los de sus hijos
verificados. La enumeración rápida proporciona candidatos; padre, ejecutable y
creación se comprueban sobre el handle abierto. Antes de liberarlo se espera su
señal real de salida y se captura un testigo inmutable con PID, padre, creación,
salida y exit code. `HasExited`/disponibilidad del exit code no sustituyen esa
espera. No se consultan ni detienen PIDs históricos al agregar resultados.

Ambos runners agregan esos testigos; el runner de negativas del default también
comprueba el hijo observado, sin consultas tardías al PID de su JSON.
`RuntimeProcessIds` sigue identificando los
procesos que generaron los informes; el lector del bootstrap exige que su PID
corresponda a un runtime realmente observado. Un PID del JSON no crea propiedad,
y faltantes, arrays vacíos o identidades discordantes fallan. Nonzero y timeout
siguen fallando; su evidencia de cierre procede de los handles propios, también
si el hijo sobrevive al lanzador. Se conservan limpieza del árbol propio, UTF-8,
CP437, locks y todas las políticas de diagnósticos.

```powershell
# Solo procesos de prueba propios y probes Godot headless, nunca el main
pwsh -NoProfile -File .\tools\godot\tests\Test-ProcessCompletion.ps1 -NativeProbe

# Incluye los nuevos tests de procesos PS y comprueba la agregación real del runner
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Helpers
```

Observado en el cierre de Ferro: **72/72** con probes nativos, exit 0; `Helpers`
**5/5**, con fixtures **344/344** y procesos PS **66/66**, exit 0. Se probaron
handles vivos/terminados, discrepancia de PID/creación/padre, procesos ajenos a la
invocación que permanecen vivos, nonzero, timeout del árbol, hijo superviviente,
PID falso/ausente del bootstrap, UTF-8/CP437 y Godot de salida inmediata.

- Probes: `tools\godot\runtime\process-completion-84f6d935454f4f4c9de34dace2eed59a\result.json`.
- Agregación: `tools\godot\runtime\preview-20260910T124301Z-8b692fc1e346497d91be06243d1cf994\result.json`.

Un intento de `Helpers` rechazó un error I/O de un fixture con sección mapeada;
no se contó como éxito ni se cambió su política de errores. La repetición acotada,
sin retoques, produjo el resultado final anterior.

No se ejecutaron foundation, las cuatro escenas negativas del default, `All`, GUI
ni exportaciones en esta corrección, ni se
modificaron fuentes/recursos del juego o ejecutables. Quedó pendiente el cierre
de coordinación, que después repitió foundation **819/819** y `All` **125/125**
como última exportadora, con la identidad final documentada arriba.

### Preview 0.2.0 — validación histórica del 10/9

**La sección siguiente conserva la ejecución aprobada 0.2.0.** Los comandos
con esos mismos nombres validan los contratos 0.4 de arriba. Sus conteos,
capturas y A/B de parqué no acreditan el cambio de control ni son expectativas
estáticas de la nueva versión.

**Estado: integración, fuente, ejecutable y GPU comprobados por coordinación;
revisión técnica final aprobada por Vasquez, sin bloqueantes.** Se ejecutó también el artefacto
normal, sin diagnóstico ni smoke. No acredita aceptación humana del juego/sprint,
arte final ni FPS. El A/B continuo independiente del parqué y sus límites están
en `docs\ART_DIRECTION.md`; la captura de aquella versión sin retoques es
`docs\images\preview-5v5.png`.

Metadatos de aquella ejecución: **Futsal — Laboratorio 5v5**, `0.2.0-preview`; main fijo
`res://match/match.tscn`. La salida conserva `build\windows\FutsalG1.exe` por
compatibilidad, con PCK debug embebido. Contenía la preview validada.
`build\windows\FutsalG1-20260909.exe` preserva el G1 anterior; su aprobación/hash
y los 639 checks de preparación permanecen históricos en `toolchain.json`.
`previousPreviewValidation` conserva esta ejecución, separada de `g1Validation`
y del cierre independiente 0.3.0.

Comandos de aquella validación (las guardas activas actuales requieren 0.4.0):

```powershell
# Solo fixtures PowerShell y parsing; no arranca Godot ni depende del menú
pwsh -NoProfile -File .\tools\godot\tests\Test-MicroSliceValidation.ps1

# Alternativa con lock/resumen del runner: únicamente esos helpers PowerShell
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Helpers

# Componentes y guards nativos headless
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Components

# SOLO para coordinación sobre el árbol estable: fuente + exe, headless + Vulkan
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope All -AllowKnownVulkanLayerWarning
```

`Helpers` y `Components` no exportan ni abren ventanas y nunca marcan
`gameplayValidated=true`. `All` conserva el lock compartido `runtime\test.lock`,
la propiedad de PID, templates fijados, informes nuevos, errores estrictos,
cabecera Vulkan/GPU real y PNG 1920×1080. El único warning opt-in sigue siendo
**un bloque completo** del loader descrito en la sección histórica: no equivale
a stderr limpio ni permite otros warnings. El mapa HUD sigue admitiendo solo sus
diagnósticos exactos. Solo la etapa `preview-integration` admite sus ocho warnings
de desarrollo previstos, con texto y multiplicidad exactos; además se cotejan
ocho errores UI y seis rechazos de autoridad etiquetados en el JSON. Cualquier
otra negativa intencionada exige ampliar explícitamente el contrato y probarlo,
no suprimir diagnósticos.

Dependencias de `Components`/`All`, sin saltos silenciosos:

- `game\tests\test_match_preview.gd` — marcador observado en fuente
  `FUTSAL_PREVIEW_TESTS`.
- `game\tests\test_match_dev_menu.gd` — `FUTSAL_DEV_MENU_TESTS`.
- `game\tests\test_match_preview_integration.gd` —
  `FUTSAL_MATCH_PREVIEW_INTEGRATION_TESTS`.
- Panel real `game\match\presentation\development\match_dev_menu.gd/.tscn`,
  conectado al host y con entrada F1.
- Cobertura visual de Lambert: `game\tests\test_match_visuals.gd` emite
  `FUTSAL_VISUAL_TESTS`, **39/39** comprobaciones nativas. No mide estabilidad
  temporal ni FPS. El replay continuo y su análisis están separados en
  `tools\godot\runtime\motion-independent-f4a3783e-20260910\`.

Los marcadores nuevos se leen del `print("FUTSAL_*_TESTS " ...)` literal del test;
se exige una sola línea JSON coherente y salida/diagnósticos nativos válidos.
Sus totales se toman del resultado real, nunca de 315/322/180 históricos. Los
tests anteriores de core, HUD e integración siguen incluidos. Los recursos bajo
`tests`, probes y `match/validation.png` continúan excluidos del PCK; el driver
`diagnostics/match_smoke.gd` permanece exportable.

#### Contrato del humo preview

El hook existente no cambia: `run(simulation: Simulation, hud: Hud) -> void`,
después del arranque normal y de `add_child`, solo con `--smoke-test`. Conserva
`--report-path=<absoluta>` y `--capture-path=<absoluta>` y watchdog de 60 s.

Antes de **cualquier** setup del driver exige el main real ya PLAYING en modo
`PREVIEW_5V5=1`: diez actores/cuerpos `0..9`, nueve IA, roles/equipos correctos,
cámara activa, avance natural de tick/reloj/comando y movimiento/liberación D
físico dispositivo 0 con HUD sincronizado. El micro de cuatro actores **no es
intercambiable**: un default micro falla antes de cero starts, igual que READY,
ticks detenidos o input roto.

Después verifica **preview → micro → preview**, restaurando la IA canónica
al aplicar cada modo. La última transición parte del drill micro con IA apagada;
no debe reactivarla implícitamente antes de aplicar el preset.
En ambos modos abre Desarrollo por el botón real enfocado e Intro, recorre las
conexiones del panel mediante sus señales públicas `mode_requested` /
`ai_actor_ids_requested`, y observa cambios efectivos de autoridad/HUD. No
presenta esa inyección de señales como prueba física de checkbox/selector; esa
cobertura pertenece a los tests nativos UI/integración. Esc vuelve a pausa y
Start reanuda. Desactivar/reactivar IA debe conservar cuerpos, reloj, puntuación
y secuencias durante el cambio, detener/reanudar comandos reales al volver a
PLAYING y conservar modo/IA al reiniciar desde el HUD.

Los drills existentes de movimiento, pausa, gol físico y reinicio se mantienen
en micro. Gol/reinicio preservan la IA desactivada de ese drill. La vista final
debe volver a **diez actores, modo preview y PLAYING**,
con cámara activa, sin modal y etiqueta visible «5v5 experimental». La comprobación
se repite tras `frame_post_draw` para la captura. Headless siempre informa
`gpu_validated=false`. `FUTSAL_MATCH_SMOKE` cambia de alcance a
`playable-preview-runtime-smoke`, con evidencias cuantitativas `default_entrypoint`,
`mode_changes`, `ai_changes` y `final_state`. El lector rechaza informes G1,
cuatro actores disfrazados de preview, secuencias falsas, reloj reiniciado por
toggle, identidad incorrecta, JSON antiguo y PNG/cabecera GPU inconsistentes.

El diagnóstico exportado **conserva la primera ruta in-app**
`-- --diagnostic-bootstrap --smoke-test ...`. No se intenta sustituir la escena
principal por un argumento posicional en templates oficiales. El editor sí
puede abrir explícitamente `res://bootstrap/bootstrap.tscn`.

#### Resultado independiente y artefacto

Último `All` de **0.2.0**: **118/118**, `ok=true`, en
`tools\godot\runtime\preview-20260910T080153Z-386a79887413473b86fff78ff917dbda\result.json`.

| Ejecución real | Comprobaciones correctas |
|---|---:|
| Fuente headless / Vulkan | 150 / 155 |
| Ejecutable headless / Vulkan | 160 / 165 |
| Simulación G1 / preview | 322 / 250 |
| HUD / Desarrollo | 324 / 210 |
| Integración G1 / preview | 183 / 159 |
| Visual nativo | 39 |
| Helpers PowerShell / driver / defaults negativos | 147 / 42 / 4 |

Cada número es el total sin fallos de su ejecución, no un conjunto de casos únicos
sumable. Los cuatro defaults defectuosos fallan antes de cualquier start del driver.
La primera preparación autoemitió 124 checks pero el lector agregado rechazó
identidades duplicadas; ese resultado no se aceptó como verde. Los helpers actuales
validan también su propia salida mediante el lector de producción.

Se corrigieron además lectura **y escritura UTF-8** de procesos PowerShell/Godot,
con regresión reproducible desde un caller CP437; el mapa exacto de warnings/rechazos;
y el estado IA vacío real del drill micro, sin convertirlo accidentalmente en `$null`
por desenrollado de arrays de PowerShell. No se relajaron las validaciones de
identidad, tiempo, comandos, errores, PNG ni GPU.

Antes del último All se repitió la preservación del bootstrap/pipeline:
**703/703**, en
`tools\godot\runtime\20260910T080042Z-47a183dc86cc46b2a13360ffff4de919\result.json`.
Esa suite también exporta la misma ruta; por eso **All se ejecutó después**.
El ejecutable final se volvió a abrir normalmente con salida 0 y sin markers
de diagnóstico/smoke; logs `normal-launch.*` dentro del último runtime preview.

- Artefacto: `build\windows\FutsalG1.exe`, **103 371 984 bytes**.
- SHA-256: `a728d5f961b80db4a1f0ea56a8547481044f323d017cd3b9fb32522edb132176`.
- Renderer: Vulkan/Forward+, NVIDIA RTX 2000 Ada Generation Laptop GPU,
  captura nativa 1920×1080. Esto no certifica 60 FPS.
- PNG publicado idéntico a `artifact-rendered.png` del último All:
  SHA-256 `24998be00725ba3fb6365e6cfce5f5d04d5bbc244713e4554b752019e20b96fb`.

Las ejecuciones fallidas conservan sus propios resultados en `runtime`;
`runtime\preview-result.json` apunta al último resumen, sin sobrescribir `g1-*`.
Revisar el PNG real y los bloques crudos de warning además del JSON.

### Un comando para componentes, main real y ejecutable G1 — histórico 9/9

**La descripción y los conteos siguientes documentan el G1 aprobado del 9/9.**
Los mismos nombres de scripts usan ahora los contratos preview de la sección
anterior; no ejecutar sus comandos suponiendo los viejos conteos/composiciones.

Con la integración y el hook opt-in del main terminados, cerrar previamente
cualquier editor de **este proyecto** y ejecutar:

```powershell
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -AllowKnownVulkanLayerWarning
```

Este comando incluye validadores de informes, helpers del driver, parse nativo de
**todos** los GDScript, simulación, HUD, integración y cuatro arranques del **main
real**: fuente y `.exe`, cada uno headless y con Vulkan/Forward+ a 1920×1080.
El flag admite exclusivamente el bloque de advertencia de registro Vulkan
documentado abajo; omitirlo activa rechazo estricto de cualquier warning.
No actualiza ni ejecuta instaladores, no modifica inventarios y no toca MCP.

La ejecución de componentes ya es independiente del main:

```powershell
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -Scope Components
```

Ese modo valida los dos tests nativos y sus preloads, el driver y los helpers;
**no** exporta, no abre ventanas y registra `gameplayValidated=false`. Si faltan
`match.tscn`, su integración o el hook del driver, `All` termina con un bloqueo
explícito antes de lanzar el juego: no espera en bucle y no usa una escena falsa.
El runner comparte `runtime\test.lock` con el diagnóstico/pipeline.

Cada ejecución genera `tools\godot\runtime\g1-<fecha>-<guid>\result.json`;
`g1-result.json` conserva el resumen más reciente, también si falla. Los informes
de humo se exigen en rutas absolutas inexistentes antes del arranque y con fecha
posterior a él. Se cotejan archivo y única línea `FUTSAL_MATCH_SMOKE`, booleanos,
conteos/identidades de checks, PID observado, versión, escena, modo y ejecutable.
El launcher console y su hijo Godot se distinguen por PID y ruta verificada;
el `.exe` debe informar `editor_binary=false` y su propia ruta. No se acepta JSON
viejo, `ok` textual, informes duplicados ni un bootstrap renombrado como partido.

`test_match_simulation.gd` informa `FUTSAL_MATCH_TESTS`;
`test_match_hud.gd`, `FUTSAL_HUD_TESTS`; el runner espera
`FUTSAL_MATCH_INTEGRATION_TESTS` de `test_match_integration.gd`. También exige sus
arrays de errores/rechazos vacíos y eventos nativos de teclado, ejes y botones.
Las matrices físicas
de 24 contactos y 50 tiros son subconjuntos de la batería de simulación.
`--fixed-fps 60` se usa en las baterías nativas para acelerar pasos de 1/60 s:
**no son FPS renderizados**. Los arranques de humo del main no usan esa aceleración.

El test HUD provoca deliberadamente **16 errores de validación**. Solo en esa
etapa se admiten líneas completas exactas: `update_score` ×2, `update_clock` ×3,
`set_shot_charge` ×3, `home_color` ×1, `away_dorsal` ×1, `show_event` ×4 y
`show_result` ×2. Se cotejan contra stdout/stderr y el contador del informe.
Un mensaje distinto, uno extra/ausente, un error de script/parse, salida no cero
o warning inesperado bloquea la suite. El main normal no admite errores ni
rechazos de comandos; no basta con que un JSON diga `ok=true`.

#### Hook del driver y alcance de sus pruebas

El host añade el driver **después de iniciar sus componentes reales**, únicamente
al recibir `--smoke-test`. No precarga el main desde el driver ni fabrica otra
autoridad/HUD:

```gdscript
if OS.get_cmdline_user_args().has("--smoke-test"):
	var smoke_script: GDScript = load("res://diagnostics/match_smoke.gd") as GDScript
	var smoke: Node = smoke_script.new() as Node
	add_child(smoke)
	smoke.call(&"run", _simulation, _hud)
```

Contrato público de `game\diagnostics\match_smoke.gd`:
`run(simulation: Simulation, hud: Hud) -> void`, con ambos tipos precargados por
ruta. El nodo usa `PROCESS_MODE_ALWAYS`, aplaza el trabajo hasta que el main sea
`current_scene` y tiene watchdog de **60 s reales**; sin `run` permanece inactivo.

Comprueba la escena/configuración real, pertenencia y tipos de autoridad/HUD,
cuatro cuerpos/IDs/roles, comandos de las tres IA por defecto y cámara activa.
**Antes de cualquier start/reset/drill del driver**, exige que el host normal ya
esté en PLAYING, observa avance natural de ticks, reloj y secuencia humana, e
inyecta D físico del dispositivo 0: el actor debe moverse y frenar al soltar
mientras continúan los comandos y el HUD refleja la autoridad. Un fallo termina
la prueba con **cero starts del driver**; ningún setup puede rescatar un arranque
normal roto. `default_entrypoint` conserva los tres snapshots de evidencia y los
contadores; el lector exige además el movimiento/liberación anteriores al primer
start. La misma condición se aplica a fuente y `.exe`, headless y Vulkan.
Inyecta `InputEventKey` físicos D/W y liberaciones, ejes y botones
`InputEventJoypadMotion/Button` del dispositivo 0. Tras comprobar el arranque
normal con las tres IA, aísla el recorrido de input mediante un `MatchSetup`
sin IA activa para que una pausa por gol no contamine la medición. Observa desplazamiento,
velocidad y secuencia en snapshots reales, no solo `Input.is_action_pressed`.
Verifica pausa/reanudación Esc/Start desde el HUD, reloj/cuerpos/rotación del balón
congelados, gol físico con un `MatchSetup` legal y reinicio mediante
Esc/Abajo/Intro. No escribe campos privados ni emite goles falsos. Pase/carga/tiro,
controles restantes y resultado terminal se amplían en la integración nativa.

Regresiones negativas del guard, incluidas en `All` y repetibles aisladamente:

```powershell
pwsh -NoProfile -File .\tools\godot\tests\Test-DefaultEntrypoint.ps1
```

Las tres fixtures instancian el main real únicamente para probar **rechazos**:
autoridad READY, PLAYING sin ticks y un binding D roto que se repararía solo al
recibir un reinicio real. Cambian únicamente estado/bindings de su propio proceso;
no editan producción, no emiten señales de gol ficticias y no cuentan como prueba
del arranque predeterminado. Cada una debe terminar con salida 1, el fallo esperado
y `driver_start_calls=0`. Los recorridos positivos de fuente/exportación usan el
entrypoint predeterminado, sin `--script` ni fábrica de escenas.

La captura sale de `ViewportTexture.get_image()` tras `frame_post_draw`, en
**PLAYING**, sin modal, con imagen no uniforme de 1920×1080. Headless rechaza
capturas y deja `gpu_validated=false`. Fuente y exportación deben declarar la
misma GPU, coherente con el arranque Vulkan nativo; se conservan PNG, logs,
inventario de drivers Windows y SHA-256 del build. Esto es despacho automático,
**no** mando físico, latencia mando-a-píxel, game feel, referencia aprobada o
1080p60 sostenido.

#### Evidencia de implementación observada

**Snapshot histórico de componentes, anterior a la ampliación de pruebas de
resume.** Ejecución del propietario de tooling, no aprobación QA independiente:

| Componente | Resultado observado |
| --- | --- |
| Validador PowerShell (errores, informes, PNG y negativos) | **61/61**, 1,243 s de proceso |
| Helpers nativos del driver | **17/17**, 0,424 s de proceso |
| Simulación nativa | **315/315**, 24/24 contactos, 50/50 tiros, 27 negativas intencionales; 2,773 s de proceso |
| HUD nativo | **275/275**, exactamente 16 diagnósticos permitidos; 0,367 s de proceso |
| Runner de componentes | **19/19**, 6,140 s totales; sin GPU/exportación |

Informe:
`tools\godot\runtime\g1-20260909T174843Z-a70bb10c2b75421fbc1065953f40b3ae\result.json`.
Los conteos de cada fila se mantienen separados; no son un nuevo total fijo.
La ejecución anterior con 53 checks de validadores se conserva en
`g1-20260909T173717Z-2ee21c7e3cb649498ea78f51f8def1e4`. Los ocho casos nuevos
cubren headers/dimensiones/frescura de PNG y coherencia con el arranque nativo:
la GPU se coteja **solo con la línea de arranque Vulkan**, no con otra aparición
de su nombre dentro del propio JSON. Las imágenes de esos unit tests son
fixtures de header, no capturas ni evidencia GPU.
El guard adicional rechazó un anfitrión nulo con salida 1 y un único fallo de
check deliberado, sin errores de motor:
`tools\godot\runtime\g1-guard-4e25356ab3ad42bd8214603513b7c684\guard.json`.

La comprobación posterior de los archivos propios confirmó el parse de los dos
scripts del diagnóstico (**2/2**) y su arranque headless explícito (**91/91**),
con main G1 aún configurado. Los helpers nativos repitieron **17/17**; además se
observó el launcher PID **43996** y su hijo de motor PID **40972**, con la ruta del
binario verificado. Evidencia:
`tools\godot\runtime\g1-owned-final-9ed19c83c64f4f63bd8149f5c1aba2ee`.
El driver final, que vuelve a comprobar PLAYING tras `frame_post_draw`, también
compiló y repitió los **17/17** helpers:
`tools\godot\runtime\g1-capture-guard-6aec0e7f0bad467fba7e3590c7777279`.

#### Verificación integral G1 con guard del arranque normal

**Ejecutada por el implementador el 2026-09-09**, con el hook real ya integrado y
el contrato de salida nativo `FUTSAL_MATCH_INTEGRATION_TESTS`:

```powershell
pwsh -NoProfile -File .\tools\godot\Test-MicroSlice.ps1 -AllowKnownVulkanLayerWarning
```

| Etapa | Resultado | Tiempo de proceso observado |
| --- | --- | --- |
| Validadores PowerShell | **78/78** | 1,870 s |
| Helpers nativos del driver | **28/28** | 0,459 s |
| Simulación, archivos de test vigentes | **322/322**, 24/24 contactos, 50/50 tiros, 27 negativas esperadas | 2,777 s |
| HUD nativo | **275/275**, 16 errores exactos esperados | 0,451 s |
| Guards negativos del default | **3/3**, cada fixture rechazada antes de cualquier start del driver | 2,971 s |
| Integración nativa | **180/180**, sin errores/rechazos | 1,451 s |
| Main fuente headless | **79/79** | 8,203 s |
| Main fuente Vulkan + PNG | **84/84** | 11,429 s |
| `.exe` G1 headless | **84/84** | 19,376 s |
| `.exe` G1 Vulkan + PNG | **89/89** | 11,005 s |
| Aserciones del runner | **97/97** | **86,384 s totales**, incluida importación/exportación |

Los conteos 315/315 y 639/639 anteriores permanecen como observaciones históricas;
322/322 es la salida de los tests presentes en esta ejecución, no una expectativa
fija ni una modificación del core por Ferro. Matrices, tiempos y checks anidados
no se suman como pruebas independientes adicionales.

Evidencia completa:
`tools\godot\runtime\g1-20260909T183848Z-9bcb8c75ca0f4c49bca8e85e614edd89\result.json`.
Cada uno de los cuatro informes acredita `default_entrypoint.verified=true` con
**cero starts del driver** durante toda la prueba inicial. Ticks observados
antes/tras espera/tras input: fuente headless **1→20→68**, fuente Vulkan
**1→26→74**, `.exe` headless **1→18→66**, `.exe` Vulkan **1→26→74**. Solo después
se ejecutan los tres drills controlados.

El `.exe` informa `editor_binary=false`, su propia ruta y
`main_scene=res://match/match.tscn`. Ambos PNG reales, inspeccionados directamente,
muestran los cuatro atletas, balón y cancha desde la cámara de partido, en
PLAYING y **sin modal ni bootstrap**. Ambos usan Vulkan/Forward+,
**1920×1080** y **NVIDIA RTX 2000 Ada Generation Laptop GPU**. La excepción
acotada del loader permanece registrada; no se ocultaron errores del juego.
Los 97 checks incluyen la salida de los PID propios; el lock quedó retirado.

Artefacto local autocontenido `build\windows\FutsalG1.exe`: **103.324.056 bytes**,
SHA-256 `eb8758d8b46528ab26058fc01a17f0bc435c6b82f4c0a5738f8fabdf1fe5de30`.
Esto prueba comportamiento automático, arranque real y captura/exportación,
**no** aprobación QA independiente, sensación humana, arte ni 1080p60 sostenido.

**Repetición tras el cierre de Hicks y su limpieza/UIDs:** mismo comando completo,
**97/97** checks del runner y los mismos conteos por etapa, en **96,528 s**.
Se comprobó la ausencia de `game\match\validation.png` antes de exportar. El
`.exe` regenerado conserva exactamente el tamaño y SHA-256 anteriores; se volvió
a inspeccionar su PNG real en PLAYING y a comprobar el cierre de los cuatro PID
de juego. Evidencia actual:
`tools\godot\runtime\g1-20260909T185204Z-e4f23d86c0a942bb93f13f00263fd7cd\result.json`.
El smoke visual prueba pausa/reanudación durante PLAYING. La batería nativa del
core cubre además la corrección de Bishop: al continuar, el balón recupera vuelo
y giro en PLAYING y GOAL_PAUSE, mientras RESTART_PAUSE sigue congelado. Las siete
aserciones añadidas elevan esa batería a **322/322**; la rama defectuosa produce
**320/322**. Contrato y evidencia de la regresión en `docs\MICRO_SLICE.md`.
Esto no añade una prueba visual de esa transición ni modifica el core desde
tooling; los informes anteriores de 315 y sus mutaciones conservan sus conteos.

El intento antiguo detenido por falta de integración se conserva, sin atribuirle
éxito, en `g1-20260909T173814Z-df4949eb66da4cc6b7377b2287579b6d`.

#### Revalidación del hook y exclusión de capturas auxiliares

Tras confirmar coordinación el hook del main, Ferro repitió el comando completo:
**97/97** del runner, **66,681 s**. Se excluye explícitamente
`match/validation.png` del preset para que una nueva captura provisional de
integración no se empaquete como asset; no se borra ni modifica ese archivo del
propietario. Un test de configuración verifica la exclusión y cada smoke del
`.exe` comprueba además que el recurso no está en el PCK.

Resultados de esta revisión: validadores **79/79**, helpers **28/28**, guards
negativos **3/3**, core **322/322**, HUD **275/275** —16 diagnósticos exactos
esperados— e integración **180/180**. Fuente: **79/79 headless**, **84/84 Vulkan**;
`.exe`: **85/85 headless**, **90/90 Vulkan**. El incremento de una aserción en
cada arranque exportado corresponde a la captura auxiliar excluida, no a cambiar
el baseline histórico. Main, hook, core y HUD no fueron editados por Ferro.

Los cuatro informes confirman el arranque normal antes de cualquier drill, con
cero starts del driver durante esa prueba, y finalizan en PLAYING. PNG del
ejecutable inspeccionado: cuatro atletas y pista, sin modal/bootstrap;
1920×1080, Vulkan/Forward+ y la misma NVIDIA RTX 2000 Ada que el source.
Warnings/errores inesperados siguen bloqueando; solo se admitió la excepción
exacta del loader solicitada mediante flag. PID propios cerrados y lock retirado.

Evidencia de esa ejecución del implementador:
`tools\godot\runtime\g1-20260909T193441Z-1ba9ba4b714c40af82adcd28335fc70f\result.json`.
**Artefacto actual:** `build\windows\FutsalG1.exe`, **103.324.536 bytes**,
SHA-256 `1df9ceeef1ab39f7a545f2c00ba1ce235291c561a777959481f83085e72801bc`.
La ejecución independiente anterior queda preservada abajo; la exclusión adicional
y este build están incluidos en el cierre técnico descrito a continuación, sin
aprobar gates humanos, artísticos ni de FPS.

**Repetición independiente del estado final:** coordinación obtuvo **97/97**
en **61,453 s**, con los mismos conteos de componentes y arranques anteriores
(incluidos validadores 79/79 y `.exe` 85/85–90/90). Informe vigente:
`tools\godot\runtime\g1-20260909T194405Z-461a8b7c505d431e92786d0c0a7301a4\result.json`.
El tamaño y SHA-256 coinciden con el artefacto actual indicado arriba.
Su arranque normal adicional, sin diagnóstico y con 240 iteraciones solicitadas,
terminó con código 0. `docs\images\g1-prototype.png` es una copia byte por byte
de la captura de esta última exportación independiente.

**Cierre de revisión técnica:** Vasquez emitió **APPROVE** para tooling/driver,
ruta diagnóstica exportada, delta de integración y exclusión de la captura.
Verificó personalmente el validador actualizado 79/79 y el diagnóstico headless
93/93 del ejecutable actual; cotejó el informe independiente final, hash,
metadatos y PNG. Sin bloqueantes técnicos pendientes. La revisión no concede
aceptación humana de sensación, aprobación artística ni 1080p60 sostenido.

#### Comprobación independiente anterior

Coordinación repitió la validación integral después de corregir la ruta diagnóstica
del ejecutable: **97/97** del runner en **61,879 s**, con simulación 322/322,
HUD 275/275, integración 180/180 y los cuatro arranques fuente/`.exe` 79/84/84/89.
Evidencia:
`tools\godot\runtime\g1-20260909T191237Z-41366e0a8d06411b8aae9145b7dda0cd\result.json`.
Cada informe conserva cuatro actores y el guard del arranque normal.
La captura de esa build permanece en el directorio de su informe; la imagen
documental muestra la exportación independiente posterior indicada arriba.

**Artefacto de esa comprobación:** `build\windows\FutsalG1.exe`, **103.324.472 bytes**,
SHA-256 `d4a04f70bb83ddcb02cea49beb83e6e8bddcabdae27d6c331d837765f2d5b2e7`.
Su hash se cotejó con el informe. Un arranque adicional del `.exe` sin flags de
diagnóstico, limitado a 240 iteraciones, terminó con código 0 y sin activar ningún
runner. Vulkan/Forward+ usó la NVIDIA RTX 2000 Ada; no se mide aquí rendimiento
sostenido ni sensación humana.

En la misma cadena independiente, diagnóstico/pipeline **692/692** y reutilización
del instalador **13/13** pasaron antes de reconstruir la build final jugable.
Informes: `20260909T191048Z-85db22f1462344a59d5669be4ac68913\result.json`
y `installer-reuse-result.json`, ambos dentro de `tools\godot\runtime\`.
El intento anterior 456/457 se conserva como fallo real: la plantilla oficial
rechazaba el override de escena por CLI. La ruta interna explícita que se describe
a continuación corrige ese caso, sin sustituir ni parchear el motor.

### Diagnóstico/pipeline conservado, separado de la validación jugable

Cierra previamente cualquier editor de **este proyecto** y ejecuta:

```powershell
pwsh -NoProfile -File .\tools\godot\Test-Godot.ps1 -AllowKnownVulkanLayerWarning
```

La prueba abre y cierra sus propias ventanas. Tiene timeouts explícitos, un lock
local para evitar dos suites simultáneas, propagación de errores y limpieza solo
de procesos/archivos propios. Si queda `tools\godot\runtime\test.lock` después de
un cierre forzado del shell, verificar que no sigue ejecutándose esa validación
antes de retirar únicamente ese lock.

Esta suite abre `res://bootstrap/bootstrap.tscn` **explícitamente** en fuente.
En el ejecutable usa `-- --diagnostic-bootstrap --smoke-test`: el main reconoce
esa opción de la aplicación antes de iniciar el partido y cambia de forma diferida
a la escena diagnóstica empaquetada. La ruta es fija, no una carga arbitraria.
Las plantillas oficiales 4.7.2 no admiten overrides de ruta de escena en la línea
de comandos del motor; pasarles directamente `res://bootstrap/bootstrap.tscn`
produce un error. No se recompila ni modifica la plantilla para evitarlo.
El main configurado sigue siendo el partido; estos recorridos no afirman probar G1.
Conserva importación GLB real, física y checks nativos del diagnóstico. La
regresión del instalador es independiente y no se ejecuta ni se parsea aquí.

**Snapshot histórico de preparación `0.0.0-preparation`**, después de corregir
el filtrado de dispositivos; no conteos actuales esperados de G1:

| Comprobación | Resultado |
| --- | --- |
| Runner nativo: escena, input, tick físico y GLB | **199/199** |
| Bootstrap diagnóstico con Godot headless | **90/90** |
| Mismo diagnóstico, ventana real Forward+ y PNG | **94/94** |
| Antiguo `.exe` diagnóstico, headless y sin editor | **91/91** |
| Antiguo `.exe` diagnóstico, ventana real Forward+ y PNG | **95/95** |
| Suite completa, incluidos scripts, hashes, procesos y cleanup | **639/639** |

Ese total histórico incluye **5/5 AST PowerShell**, los casos de argumentos con espacios,
salida distinta de cero y timeout con limpieza de PID, y **2/2 comprobaciones
nativas de parsing/tipos GDScript**. No se presentan como tests adicionales al total.
Los conteos se calculan sobre los resultados, no sobre un número fijo esperado.

**Regresión de input reproducida y corregida:** en el binario 4.7.2 comprobado,
`InputEventKey.new().device` devuelve **16**, igual que el parser nativo de un
`Object(InputEventKey, ...)` sin `device`. Las teclas originales omitían esa
propiedad; heredaron el valor y el editor lo serializó. Esto describe el default
del motor, **no identifica el teclado físico de Windows**. Un evento de tecla
del dispositivo 0 no coincidía ni activaba las acciones. Se corrigieron las nueve
entradas con `device=-1` explícito, sin reasignar dispositivos ni modificar InputMap
desde los tests.

La nueva regresión falló **63/90, con 27 aserciones fallidas**, antes de cambiar
los bindings, y pasó **90/90** después. Comprueba las nueve acciones de teclado
y mando del dispositivo **0** mediante `InputMap.event_is_action`,
`Input.parse_input_event`, `Input.flush_buffered_events` e
`Input.is_action_pressed`: coincidencia de pulsación, estado pulsado,
coincidencia de liberación y estado liberado. Pulsación y liberación usan
**objetos de evento distintos**; las liberaciones de ejes vuelven a cero.
No se utiliza `Input.action_press` como sustituto del despacho.

Cada uno de los cuatro arranques de diagnóstico históricos añadió **72 aserciones de despacho
real**. El runner nativo repite además con dispositivo **1**: **144 aserciones**
de input dentro de sus 199. Son aserciones, no cientos de escenarios de gameplay.
El anterior **207/207** no comprobaba este recorrido y queda como histórico,
no como validación vigente. Los eventos se inyectan solo en el modo smoke;
esas pruebas del bootstrap no atraviesan handlers de juego ni acreditan un teclado/mando físico.
El rojo/verde se conserva en `tools\godot\runtime\input-regression-red.json` y
`input-regression-green.json`; el diagnóstico del default está en
`input-device-before.stdout.log` e `input-device-after.stdout.log`.

La importación usa `--headless --editor --import`; cada script se comprueba
separadamente con `--headless --check-only --script res://...`.
**`--check-only --editor` no se considera un lint.** El runner nativo del
diagnóstico se complementa con arranques explícitos del bootstrap. El main G1
normal se valida separadamente mediante `Test-MicroSlice.ps1`.

El preset `game\export_presets.cfg`, **Windows Desktop**, produce:

```text
build\windows\FutsalG1.exe
```

Es un **debug x86_64 con PCK embebido**, sin firma ni modificación externa de
recursos; no necesita `rcedit`. Los **103.194.744 bytes** registrados anteriormente
pertenecían a `FutsalBootstrap.exe`, no son un tamaño esperado de G1.
`Test-MicroSlice` ejecuta el nuevo build desde `build\windows`, **sin `--path`,
`--script`, selección de escena, Blender ni editor en su línea de ejecución**,
y exige `editor_binary=false`. `tests/*`, probes sintéticos y la captura auxiliar
`match/validation.png` se excluyen;
`diagnostics/match_smoke.gd` se conserva para la prueba opt-in del propio `.exe`.
Tras completar y validar la exportación, se abre sin Godot/Blender instalados:

```powershell
Start-Process -FilePath .\build\windows\FutsalG1.exe -Wait
```

Con el hook conectado, el main acepta `-- --smoke-test` para una ejecución acotada;
`--report-path=C:\ruta\resultado.json` y `--capture-path=C:\ruta\captura.png`
van **después** del separador `--`, dentro de directorios ya existentes.
Una captura exige modo gráfico; headless falla si se le pide una imagen y nunca
afirma haber validado la GPU. La suite ya prepara todas esas rutas ignoradas.

### Evidencia GPU y límites

Las ejecuciones gráficas históricas del **diagnóstico**, no del partido G1, registraron:

- **1920 × 1080**, método `forward_plus`, driver `vulkan`, API Vulkan **1.4.329**.
- **NVIDIA RTX 2000 Ada Generation Laptop GPU**, elegida por Godot sin override.
- Driver Windows observado: **32.0.15.9595**. El inventario registra aparte Intel
  Arc Pro **32.0.101.8801**; no confundir hardware enumerado con GPU utilizada.
- PNG leído del viewport **tras `RenderingServer.frame_post_draw`**, con contenido
  no uniforme y guardado real. Se inspeccionó visualmente la captura del ejecutable.
- **Un fotograma capturado**, no un benchmark. No se midieron FPS sostenidos,
  p95/p99, memoria de un partido ni calidad artística. No acredita 1080p60,
  gráficos ≥8/10, mando físico, sonido ni una escena 3D representativa.

El loader Vulkan emitió un bloque `WARNING: GENERAL - Message Id Number: 0 |
Message Id Name: Loader Message`, seguido de
`windows_read_data_files_in_registry: Registry lookup failed to get layer manifest files.`,
un objeto `VK_OBJECT_TYPE_INSTANCE` y el callback fijado del loader. Se conserva
en stderr. `-AllowKnownVulkanLayerWarning` solo admite **una coincidencia completa**
de ese bloque por arranque gráfico, con su handle variable; no permite otros
warnings ni errores. Se registra su presencia por etapa. Sin ese flag falla
también esa advertencia. **No se modifica registro, driver ni entorno global**
para ocultarla.

Evidencia histórica ignorada y fechada del diagnóstico:

```text
tools\godot\runtime\smoke-result.json
tools\godot\runtime\20260909T143124Z-3e4038b2c74b47d78396167b37abb819\result.json
tools\godot\runtime\20260909T143124Z-3e4038b2c74b47d78396167b37abb819\source-rendered.png
tools\godot\runtime\20260909T143124Z-3e4038b2c74b47d78396167b37abb819\artifact-rendered.png
```

Cada ejecución nueva del diagnóstico crea su propio directorio;
`smoke-result.json` guarda su resultado más reciente. G1 usa el resumen separado
`g1-result.json`. Los procesos propios tienen timeout y limpieza por PID/árbol;
no se detienen sesiones ajenas por nombre.

### Pipeline de assets y Git LFS

La suite usó Blender **4.5.13 LTS** real, en una instancia de fábrica sin activar
MCP, y exportó un **GLB de 1.944 bytes**: una única caja roja de prueba de
2 × 4 × 6 metros. Godot la importó como `PackedScene`; verificó una malla,
escala unitaria, dimensiones **2 × 6 × 4** tras pasar a Y-up, color de material,
metallic **0,2** y roughness **0,65**. También avanzó una prueba efímera de física
3D bajo Jolt. **No es un asset artístico ni una escena del juego.**

El `.blend` fuente estuvo únicamente dentro del directorio ignorado de esa
validación; el GLB, bajo `game\assets\_pipeline_probe_<id>.glb`. Se retiraron ambos,
su `.import` y las cachés de importación de ese GUID, incluso en la ruta de error.
Se verificaron **0 probes restantes**. Los futuros `.blend` fuente seguirán fuera
de `game`; sus entregables de runtime serán GLB bajo `game\assets`.
La opción real `filesystem/import/blender/enabled=false` evita introducir una
dependencia implícita de Blender en cada importación del proyecto.

**Git LFS 3.7.1** estaba instalado. Se ejecutó `git lfs install --local` únicamente
después de comprobar que no había un `core.hooksPath` personalizado ni hooks
activos en conflicto. En otros clones hay que hacer la misma comprobación antes
de instalar LFS; no usar `--force` sobre hooks ajenos.

`.gitattributes` añade LFS solo para `*.blend` y `*.glb`; scripts y licencias no
usan ese filtro. Conserva todas las reglas `merge=union` existentes. Los UID
`*.gd.uid` son identidad de código fuente y se versionan; `game\.godot`, builds,
cachés e inventarios locales no. Los dos archivos upstream de dream-loop tienen
`-text` para mantener sus bytes exactos; `Install-DreamLoop.ps1 -VerifyOnly`
volvió a comprobarlos tras añadir esos atributos. MCP no se modificó.

Fuentes: [descarga Windows oficial](https://godotengine.org/download/windows/),
[release 4.7.2 y SHA-512](https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/SHA512-SUMS.txt),
[CLI oficial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
y [licencia MIT de Godot](https://godotengine.org/license/). Los artefactos son locales
y de desarrollo. Las copias 0.4 publicadas localmente no constituyen una release
externa; firma, créditos/licencias de distribución y gates de gameplay/arte
requieren sus propios encargos y revisión independiente.
