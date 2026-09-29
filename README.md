# mascota-claude
Creá una mascota de escritorio para Windows que me muestre qué está haciendo Claude Code en mi PC.

Requisitos:
- Ventana chica, sin bordes, siempre visible, fondo transparente, que pueda arrastrar con el mouse y que recuerde su posición.
- Personaje animado simple con 4 estados: "esperando", "pensando/trabajando", "necesita mi aprobación" (llamativo, con sonido corto opcional) y "listo".
- Un globito de texto corto con lo que está pasando (ej: "Editando archivo…", "Terminé", "Necesito tu permiso").
- Conectala a los hooks de Claude Code (UserPromptSubmit, PreToolUse, Notification, Stop) en mi settings.json de usuario (%USERPROFILE%\.claude\settings.json), sin borrar lo que ya haya ahí.
- Sin instalar programas pesados: usá PowerShell/.NET que ya trae Windows.
- Que arranque sola al iniciar Windows y se pueda cerrar con clic derecho.

Estás en la nube, así que:
- Dejá todo guardado en este repositorio.
- Incluí un instalar.ps1 que yo ejecute una vez en mi PC para copiar los archivos, configurar los hooks y dejarla andando, y un desinstalar.ps1.
- Incluí un README corto en español con los pasos para instalarla.
