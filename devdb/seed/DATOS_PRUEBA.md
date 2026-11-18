# Datos de prueba de EdenPOS

Generados el 2026-11-16 en la base `edenpos` del MariaDB de XAMPP (127.0.0.1:3306, root sin contraseña) con
`devdb\seed\GenerarDatosPrueba.ps1`. Todo es **ficticio y solo de prueba**: nombres inventados, DNI `99000001` a
`99000025`, PIN de prueba. La facturación electrónica es **simulada** (no se envía nada a SUNAT).

El script usa la propia lógica de la app (`AppData`), así que stock, movimientos de inventario, comprobantes, auditoría y
promociones son coherentes. Después retrasa las fechas por id para tener 15 días de historial (del 2026-11-02 al 2026-11-16).

## Usuarios

| Usuario | Rol | PIN de prueba | Estado |
|---|---|---|---|
| DUEÑA | Dueña | 0000 | activa (la de la siembra) |
| CARLOS | Trabajador | 2468 | activo (tiene el turno abierto de hoy) |
| MARIA | Trabajador | 1357 | activa |
| PEDRO | Trabajador | 9753 | **desactivado** (no puede entrar; sale en auditoría) |

## Qué hay en la base

| Tabla | Filas |
|---|---|
| usuario | 4 |
| cliente | 25 (origen "Manual") |
| producto | 41 (se eliminó MANO SAUNA) y 37 variantes |
| sesion_caja | 15 (14 cerrados + 1 abierto hoy) |
| movimiento_caja | 21 (15 salidas, 6 depósitos) |
| recibo / recibo_linea | 174 / 389 |
| comprobante | 174 (169 Aceptado, 2 Rechazado, 3 Anulado) |
| movimiento_inventario | 162 (41 entradas, 118 ventas, 3 reembolsos) |
| ticket_guardado | 2 (con 3 llaves) |
| auditoria | 11 |

- **Configuración:** nombre del negocio de la siembra (BAÑOS SAUNA EDÉN), sexta visita activa, grupal desde 4 personas al 10 %.
- **Historial:** un turno por día, alternando CARLOS (días pares respecto a hoy) y MARIA. Entre 8 y 20 ventas por día
  (más en fin de semana), con 1 o 2 movimientos de caja, medios de pago Efectivo, Yape y Mixto, con y sin DNI.
- **Hoy (lunes 16/11):** turno **abierto** de CARLOS desde las 15:42 con 6 ventas y los 2 tickets guardados.

## Qué probar con cada cosa

### Promociones (sexta visita y grupal)
- **DNI 99000003 (ELVA MAMANI CHOQUE):** tiene 5 visitas pagadas; su **próxima visita con entrada SAUNA sale gratis**
  (SEXTA_VISITA). Cóbrale un GENERAL con DNI 99000003 y el diálogo debe mostrar "6ª visita gratis" (descuento S/ 18).
