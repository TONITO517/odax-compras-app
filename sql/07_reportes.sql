-- =====================================================================
-- 07_reportes.sql
-- Entrega 5 - Reportes del aplicativo como procedimientos almacenados.
--
-- 12 reportes; 9 de ellos usan JOIN entre varias tablas (el mínimo
-- exigido es 10 reportes con al menos 6 JOIN).
-- Todos consideran el estado real: solo los pagos EJECUTADOS cuentan como
-- pagados y los documentos ANULADOS no se incluyen (salvo R09 y R11).
-- Los parámetros opcionales se envían como NULL para "todos".
--
-- Ejecutar después de 06. Se puede ejecutar varias veces.
-- =====================================================================

USE odaxfarma_compras;

DROP PROCEDURE IF EXISTS sp_rep_01_trazabilidad;
DROP PROCEDURE IF EXISTS sp_rep_02_compras_por_proveedor;
DROP PROCEDURE IF EXISTS sp_rep_03_ordenes_pendientes;
DROP PROCEDURE IF EXISTS sp_rep_04_ordenado_vs_recibido;
DROP PROCEDURE IF EXISTS sp_rep_05_estado_financiero;
DROP PROCEDURE IF EXISTS sp_rep_06_pagos_por_ejecutar;
DROP PROCEDURE IF EXISTS sp_rep_07_comparar_cotizaciones;
DROP PROCEDURE IF EXISTS sp_rep_08_historial_producto;
DROP PROCEDURE IF EXISTS sp_rep_09_ordenes_por_fecha;
DROP PROCEDURE IF EXISTS sp_rep_10_productos_mas_comprados;
DROP PROCEDURE IF EXISTS sp_rep_11_auditoria;
DROP PROCEDURE IF EXISTS sp_rep_12_productos_sin_cotizar;

DELIMITER $$

-- ---------------------------------------------------------------------
-- R01 (JOIN) Trazabilidad: requerimiento -> cotización -> orden -> pagos -> guías
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_01_trazabilidad(IN p_num_requerimiento VARCHAR(20))
BEGIN
  SELECT r.num_requerimiento                              AS requerimiento,
         DATE_FORMAT(r.fecha_requerimiento, '%Y-%m-%d')   AS fecha_req,
         c.num_cotizacion                                 AS cotizacion,
         p.razon_social                                   AS proveedor,
         c.moneda,
         COALESCE(o.num_orden, 'SIN ORDEN')               AS orden,
         o.monto_total                                    AS total_orden,
         (SELECT GROUP_CONCAT(CONCAT(pg.num_solicitud,
                   IF(pg.fecha_ejecucion IS NULL, ' (solicitado)', ' (ejecutado)'))
                   ORDER BY pg.fecha_solicitud SEPARATOR ', ')
          FROM tb_pago pg
          WHERE pg.num_orden = o.num_orden AND pg.estado = 'ACTIVO') AS pagos,
         (SELECT GROUP_CONCAT(g.num_guia ORDER BY g.fecha_traslado SEPARATOR ', ')
          FROM tb_guia_remision g
          WHERE g.num_orden = o.num_orden AND g.estado = 'ACTIVO')   AS guias,
         v.estado_pago,
         v.estado_recepcion
  FROM tb_requerimiento_compra r
  JOIN tb_cotizacion   c ON c.num_requerimiento = r.num_requerimiento AND c.estado = 'ACTIVO'
  JOIN tb_proveedor    p ON p.ruc_proveedor     = c.ruc_proveedor
  LEFT JOIN tb_orden_compra o ON o.num_cotizacion = c.num_cotizacion AND o.estado = 'ACTIVO'
  LEFT JOIN vw_estado_orden v ON v.num_orden      = o.num_orden
  WHERE r.estado = 'ACTIVO'
    AND (p_num_requerimiento IS NULL OR p_num_requerimiento = '' OR r.num_requerimiento = p_num_requerimiento)
  ORDER BY r.fecha_requerimiento, c.num_cotizacion;
