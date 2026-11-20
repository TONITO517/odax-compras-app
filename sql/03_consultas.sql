-- =====================================================================
-- 03_consultas.sql  (versión Entrega 5)
-- Consultas de verificación y pruebas de integridad de odaxfarma_compras.
--
-- PARTE A: las consultas del sistema son ahora los 12 reportes
--          (procedimientos sp_rep_..., script 07). Aquí se llaman.
-- PARTE B: pruebas de integridad. Cada sentencia DEBE FALLAR con el
--          error indicado. Ejecutarlas de una en una (Ctrl + Enter).
--
-- Corrección de la Entrega 4: las consultas de pagos ya NO consideran
-- pagada una orden solo por tener una solicitud; usan la vista
-- vw_estado_orden, que distingue pago solicitado, ejecutado, parcial,
-- pendiente y el saldo real.
-- =====================================================================

USE odaxfarma_compras;

-- =====================================================================
-- PARTE A. Consultas (reportes)
-- =====================================================================

-- C1. Trazabilidad completa del proceso (antes C1)
CALL sp_rep_01_trazabilidad(NULL);

-- C2. Compras por proveedor y moneda (antes C2)
CALL sp_rep_02_compras_por_proveedor(NULL, NULL);

-- C3. Órdenes pendientes de pago o de recepción (antes C3, corregida)
CALL sp_rep_03_ordenes_pendientes();

-- C4. Ordenado vs recibido por producto (antes C4)
CALL sp_rep_04_ordenado_vs_recibido(NULL);

-- C5. Estado financiero: solicitado vs ejecutado y saldo (antes C5, corregida)
CALL sp_rep_05_estado_financiero();

-- C6. Comparación de cotizaciones con IGV calculado (antes C6)
CALL sp_rep_07_comparar_cotizaciones('P06-2026');

-- Estado real de todas las órdenes (vista)
SELECT num_orden, moneda, monto_total, monto_pagado, monto_por_ejecutar,
       saldo_pendiente, estado_pago, estado_recepcion, estado
FROM vw_estado_orden ORDER BY fecha_emision;

-- C7. Uso de índices
EXPLAIN SELECT num_orden, fecha_emision FROM tb_orden_compra
WHERE fecha_emision BETWEEN '2026-07-01' AND '2026-07-31';      -- idx_orden_fecha

EXPLAIN SELECT * FROM tb_detalle_orden_compra
WHERE codigo_producto = 'PFC150';                               -- idx_detoc_producto

-- =====================================================================
-- PARTE B. Pruebas de integridad (todas DEBEN FALLAR)
-- =====================================================================

-- I1. FK: orden con una cotización que no existe -> Error 1452
INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion)
VALUES ('RQP99/26', '2026-11-20', 100.00, 'COT-NO-EXISTE');

-- I2. Borrado físico bloqueado (borrado lógico) -> Error 1644
DELETE FROM tb_proveedor WHERE ruc_proveedor = '20610730109';

-- I3. UNIQUE de Genera (1:1): segunda orden para la misma cotización -> Error 1062
INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion)
VALUES ('RQP04/26-X', '2026-07-30', 50.00, 'COT-ALP-001');

-- I4. Trigger: RUC con formato inválido -> Error 1644
CALL sp_proveedor_insertar('2061073010X', 'PRUEBA', NULL, NULL);

-- I5. CHECK: pago ejecutado antes de solicitarse -> Error 3819 (ck_pago_fechas)
INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                     cuenta_origen, cuenta_destino, area_responsable, num_orden)
VALUES ('SOL-PRUEBA', '2026-11-10', '2026-11-01', 10.00, 0.00,
        'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP07/26-C');

-- I6. Trigger R3: recibir más de lo ordenado (se ordenaron 400 cajas; se intenta registrar 450) -> Error 1644
CALL sp_detguia_guardar('G003-0090', 'CAJ012', 450.00);

-- I7. Trigger R3: producto que no está en la orden de la guía -> Error 1644
CALL sp_detguia_guardar('G003-0090', 'PFC150', 10.00);

-- I8. Trigger R4: pago en dólares para una orden en soles -> Error 1644
INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                     cuenta_origen, cuenta_destino, area_responsable, num_orden)
VALUES ('SOL-PRUEBA2', '2026-11-10', NULL, 0.00, 50.00,
        'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP07/26-C');

-- I9. Trigger R5: la suma de pagos superaría el total (RQP08/26 ya está pagada) -> Error 1644
CALL sp_pago_solicitar('SOL-PRUEBA3', '2026-11-10', 100.00, 'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP08/26');

-- I10. Regla R6: un pago ejecutado no se puede anular -> Error 1644
CALL sp_pago_anular('SOL-000270-26');

-- I11. Regla R7: no se anula una orden que tiene pagos activos -> Error 1644
CALL sp_orden_anular('RQP06/26-B');

-- I12. Trigger R2: el producto ordenado debe estar en la cotización -> Error 1644
CALL sp_detoc_guardar('RQP07/26-C', 'PFC150', 10.00);

-- I13. Anular una guía devuelve lo recibido a "pendiente" (se deshace con ROLLBACK)
START TRANSACTION;
SELECT num_orden, estado_recepcion FROM vw_estado_orden WHERE num_orden = 'RQP07/26-C';  -- PARCIAL
CALL sp_guia_anular('G003-0090');
SELECT num_orden, estado_recepcion FROM vw_estado_orden WHERE num_orden = 'RQP07/26-C';  -- PENDIENTE
ROLLBACK;