- **DNI 99000002 (JORGE LUIS CONDORI PARI):** cliente frecuente, 13 visitas; ya recibió la 6ª (recibo #66) y la 12ª (recibo #127)
  gratis. Su visita 13 de hoy se cobró normal; la 18ª será la siguiente gratis.
- **DNI 99000001 (MARIBEL TICONA HUANCA):** la 6ª gratis fue el recibo #125 (12/11); la 7ª se cobró normal.
- **DNI 99000004 (CESAR AUGUSTO FLORES ZEGARRA):** 3 visitas (no califica todavía).
- **Grupal:** hay 35 recibos con `GRUPAL` (4 o más personas), por ejemplo #2, #3, #5, #7. Prueba AMIGOS X4, FAMILIA 2 o GENERAL x4.
- **Venta grande:** recibo **#61** (07/11) de **S/ 748.80** con DNI 99000006, pago Mixto (efectivo 400.00 + Yape 348.80), grupal 10 %.
  Para probar la regla de "más de S/ 700 exige DNI", intenta una venta parecida sin DNI.

### Tickets guardados (cobrar un ticket guardado)
- **"Pareja llaves 3 y 7":** llaves **3 y 7**, cliente DNI 99000005 (LUZ MARINA CALIZAYA VARGAS), 2 adultos, S/ 38.00 (PAREJA + 2 hidratantes).
- **"Cliente llave 12":** llave **12**, cliente DNI 99000007 (SOFIA VALDIVIA MEDINA), 1 adulto, S/ 22.50 (GENERAL + toalla + snack).
- Prueba también que la llave ocupada no se pueda reusar en otro ticket.

### Inventario
- **Bajo el mínimo (salen en rojo y en el reporte de stock bajo):**
  - DESODORANTE: stock 0, mínimo 5 (agotado; la venta debe bloquearse).
  - GASEOSAS · INCA COLA / 2.5 L: stock 2, mínimo 6.
  - SNACKS · RITZ: stock 4, mínimo 10.
- Hay 36 artículos/variantes con control de inventario (bebidas, snacks, aseo y variantes de GASEOSAS, HIDRATANTE, SNACKS,
  JABONES, SHAMPOOS, ACONDICIONADOR, más MARCIANOS y artículos de aseo sueltos). El resto está por encima del mínimo.
- **Cambio de precio:** MARCIANOS pasó de 2.00 a 2.50 el 08/11 (auditoría PRECIO_CAMBIADO).
- **Artículo eliminado:** MANO SAUNA (sin ventas) el 12/11 (auditoría PRODUCTO_ELIMINADO).

### Reembolsos (3, con motivo)
| Recibo | Día | Quién cobró | Total | Motivo |
|---|---|---|---|---|
| #30 | 05/11 | MARIA | S/ 16.00 | Gaseosas entregadas en mal estado |
| #96 | 10/11 | CARLOS | S/ 36.00 | Error de cobro: los clientes no llegaron a ingresar |
| #126 | 13/11 | MARIA | S/ 43.00 | Reclamo por falla del vapor |

Sus comprobantes quedaron **Anulado** y el stock volvió al inventario (movimientos "Reembolso").

### Facturación simulada
- Rechazados: recibo **#112** (11/11, Yape, DNI 99000009) y recibo **#142** (14/11, Efectivo). En la pantalla de comprobantes
  prueba "Reintentar envíos": con "Simular rechazo" desactivado deberían pasar a Aceptado.
- "Simular rechazo" quedó desactivado (ese interruptor vive en el `settings.json` local de cada instalación, no en la base).
- Auditoría `COMPROBANTE_RECHAZADO` sale como acción del sistema (sin usuario).

### Caja
- Turnos cerrados con diferencia (auditoría CAJA_DIFERENCIA): turno #3 (04/11, CARLOS) **faltante de S/ 5.00**,
  turno #8 (09/11, MARIA) **sobrante de S/ 3.50**, turno #12 (13/11, MARIA) **faltante de S/ 12.00**.
- Los demás cierran exactos. `monto_esperado` coincide con `AppData.CalculateExpectedCash` en los 14 turnos cerrados.
- Turno abierto: #15 de CARLOS. Al entrar como CARLOS debe poder seguir vendiendo sin abrir turno nuevo.

### Auditoría (11 filas)
CAJA_DIFERENCIA x3, RECIBO_REEMBOLSADO x3, COMPROBANTE_RECHAZADO x2, USUARIO_DESACTIVADO (PEDRO, 07/11),
PRECIO_CAMBIADO (08/11), PRODUCTO_ELIMINADO (12/11).

## Cómo volver a generar los datos

El script **se niega a escribir** si la base no está en estado de siembra: exige 0 filas en `recibo`, `recibo_linea`,
`comprobante`, `cliente`, `sesion_caja`, `movimiento_caja`, `ticket_guardado`, `ticket_linea`, `casillero_llave`,
`movimiento_inventario` y `auditoria`, un único usuario (la dueña) y los contadores de recibo y turno en 1.

Para regenerar hay que **vaciar antes los datos de prueba** (esto borra TODO el historial de `edenpos`; no lo hagas si la base
ya tiene datos reales). Ejecuta en MySQL/phpMyAdmin sobre la base `edenpos`:

```sql
SET FOREIGN_KEY_CHECKS = 0;
DELETE FROM casillero_llave;
DELETE FROM ticket_linea;
DELETE FROM ticket_guardado;
DELETE FROM comprobante;
DELETE FROM recibo_linea;
DELETE FROM recibo;
DELETE FROM movimiento_caja;
DELETE FROM sesion_caja;
DELETE FROM movimiento_inventario;
DELETE FROM auditoria;
DELETE FROM cliente;
DELETE FROM usuario WHERE nombre IN ('CARLOS', 'MARIA', 'PEDRO');
DELETE FROM producto_variante;
DELETE FROM producto;            -- la app vuelve a sembrar los 42 productos al iniciar (Initialize)
UPDATE configuracion SET next_receipt_number = 1, next_shift_number = 1 WHERE id = 1;
SET FOREIGN_KEY_CHECKS = 1;
```

Notas:
- Borrar `producto` y `producto_variante` deja el catálogo en blanco: el script llama a `AppData.Initialize()`, que lo vuelve a
  sembrar solo si la tabla `producto` está vacía (42 productos, con MANO SAUNA y sin stock). Si prefieres conservar el
  catálogo, no lo borres, pero entonces restablece antes `stock`, `stock_inicial`, `stock_minimo` y `controla_inventario` a 0
  (en producto y producto_variante), los precios originales (MARCIANOS 2.00) y vuelve a crear MANO SAUNA, o el script fallará.
- Se conserva la dueña (id 1).

Luego ejecuta, con la app compilada (`dotnet build`) y XAMPP encendido:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Braya\PR lap\GPTI\EdenPOS\devdb\seed\GenerarDatosPrueba.ps1"
```

Parámetros opcionales: `-Connection` (otra cadena de conexión, por ejemplo una base de pruebas en el puerto 3307),
`-BinDir`, `-DataPath` (carpeta temporal para el `settings.json` local) y `-Seed` (misma semilla = mismas ventas).
El historial se calcula respecto a la fecha en que se ejecuta (14 días cerrados + hoy abierto), y el turno de hoy se abre 3 horas
antes de la hora actual, así que conviene ejecutarlo pasadas las 03:00.