END$$

-- ---------------------------------------------------------------------
-- R02 (JOIN) Compras por proveedor y moneda en un periodo (solo pagos ejecutados)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_02_compras_por_proveedor(IN p_desde DATE, IN p_hasta DATE)
BEGIN
  SELECT p.ruc_proveedor                                  AS ruc,
         p.razon_social                                   AS proveedor,
         c.moneda,
         COUNT(o.num_orden)                               AS ordenes,
         SUM(o.monto_total)                               AS total_ordenado,
         SUM(COALESCE(pg.pagado, 0))                      AS total_pagado,
         SUM(o.monto_total - COALESCE(pg.pagado, 0))      AS saldo
  FROM tb_orden_compra o
  JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
  JOIN tb_proveedor  p ON p.ruc_proveedor  = c.ruc_proveedor
  LEFT JOIN (SELECT num_orden, SUM(monto_soles + monto_dolares) AS pagado
             FROM tb_pago
             WHERE estado = 'ACTIVO' AND fecha_ejecucion IS NOT NULL
             GROUP BY num_orden) pg ON pg.num_orden = o.num_orden
  WHERE o.estado = 'ACTIVO'
    AND (p_desde IS NULL OR o.fecha_emision >= p_desde)
    AND (p_hasta IS NULL OR o.fecha_emision <= p_hasta)
  GROUP BY p.ruc_proveedor, p.razon_social, c.moneda
  ORDER BY c.moneda, total_ordenado DESC;
END$$

-- ---------------------------------------------------------------------
-- R03 Órdenes pendientes de pago o de recepción (desde la vista de estado)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_03_ordenes_pendientes()
BEGIN
  SELECT num_orden                                AS orden,
         DATE_FORMAT(fecha_emision, '%Y-%m-%d')   AS emision,
         razon_social                             AS proveedor,
         moneda,
         monto_total                              AS total,
         monto_pagado                             AS pagado_ejecutado,
         monto_por_ejecutar                       AS solicitado_sin_ejecutar,
         saldo_pendiente                          AS saldo,
         estado_pago,
         estado_recepcion
  FROM vw_estado_orden
  WHERE estado = 'ACTIVO'
    AND (estado_pago <> 'PAGADO' OR estado_recepcion <> 'COMPLETA')
  ORDER BY fecha_emision;
END$$

-- ---------------------------------------------------------------------
-- R04 (JOIN) Ordenado vs recibido por producto (recepciones parciales y varias guías)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_04_ordenado_vs_recibido(IN p_num_orden VARCHAR(20))
BEGIN
  SELECT d.num_orden                                              AS orden,
         p.razon_social                                           AS proveedor,
         d.codigo_producto                                        AS codigo,
         pr.descripcion,
         pr.unidad_medida                                         AS unidad,
         d.cantidad_ordenada                                      AS ordenado,
         COALESCE(SUM(dg.cantidad_recibida), 0)                   AS recibido,
         d.cantidad_ordenada - COALESCE(SUM(dg.cantidad_recibida), 0) AS pendiente,
         COUNT(DISTINCT g.num_guia)                               AS guias,
         CASE
           WHEN COALESCE(SUM(dg.cantidad_recibida), 0) = 0                    THEN 'PENDIENTE'
           WHEN COALESCE(SUM(dg.cantidad_recibida), 0) < d.cantidad_ordenada THEN 'PARCIAL'
           ELSE 'COMPLETO'
         END                                                      AS estado
  FROM tb_detalle_orden_compra d
  JOIN tb_orden_compra o ON o.num_orden      = d.num_orden
  JOIN tb_cotizacion   c ON c.num_cotizacion = o.num_cotizacion
  JOIN tb_proveedor    p ON p.ruc_proveedor  = c.ruc_proveedor
  JOIN tb_producto    pr ON pr.codigo_producto = d.codigo_producto
  LEFT JOIN tb_guia_remision g ON g.num_orden = d.num_orden AND g.estado = 'ACTIVO'
  LEFT JOIN tb_detalle_guia dg ON dg.num_guia = g.num_guia AND dg.codigo_producto = d.codigo_producto
  WHERE o.estado = 'ACTIVO'
    AND (p_num_orden IS NULL OR p_num_orden = '' OR d.num_orden = p_num_orden)
  GROUP BY d.num_orden, p.razon_social, d.codigo_producto, pr.descripcion, pr.unidad_medida, d.cantidad_ordenada
  ORDER BY d.num_orden, pendiente DESC;
