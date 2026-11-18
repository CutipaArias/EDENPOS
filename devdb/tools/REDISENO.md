# Rediseño de pantallas EdenPOS — reglas comunes (Fase 2)

Lee esto completo antes de tocar código. Varios implementadores trabajan **a la vez**, cada uno en su grupo de archivos.

## Qué usar
- El sistema de diseño ya existe: comentario inicial de `Theme.cs` (líneas 10–60) y `Controls.cs`. Mira `devdb/capturas/base/00-galeria-diseno.png` para ver cada componente.
- Botones: `Theme.Button(texto, ButtonVariant.Primary|Secondary|Destructive|Ghost)`. Una sola acción `Primary` por zona; las destructivas en `Destructive`; las terciarias en `Ghost`. Para colores de fondo usa `Theme.Primary` (no `Theme.Green`, que no da contraste con texto blanco). Para deshabilitar usa `Enabled=false`.
- Campos: `Theme.Field(textBox|numericUpDown)` (`EdenField`), `Theme.Combo()` (`EdenComboBox`) en vez de `ComboBox`, `Theme.LabelField(texto)` encima de cada campo.
- Superficies: `CardPanel` (radio 12, borde, `Elevated` para lo que flota), `ScreenHeader` (título + subtítulo de contexto + acciones a la derecha) en cada pantalla principal, `Theme.Pill` para estados, `Theme.Banner` para feedback en línea, `Theme.EmptyState` cuando no hay datos, `Theme.Message(owner, Tone, …)` en lugar de `MessageBox.Show` para avisos al usuario (conserva las confirmaciones Sí/No existentes).
- Tablas: `Theme.StyleGrid`. Quita colores sueltos de celdas que ya cubren los tokens (usa `Theme.Danger`/`DangerSoft` para alertas, `Theme.Muted` para texto secundario).
- Tipografía: `Display` (cifra principal), `Heading` (título de pantalla), `Title` (título de tarjeta/diálogo), `Subhead`, `Emphasis` (importes/totales), `Body`, `FieldLabel`, `Caption`. Nada de `new Font(...)` suelto salvo casos justificados.
- Espaciado y radios solo de `Theme.Space`, `Theme.Radius`, `Theme.Dim`. Nada de números mágicos nuevos.

## Principios (apple-design aplicado a WinForms)
- **Jerarquía clara:** lo más importante de cada pantalla es lo más visible (en Ventas, el total y el botón Cobrar; en Turno, el efectivo esperado; en Reportes, las cifras de resumen).
- **Orientación:** cada pantalla dice dónde estás (cabecera) y qué puedes hacer (acciones agrupadas cerca de lo que afectan).
- **Etiquetas directas y en mayúscula inicial:** "Registrar entrada", "Cobrar S/ 49.00", "Cerrar turno". No TODO EN MAYÚSCULAS en botones, títulos ni etiquetas. Los nombres que vienen de la base (productos, usuarios, categorías) se muestran tal cual.
- **Español correcto con tildes y ñ** en todo texto nuevo o reescrito ("categoría", "mínimo", "aparecerá", "Configuración").
- **Feedback en cuatro tipos** (estado, completado, advertencia, error) con su color semántico; validación en línea cerca del campo cuando sea posible.
- **Respuesta inmediata** (ya la dan los botones). Sin animaciones salvo que respeten `Theme.UseMotion` y aporten algo.
- **Simplicidad, no minimalismo:** no quites funciones ni información; reorganiza, agrupa y da aire.
- Preferir `TableLayoutPanel`/`FlowLayoutPanel`/`Dock`/`Anchor` sobre coordenadas fijas cuando reescribas un layout, para que la pantalla aguante distintos tamaños de ventana y escalas de Windows (125–150 %). Comprueba 1366×768 y 1920×1080.

## Qué NO hacer
- No cambiar lógica de negocio, firmas públicas, nombres de controles que otros archivos usan, ni el flujo (qué pasa al pulsar cada cosa). Mantén todos los manejadores de eventos y validaciones.
- No tocar archivos fuera de tu grupo. Si necesitas algo nuevo en `Theme.cs`/`Controls.cs`, NO lo edites: créalo como clase privada dentro de tu archivo y repórtalo (el orquestador lo unificará).
- No escribir en el MariaDB del puerto 3306 (es del usuario).

## Compilar y capturar (el usuario puede tener la app abierta y `bin\` bloqueado)
- Compila SIEMPRE a carpetas propias para no chocar con los demás implementadores ni con la app abierta:
  `dotnet build "C:/Users/Braya/PR lap/GPTI/EdenPOS/EdenPOS.csproj" -nologo -p:OutDir=<tu-scratchpad>\out\ -p:IntermediateOutputPath=<tu-scratchpad>\obj\`
  Si falla por un error en un archivo que NO es tuyo (otro implementador está a mitad), espera un poco y reintenta; no lo arregles.
- Capturas: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File "C:\Users\Braya\PR lap\GPTI\EdenPOS\devdb\tools\Capturas.ps1" -Etiqueta <tu-grupo> -BinDir <tu-scratchpad>\out -Solo '<patrón de tus capturas>'`. Usa `-OutDir` propio si hace falta. La herramienta usa una base en el 3307; si varios la ejecutan a la vez, pasa `-KeepDb -ReuseDb` solo si sabes que nadie la borra; si no, déjala crear y borrar la suya.
- **Mira tus capturas** con la herramienta Read antes y después, y repite hasta que se vean bien: nada cortado, nada solapado, alineaciones limpias, jerarquía clara. Compara con `devdb/capturas/antes/`.
- Al final deja tus capturas en `devdb/capturas/despues/` con los mismos nombres que en `antes/`.
