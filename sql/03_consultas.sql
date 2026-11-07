-- =====================================================================
-- 03_consultas.sql
-- Consultas de odaxfarma_compras. Ejecutar después de 02_insertar_datos.sql.
-- Ejecutar de a una (Ctrl + Enter en Workbench) para explicarlas en el video.
-- =====================================================================

USE odaxfarma_compras;

-- ---------------------------------------------------------------------
-- C1. Trazabilidad completa: requerimiento -> cotización -> orden -> pago / guía
--     (LEFT JOIN para que aparezcan también las cotizaciones sin orden
--      y las órdenes sin pago o sin guía)
-- ---------------------------------------------------------------------
SELECT r.num_requerimiento,
       c.num_cotizacion,
       p.razon_social      AS proveedor,
       c.moneda,
       o.num_orden,
       o.fecha_emision,
       o.monto_total,
       pg.num_solicitud,
       pg.fecha_solicitud,
       g.num_guia,
       g.fecha_traslado
FROM tb_requerimiento_compra r
JOIN tb_cotizacion   c  ON c.num_requerimiento = r.num_requerimiento
JOIN tb_proveedor    p  ON p.ruc_proveedor     = c.ruc_proveedor
LEFT JOIN tb_orden_compra  o  ON o.num_cotizacion = c.num_cotizacion
LEFT JOIN tb_pago          pg ON pg.num_orden     = o.num_orden
LEFT JOIN tb_guia_remision g  ON g.num_orden      = o.num_orden
ORDER BY r.num_requerimiento, c.num_cotizacion, pg.num_solicitud;

-- ---------------------------------------------------------------------
-- C2. Total comprado por proveedor y moneda
--     (el proveedor de la orden se obtiene por su cotización)
-- ---------------------------------------------------------------------
SELECT p.ruc_proveedor,
       p.razon_social,
       c.moneda,
       COUNT(o.num_orden)  AS cantidad_ordenes,
       SUM(o.monto_total)  AS total_comprado
FROM tb_orden_compra o
JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
JOIN tb_proveedor  p ON p.ruc_proveedor  = c.ruc_proveedor
GROUP BY p.ruc_proveedor, p.razon_social, c.moneda
ORDER BY total_comprado DESC;

-- ---------------------------------------------------------------------
-- C3. Órdenes pendientes: sin pago o sin guía de remisión
--     (es justo el punto donde hoy se corta el proceso en Excel)
-- ---------------------------------------------------------------------
SELECT o.num_orden,
       p.razon_social AS proveedor,
       o.fecha_emision,
       o.monto_total,
       CASE WHEN NOT EXISTS (SELECT 1 FROM tb_pago pg WHERE pg.num_orden = o.num_orden)
            THEN 'SIN PAGO' ELSE 'con pago' END AS estado_pago,
       CASE WHEN NOT EXISTS (SELECT 1 FROM tb_guia_remision g WHERE g.num_orden = o.num_orden)
            THEN 'SIN GUÍA' ELSE 'con guía' END AS estado_recepcion
FROM tb_orden_compra o
JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
JOIN tb_proveedor  p ON p.ruc_proveedor  = c.ruc_proveedor
WHERE NOT EXISTS (SELECT 1 FROM tb_pago pg WHERE pg.num_orden = o.num_orden)
   OR NOT EXISTS (SELECT 1 FROM tb_guia_remision g WHERE g.num_orden = o.num_orden);

-- Versión con LEFT JOIN ... IS NULL (solo órdenes sin guía)
SELECT o.num_orden, o.fecha_emision
FROM tb_orden_compra o
LEFT JOIN tb_guia_remision g ON g.num_orden = o.num_orden
WHERE g.num_guia IS NULL;

-- ---------------------------------------------------------------------
-- C4. Ordenado vs recibido por producto (detecta entregas incompletas)
-- ---------------------------------------------------------------------
SELECT d.num_orden,
       pr.descripcion,
       pr.unidad_medida,
       d.cantidad_ordenada,
       COALESCE(SUM(dg.cantidad_recibida), 0)                       AS cantidad_recibida,
       d.cantidad_ordenada - COALESCE(SUM(dg.cantidad_recibida), 0) AS pendiente
FROM tb_detalle_orden_compra d
JOIN tb_producto pr ON pr.codigo_producto = d.codigo_producto
LEFT JOIN tb_guia_remision g  ON g.num_orden = d.num_orden
LEFT JOIN tb_detalle_guia  dg ON dg.num_guia = g.num_guia
                             AND dg.codigo_producto = d.codigo_producto