END$$

-- ---------------------------------------------------------------------
-- R05 (JOIN) Estado financiero de cada orden: solicitado vs ejecutado y saldo
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_05_estado_financiero()
BEGIN
  SELECT o.num_orden                                         AS orden,
         DATE_FORMAT(o.fecha_emision, '%Y-%m-%d')            AS emision,
         p.razon_social                                      AS proveedor,
         c.moneda,
         o.monto_total                                       AS total,
         COUNT(pg.num_solicitud)                             AS solicitudes,
         COALESCE(SUM(CASE WHEN pg.fecha_ejecucion IS NULL
                           THEN pg.monto_soles + pg.monto_dolares END), 0) AS solicitado_sin_ejecutar,
         COALESCE(SUM(CASE WHEN pg.fecha_ejecucion IS NOT NULL
                           THEN pg.monto_soles + pg.monto_dolares END), 0) AS pagado_ejecutado,
         o.monto_total - COALESCE(SUM(CASE WHEN pg.fecha_ejecucion IS NOT NULL
                           THEN pg.monto_soles + pg.monto_dolares END), 0) AS saldo,
         CASE
           WHEN COALESCE(SUM(CASE WHEN pg.fecha_ejecucion IS NOT NULL
                                  THEN pg.monto_soles + pg.monto_dolares END), 0) = 0 THEN 'PENDIENTE'
           WHEN COALESCE(SUM(CASE WHEN pg.fecha_ejecucion IS NOT NULL
                                  THEN pg.monto_soles + pg.monto_dolares END), 0) < o.monto_total THEN 'PARCIAL'
           ELSE 'PAGADO'
         END                                                 AS estado_pago
  FROM tb_orden_compra o
  JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
  JOIN tb_proveedor  p ON p.ruc_proveedor  = c.ruc_proveedor
  LEFT JOIN tb_pago pg ON pg.num_orden = o.num_orden AND pg.estado = 'ACTIVO'
  WHERE o.estado = 'ACTIVO'
  GROUP BY o.num_orden, o.fecha_emision, p.razon_social, c.moneda, o.monto_total
  ORDER BY saldo DESC;
END$$

-- ---------------------------------------------------------------------
-- R06 (JOIN) Pagos solicitados que todavía no se ejecutan (con días de espera)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_06_pagos_por_ejecutar()
BEGIN
  SELECT pg.num_solicitud                                AS solicitud,
         DATE_FORMAT(pg.fecha_solicitud, '%Y-%m-%d')     AS fecha_solicitud,
         DATEDIFF(CURDATE(), pg.fecha_solicitud)         AS dias_esperando,
         pg.num_orden                                    AS orden,
         p.razon_social                                  AS proveedor,
         c.moneda,
         pg.monto_soles + pg.monto_dolares               AS monto,
         pg.cuenta_destino,
         pg.area_responsable                             AS area
  FROM tb_pago pg
  JOIN tb_orden_compra o ON o.num_orden      = pg.num_orden
  JOIN tb_cotizacion   c ON c.num_cotizacion = o.num_cotizacion
  JOIN tb_proveedor    p ON p.ruc_proveedor  = c.ruc_proveedor
  WHERE pg.estado = 'ACTIVO' AND pg.fecha_ejecucion IS NULL
  ORDER BY pg.fecha_solicitud;
END$$

