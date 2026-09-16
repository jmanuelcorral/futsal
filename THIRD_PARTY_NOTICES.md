# Avisos de terceros

La publicación del repositorio no cambia las licencias de sus componentes.
El código y el arte propios del juego no tienen asignada una licencia general
de reutilización. Este documento no concede derechos sobre marcas, rostros,
equipaciones ni otros activos ajenos.

## Godot y las builds del juego

Las releases incorporan el runtime oficial de **Godot 4.7.2**, distribuido bajo
licencia MIT, y sus componentes de terceros. Los paquetes deben conservar el
texto de la licencia de Godot y los avisos de su archivo `COPYRIGHT.txt`.
Las licencias de esos componentes no se sustituyen por una licencia del juego.

- [Licencia del motor](https://godotengine.org/license/)
- [LICENSE.txt de Godot 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/LICENSE.txt)
- [COPYRIGHT.txt de Godot 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt)

La documentación de distribución describe el contenido de cada paquete y sus
limitaciones de firma y validación. Blender es una herramienta de autoría:
no se distribuye dentro del ejecutable del juego.

## Base anatómica de los atletas

El cuerpo y los ojos de `CourtAthlete` derivan de la colección
**Body Male - Realistic**, de **Dan Ulrich**, incluida en **Human Base Meshes
v1.4.1**, publicada por Blender Studio y la comunidad bajo **CC0 1.0**.
La ropa, calzado, rig, pesos, máscaras y mapas de la adaptación se han creado
para este proyecto; no se han extraído de FIFA, EA Sports FC ni GOALS.

- [Paquete oficial y descripción](https://www.blender.org/download/demo-files/#assets)
- [Licencia CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)
- Procedencia, selección exacta y hashes: `art\source\athletes\court_athlete\provenance.json`.

La captura aportada como referencia de calidad no se redistribuye ni concede
derechos sobre su contenido. No se utilizan Rain Rig ni sus escenas, scripts
o animaciones. La licencia CC0 de la base no asigna una licencia general al juego.
Esta incorporación es posterior a la fuente congelada de la preview 0.4 y forma
parte de las fuentes y los paquetes gráficos de la preview 0.5.

## Skill dream-loop

La skill de [achimala/dream-loop](https://github.com/achimala/dream-loop) está
vendorizada bajo licencia **MIT**, sin editar sus archivos originales. Su
licencia, revisión de procedencia y hashes están en `.github\skills\dream-loop`.
No se ha aprobado una referencia comparable A-G2/A-G3 ni una puntuación visual
de producto; las iteraciones de los atletas no sustituyen esas condiciones.

## Integración opcional Blender MCP

Las herramientas locales pueden descargar y configurar
[ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp), bajo licencia
**MIT**. `tools\mcp\upstream.json` identifica la versión y el commit usados.
Las instalaciones, entornos Python y archivos descargados son locales y no
forman parte de las releases del juego. Los scripts de configuración conservan
la procedencia de las modificaciones; la integración no concede derechos
sobre activos obtenidos de otros servicios.
