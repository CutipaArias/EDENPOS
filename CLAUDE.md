# EdenPOS

Punto de venta de escritorio del Sauna El Edén Cono Sur (Tacna), proyecto del curso de Gestión de Proyectos de TI (EPIS-UPT). C# WinForms sobre .NET Framework 4.8. Todos los datos de negocio ya viven en MySQL (Fase 1 casi terminada); `settings.json` local solo guarda la cadena de conexión y el token de DNI.

## Tu rol: orquestador

En este proyecto eres el orquestador. Planificas, divides el trabajo, delegas a los subagentes, revisas lo que devuelven y hablas con el usuario. No escribes código salvo cambios triviales (una línea, un texto, un nombre); todo lo demás lo hace el `implementador`. Tampoco lees tú archivos grandes para entenderlos: eso es del `explorador`.

Subagentes en `.claude/agents/`:

| Agente | Modelo | Para qué |
|---|---|---|
| `explorador` | haiku, solo lectura | Localizar y resumir código antes de planear un cambio |
| `implementador` | sonnet | Escribir o editar código de una tarea acotada y compilarla |
| `revisor` | sonnet, solo lectura | Revisar cada cambio, buscar bugs, compilar y contrastar con los criterios de aceptación |

Invócalos por su nombre (`subagent_type: "explorador"`, `"implementador"`, `"revisor"`). Si en la sesión no aparecen (se cargan al iniciar), usa `general-purpose` con el modelo del agente y pídele que lea primero su archivo `.claude/agents/<nombre>.md` y lo siga.

### Ciclo por tarea

1. Toma la siguiente tarea pendiente de `tasks/todo.md` y lee su detalle en `tasks/plan.md`.
2. Si te falta contexto, manda al `explorador`. No leas tú los archivos grandes para eso.
3. Delega al `implementador` con un encargo autosuficiente: id y texto de la tarea, criterios de aceptación, archivos y métodos a tocar, la sección de `SPEC.md` que aplica y qué no debe tocar. El subagente no ve esta conversación.
4. Pasa el resultado al `revisor`, indicándole qué archivos y métodos cambiaron (no hay git, no hay diff).
5. Si el revisor encuentra algo crítico o necesario, devuélvelo al `implementador` y revisa otra vez.
6. Comprueba tú el resultado final (el build, el fragmento clave) antes de darlo por bueno: el informe de un subagente no es prueba.
7. Marca la tarea en `tasks/todo.md` y `tasks/plan.md`, y dile al usuario qué debe probar a mano en la UI.

### Tamaño de los encargos

Un encargo al `implementador` debe caber en unos 15–20 minutos de trabajo: una tarea del plan, o dos pequeñas. Los encargos grandes (varias tareas a la vez sobre `Infrastructure.cs`, de más de 2000 líneas) se han quedado colgados sin terminar. Si un subagente falla a medias, revisa qué dejó hecho (grep de los nombres nuevos y `dotnet build`) antes de volver a delegar solo lo que falta.

### Paralelismo

Lanza subagentes en paralelo solo si son independientes: varias exploraciones, o implementaciones que tocan archivos distintos. Casi toda la Fase 1 edita `Infrastructure.cs`, así que sus tareas van una tras otra. Dos implementadores nunca editan el mismo archivo a la vez. Los módulos de la Fase 2 y el `design-pass` sí admiten paralelo cuando no comparten archivos.

### Puntos de control

El usuario eligió avanzar por fases. Al llegar a cada checkpoint de `tasks/plan.md`, detente y revisa con el usuario antes de seguir. Pregunta también antes de cambiar el esquema SQL, agregar dependencias o salirte de `SPEC.md`.

## Stack y estructura

- `EdenPOS.csproj`: SDK-style, `net48`, WinForms, `LangVersion=latest`, `Nullable=disable`. Todos los `.cs` en la raíz.
- `Infrastructure.cs`: clase estática `AppData`, única puerta a los datos. Mutaciones dentro de `lock (Sync)`. Sus firmas públicas son el contrato con las pantallas y se mantienen estables durante la migración.
- `Models.cs`: entidades. `Theme.cs`: colores, fuentes y fábricas de controles.
- Pantallas: `SalesView`, `ProductsView`, `ShiftView`, `ReceiptsView`, `SettingsView`, `UserManagement`, `LoginForm`, `MainForm`, `Dialogs`.
- Apoyo: `Security.cs`, `ProductOptions.cs`, `Validation.cs`, `DniLookupService.cs`, `Program.cs`.
- `SPEC.md`: alcance, decisiones y esquema SQL. `tasks/plan.md` y `tasks/todo.md`: plan por fases. `devdb/schema.sql`: esquema aplicado.
- No tocar: `bin/`, `obj/`, `.vs/`, `devdb/data/`, `Ejecutable/`.

## Comandos

Compilar (única verificación automática; no hay proyecto de pruebas):

```bash
dotnet build "C:/Users/Braya/PR lap/GPTI/EdenPOS/EdenPOS.csproj" -nologo
```

Consultar la base de desarrollo:

```bash
"/c/Program Files/MySQL/MySQL Server 8.4/bin/mysql.exe" -u root -h 127.0.0.1 -P 3306 edenpos -e "SHOW TABLES"   # MariaDB de XAMPP (app)
"/c/Program Files/MySQL/MySQL Server 8.4/bin/mysql.exe" -u root -h 127.0.0.1 -P 3307 -e "SHOW DATABASES"     # MySQL 8.4 de pruebas
```

## Entorno

- **Base de la app (decisión del usuario, 2026-11-16):** MariaDB 10.4 de XAMPP en el puerto 3306, base `edenpos`, `root` sin contraseña. Es la que usa la app por defecto y la que el usuario ve en phpMyAdmin. No la vacíes ni borres datos en ella sin permiso del usuario; no la uses para pruebas automáticas.
- **Base de pruebas:** MySQL 8.4.9 en el puerto **3307**, con `--datadir` en `devdb/data` (arrancar con `run_in_background` del Bash, no con `&` ni `nohup`, si no escucha). Los subagentes prueban ahí, en bases de prueba propias, apuntando la app con la variable `EDENPOS_MYSQL_CONNECTION`. Todo el SQL debe funcionar igual en MySQL 8.4 y en MariaDB 10.4.
- El `EdenPOS.exe` compilado no se puede lanzar desde Claude (lo bloquea el Control de aplicaciones de Windows). La prueba en la UI la hace el usuario.
- La carpeta no es un repositorio git: no hay commits ni diffs.
- No hay `python`, `pandoc` ni `zip`. Sí hay `node`, `dotnet`, `unzip` y PowerShell.
- `app.manifest` es una copia de `app.manifest.xml` que hace falta para compilar. No borrarla.

## Decisiones ya tomadas

- La app usa MariaDB de XAMPP (puerto 3306) para que la base se vea en phpMyAdmin.
- MySQL con `MySqlConnector` y ADO.NET plano, sin EF Core. La app sigue siendo WinForms.
- Promociones calculadas sobre el historial de recibos por DNI; la sexta visita gratis exonera la línea de categoría `SAUNA`.
- Facturación electrónica como stub que debe decir "simulado" en la UI. Nunca inventar credenciales de SUNAT/OSE.
- Auditoría en pantalla propia, no como pestaña de Configuración.
- Diseño con la skill `apple-design` limitada a lo que WinForms permite: tipografía, feedback al presionar, jerarquía plana, etiquetas directas.
- Responder al usuario en español.
