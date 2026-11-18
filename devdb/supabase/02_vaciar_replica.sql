-- =====================================================================
-- !!!  ATENCION: ESTE SCRIPT BORRA TODA LA REPLICA DE EDENPOS EN SUPABASE  !!!
-- Vacia (TRUNCATE) las 16 tablas de datos y _replica_info del esquema edenpos.
-- No se puede deshacer. Los datos de MariaDB (la base principal) NO se tocan.
--
-- Cuando usarlo: EdenPOS muestra "Bloqueada" porque la replica contiene datos
-- de OTRA base o de otra instalacion y usted quiere empezar de cero. Despues
-- de ejecutarlo, pulse "Subir ahora" en EdenPOS para volver a subir todo.
-- Si la replica tiene la unica copia buena de sus datos, NO lo ejecute:
-- use antes "Restaurar desde Supabase".
--
-- Ejecutar en Supabase > SQL Editor (como usuario postgres).
-- =====================================================================

TRUNCATE TABLE
  edenpos.rol,
  edenpos.usuario,
  edenpos.cliente,
  edenpos.producto,
  edenpos.producto_variante,
  edenpos.ticket_guardado,
  edenpos.casillero_llave,
  edenpos.ticket_linea,
  edenpos.sesion_caja,
  edenpos.movimiento_caja,
  edenpos.recibo,
  edenpos.recibo_linea,
  edenpos.comprobante,
  edenpos.movimiento_inventario,
  edenpos.auditoria,
  edenpos.configuracion,
  edenpos._replica_info;

-- Comprobacion: todas las filas deben mostrar 0.
SELECT edenpos. || relname AS tabla, n_live_tup AS filas_estimadas
FROM pg_stat_user_tables WHERE schemaname = edenpos ORDER BY relname;