GROUP BY d.num_orden, pr.descripcion, pr.unidad_medida, d.cantidad_ordenada
ORDER BY d.num_orden, pendiente DESC;

-- ---------------------------------------------------------------------
-- C5. Saldo por pagar de cada orden (una orden puede pagarse en partes)
-- ---------------------------------------------------------------------
SELECT o.num_orden,
       c.moneda,
       o.monto_total,
       COALESCE(SUM(CASE WHEN c.moneda = 'PEN' THEN pg.monto_soles
                         ELSE pg.monto_dolares END), 0) AS total_pagado,
       o.monto_total - COALESCE(SUM(CASE WHEN c.moneda = 'PEN' THEN pg.monto_soles
                                         ELSE pg.monto_dolares END), 0) AS saldo
FROM tb_orden_compra o
JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
LEFT JOIN tb_pago pg ON pg.num_orden = o.num_orden
GROUP BY o.num_orden, c.moneda, o.monto_total
ORDER BY saldo DESC;

-- ---------------------------------------------------------------------
-- C6. Precio con IGV calculado (vista) y comparación de cotizaciones
--     de un mismo requerimiento para elegir la más barata
-- ---------------------------------------------------------------------
SELECT * FROM vw_cotizacion_con_igv WHERE num_cotizacion = 'COT-GK-014';

SELECT c.num_requerimiento,
       c.num_cotizacion,
       p.razon_social,
       c.moneda,
       SUM(v.total_linea_con_igv) AS total_con_igv,
       CASE WHEN o.num_orden IS NULL THEN 'No aprobada' ELSE 'Aprobada' END AS resultado
FROM tb_cotizacion c
JOIN tb_proveedor p          ON p.ruc_proveedor  = c.ruc_proveedor
JOIN vw_cotizacion_con_igv v ON v.num_cotizacion = c.num_cotizacion
LEFT JOIN tb_orden_compra o  ON o.num_cotizacion = c.num_cotizacion
WHERE c.num_requerimiento = 'P05-2026'
GROUP BY c.num_requerimiento, c.num_cotizacion, p.razon_social, c.moneda, o.num_orden
ORDER BY total_con_igv;

-- ---------------------------------------------------------------------
-- C7. Uso de índices (para la parte de ficheros e índices)
-- ---------------------------------------------------------------------
EXPLAIN SELECT * FROM tb_orden_compra
WHERE fecha_emision BETWEEN '2026-07-01' AND '2026-07-31';   -- usa idx_orden_fecha

EXPLAIN SELECT * FROM tb_detalle_orden_compra
WHERE codigo_producto = 'PFC150';                            -- usa idx_detoc_producto

-- =====================================================================
-- PRUEBAS DE INTEGRIDAD: cada una DEBE FALLAR. Ejecutarlas de a una.
-- =====================================================================

-- I1. FK: orden con una cotización que no existe -> Error 1452
INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion)
VALUES ('RQP99/26', '2026-10-24', 100.00, 'COT-NO-EXISTE');

-- I2. FK con RESTRICT: borrar un proveedor que tiene cotizaciones -> Error 1451
DELETE FROM tb_proveedor WHERE ruc_proveedor = '20610730109';

-- I3. UNIQUE de Genera (1:1): segunda orden para la misma cotización -> Error 1062
INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion)
VALUES ('RQP04/26-B', '2026-07-30', 50.00, 'COT-ALP-001');

-- I4. CHECK: RUC con letras -> Error 3819
INSERT INTO tb_proveedor (ruc_proveedor, razon_social) VALUES ('2061073010X', 'PRUEBA');

-- I5. CHECK: pago ejecutado antes de solicitarse -> Error 3819
INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                     cuenta_origen, cuenta_destino, area_responsable, num_orden)
VALUES ('SOL-PRUEBA', '2026-10-10', '2026-10-01', 10.00, 0.00,
        'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP05/26');

-- I6. CASCADE: al borrar una guía se borran sus detalles (se deshace con ROLLBACK)
START TRANSACTION;
SELECT COUNT(*) AS detalles_antes   FROM tb_detalle_guia WHERE num_guia = 'EG01-0001234';
DELETE FROM tb_guia_remision WHERE num_guia = 'EG01-0001234';
SELECT COUNT(*) AS detalles_despues FROM tb_detalle_guia WHERE num_guia = 'EG01-0001234';
ROLLBACK;