-- ---------------------------------------------------------------------
-- R07 (JOIN) Comparación de cotizaciones de un requerimiento (con IGV)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_07_comparar_cotizaciones(IN p_num_requerimiento VARCHAR(20))
BEGIN
  SELECT c.num_requerimiento                                               AS requerimiento,
         c.num_cotizacion                                                  AS cotizacion,
         DATE_FORMAT(c.fecha_cotizacion, '%Y-%m-%d')                       AS fecha,
         p.razon_social                                                    AS proveedor,
         c.moneda,
         COUNT(dc.codigo_producto)                                         AS productos,
         ROUND(SUM(dc.cantidad_cotizada * dc.precio_unitario), 2)          AS subtotal,
         ROUND(SUM(dc.cantidad_cotizada * dc.precio_unitario) * 0.18, 2)   AS igv,
         ROUND(SUM(dc.cantidad_cotizada * dc.precio_unitario) * 1.18, 2)   AS total_con_igv,
         COALESCE(o.num_orden, 'NO APROBADA')                              AS orden_generada
  FROM tb_cotizacion c
  JOIN tb_proveedor p           ON p.ruc_proveedor   = c.ruc_proveedor
  JOIN tb_detalle_cotizacion dc ON dc.num_cotizacion = c.num_cotizacion
  LEFT JOIN tb_orden_compra o   ON o.num_cotizacion  = c.num_cotizacion AND o.estado = 'ACTIVO'
  WHERE c.estado = 'ACTIVO'
    AND (p_num_requerimiento IS NULL OR p_num_requerimiento = '' OR c.num_requerimiento = p_num_requerimiento)
  GROUP BY c.num_requerimiento, c.num_cotizacion, c.fecha_cotizacion, p.razon_social, c.moneda, o.num_orden
  ORDER BY c.num_requerimiento, c.moneda, total_con_igv;
END$$

-- ---------------------------------------------------------------------
-- R08 (JOIN) Historial de compras de un producto (proveedor, cantidad y precio)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_08_historial_producto(IN p_codigo VARCHAR(20))
BEGIN
  SELECT pr.codigo_producto                                         AS codigo,
         pr.descripcion,
         o.num_orden                                                AS orden,
         DATE_FORMAT(o.fecha_emision, '%Y-%m-%d')                   AS emision,
         p.razon_social                                             AS proveedor,
         c.moneda,
         d.cantidad_ordenada                                        AS cantidad,
         pr.unidad_medida                                           AS unidad,
         dc.precio_unitario                                         AS precio_sin_igv,
         ROUND(dc.precio_unitario * 1.18, 2)                        AS precio_con_igv,
         ROUND(d.cantidad_ordenada * dc.precio_unitario * 1.18, 2)  AS importe_con_igv
  FROM tb_detalle_orden_compra d
  JOIN tb_orden_compra o        ON o.num_orden        = d.num_orden
  JOIN tb_cotizacion c          ON c.num_cotizacion   = o.num_cotizacion
  JOIN tb_proveedor p           ON p.ruc_proveedor    = c.ruc_proveedor
  JOIN tb_producto pr           ON pr.codigo_producto = d.codigo_producto
  JOIN tb_detalle_cotizacion dc ON dc.num_cotizacion  = c.num_cotizacion
                               AND dc.codigo_producto = d.codigo_producto
  WHERE o.estado = 'ACTIVO'
    AND (p_codigo IS NULL OR p_codigo = '' OR d.codigo_producto = p_codigo)
  ORDER BY pr.descripcion, o.fecha_emision DESC;
END$$

-- ---------------------------------------------------------------------
-- R09 Órdenes emitidas en un rango de fechas (incluye anuladas, con su estado)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_09_ordenes_por_fecha(IN p_desde DATE, IN p_hasta DATE)
BEGIN
  SELECT num_orden                                AS orden,
         DATE_FORMAT(fecha_emision, '%Y-%m-%d')   AS emision,
         num_cotizacion                           AS cotizacion,
         monto_total                              AS total,
         estado
  FROM tb_orden_compra
  WHERE (p_desde IS NULL OR fecha_emision >= p_desde)
    AND (p_hasta IS NULL OR fecha_emision <= p_hasta)
  ORDER BY fecha_emision;
