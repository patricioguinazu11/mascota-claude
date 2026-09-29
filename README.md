# Mascota de Claude Code para Windows

Un bichito pixel-art que vive en una esquina de tu escritorio y te muestra qué está haciendo Claude Code: si está esperando, trabajando, si necesita tu permiso (salta, se pone rojo y suena un "din-don") o si ya terminó.

![Los 4 estados de la mascota](docs/estados.png)

Funciona solo con Windows PowerShell y .NET, que ya vienen con Windows, así que no hace falta instalar nada.

## Instalación

1. Bajá el repositorio a tu PC: en GitHub, **Code → Download ZIP** y descomprimilo, o `git clone https://github.com/patricioguinazu11/mascota-claude.git`.
2. Abrí PowerShell en esa carpeta (en el Explorador: clic derecho en un espacio vacío → *Abrir en Terminal*).
3. Ejecutá:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\instalar.ps1
   ```
4. Si tenías Claude Code abierto, cerralo y volvelo a abrir para que tome los hooks.

La mascota aparece abajo a la derecha y a partir de ahí arranca sola cada vez que prendés la PC.

## Uso

- **Arrastrala** con el botón izquierdo a donde quieras: se acuerda de la posición.
- **Clic derecho** para prender o apagar el sonido, devolverla a la esquina o cerrarla.
- Si pasás el mouse por encima, te dice en qué proyecto está trabajando Claude.

## Desinstalación

Desde la carpeta del repositorio:

```powershell
powershell -ExecutionPolicy Bypass -File .\desinstalar.ps1
```

También queda una copia en `%LOCALAPPDATA%\ClaudeMascota\desinstalar.ps1`. Cierra la mascota, quita solo sus hooks del `settings.json`, borra el acceso directo de Inicio y la carpeta instalada.

## Qué toca en tu PC

| Qué | Dónde |
| --- | --- |
| Archivos de la mascota | `%LOCALAPPDATA%\ClaudeMascota` |
| Hooks de Claude Code | `%USERPROFILE%\.claude\settings.json` (antes de modificarlo deja una copia `settings.json.bak-mascota-FECHA`) |
| Arranque con Windows | Acceso directo `Mascota Claude` en la carpeta Inicio |

Los hooks que agrega son `UserPromptSubmit`, `PreToolUse`, `PostToolUse` (para salir del estado de "permiso" cuando aprobás), `Notification`, `Stop` y `SessionEnd`. Corren en segundo plano (`"async": true`), así que no frenan a Claude. Todo lo demás que tengas en `settings.json` queda igual.

## Si algo no anda

- **No cambia de estado:** reiniciá Claude Code y fijate que en `settings.json` estén los hooks que apuntan a `ClaudeMascota/hook.ps1`.
- **No aparece:** abrila a mano con `powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ClaudeMascota\mascota.ps1"` y mirá si hay errores en `%LOCALAPPDATA%\ClaudeMascota\mascota.log`.
- **Quedó en un estado viejo** (por ejemplo, si cortaste a Claude con Esc): vuelve sola a "esperando" a los pocos minutos, o con el próximo mensaje que le mandes.
