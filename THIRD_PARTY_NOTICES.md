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

## Skill dream-loop

La skill de [achimala/dream-loop](https://github.com/achimala/dream-loop) está
vendorizada bajo licencia **MIT**, sin editar sus archivos originales. Su
licencia, revisión de procedencia y hashes están en `.github\skills\dream-loop`.
No se ha ejecutado un bucle visual ni se ha aprobado una imagen objetivo.

## Integración opcional Blender MCP

Las herramientas locales pueden descargar y configurar
[ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp), bajo licencia
**MIT**. `tools\mcp\upstream.json` identifica la versión y el commit usados.
Las instalaciones, entornos Python y archivos descargados son locales y no
forman parte de las releases del juego. Los scripts de configuración conservan
la procedencia de las modificaciones; la integración no concede derechos
sobre activos obtenidos de otros servicios.