END$$

-- ---------------------------------------------------------------------
-- R10 (JOIN) Productos más comprados (por número de órdenes)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_10_productos_mas_comprados(IN p_top INT)
BEGIN
  DECLARE v_top INT DEFAULT 10;
  IF p_top IS NOT NULL AND p_top > 0 THEN
    SET v_top = p_top;
  END IF;
  SELECT pr.codigo_producto                AS codigo,
         pr.descripcion,
         pr.unidad_medida                  AS unidad,
         COUNT(DISTINCT d.num_orden)       AS ordenes,
         SUM(d.cantidad_ordenada)          AS cantidad_total_ordenada
  FROM tb_detalle_orden_compra d
  JOIN tb_orden_compra o ON o.num_orden        = d.num_orden
  JOIN tb_producto    pr ON pr.codigo_producto = d.codigo_producto
  WHERE o.estado = 'ACTIVO'
  GROUP BY pr.codigo_producto, pr.descripcion, pr.unidad_medida
  ORDER BY ordenes DESC, cantidad_total_ordenada DESC
  LIMIT v_top;
END$$

-- ---------------------------------------------------------------------
-- R11 Auditoría: operaciones registradas por los triggers
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_11_auditoria(IN p_desde DATE, IN p_hasta DATE, IN p_tabla VARCHAR(40))
BEGIN
  SELECT id_auditoria                                AS id,
         DATE_FORMAT(fecha_hora, '%Y-%m-%d %H:%i')   AS fecha_hora,
         usuario,
         tabla,
         operacion,
         clave,
         detalle
  FROM tb_auditoria
  WHERE (p_desde IS NULL OR DATE(fecha_hora) >= p_desde)
    AND (p_hasta IS NULL OR DATE(fecha_hora) <= p_hasta)
    AND (p_tabla IS NULL OR p_tabla = '' OR tabla = p_tabla)
  ORDER BY id_auditoria DESC;
END$$

-- ---------------------------------------------------------------------
-- R12 (JOIN) Productos requeridos que todavía no tienen ninguna cotización
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_rep_12_productos_sin_cotizar(IN p_num_requerimiento VARCHAR(20))
BEGIN
  SELECT dr.num_requerimiento                          AS requerimiento,
         DATE_FORMAT(r.fecha_requerimiento, '%Y-%m-%d') AS fecha_req,
         dr.codigo_producto                            AS codigo,
         pr.descripcion,
         pr.unidad_medida                              AS unidad,
         dr.cantidad_formulada                         AS cantidad_requerida
  FROM tb_detalle_requerimiento dr
  JOIN tb_requerimiento_compra r ON r.num_requerimiento = dr.num_requerimiento
  JOIN tb_producto pr            ON pr.codigo_producto  = dr.codigo_producto
  LEFT JOIN (tb_detalle_cotizacion dc
             JOIN tb_cotizacion c ON c.num_cotizacion = dc.num_cotizacion AND c.estado = 'ACTIVO')
         ON c.num_requerimiento = dr.num_requerimiento AND dc.codigo_producto = dr.codigo_producto
  WHERE r.estado = 'ACTIVO'
    AND dc.codigo_producto IS NULL
    AND (p_num_requerimiento IS NULL OR p_num_requerimiento = '' OR dr.num_requerimiento = p_num_requerimiento)
  ORDER BY dr.num_requerimiento, pr.descripcion;
END$$

DELIMITER ;

-- Comprobación: deben salir 12 reportes
SELECT ROUTINE_NAME AS reporte
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'odaxfarma_compras' AND ROUTINE_NAME LIKE 'sp_rep_%'
ORDER BY ROUTINE_NAME;
