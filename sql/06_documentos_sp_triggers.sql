-- =====================================================================
-- 06_documentos_sp_triggers.sql
-- Entrega 5 - Lógica del aplicativo para los documentos del proceso:
-- Requerimiento, Cotización, Orden de compra, Pago y Guía de remisión,
-- con sus tablas de detalle.
--
-- Reglas del negocio implementadas (observaciones 7, 8 y 10 de la E4):
--   R1. Los productos de una cotización deben estar en su requerimiento.
--   R2. Los productos de una orden deben estar en su cotización y no
--       superar la cantidad cotizada.
--   R3. Los productos de una guía deben estar en la orden que sustenta, y
--       lo recibido (sumando todas las guías activas) no puede superar
--       lo ordenado. Se admiten recepciones parciales y varias guías.
--   R4. Cada pago va en una sola moneda: la de la cotización de su orden.
--   R5. Se admiten pagos parciales y anticipados, pero la suma de los
--       pagos activos no puede superar el monto total de la orden.
--   R6. Un pago se SOLICITA (fecha_solicitud) y luego se EJECUTA
--       (fecha_ejecucion). Solo los pagos ejecutados reducen el saldo.
--       Un pago ejecutado no se modifica ni se anula.
--   R7. Borrado lógico: los documentos se ANULAN; el borrado físico está
--       bloqueado. No se anula un documento si otro activo depende de él.
--   R8. Toda operación sobre los documentos queda en tb_auditoria.
--
-- Ejecutar después de 01, 02 y 05. Se puede ejecutar varias veces.
-- =====================================================================

USE odaxfarma_compras;

-- La auditoría también registra la ejecución de pagos
ALTER TABLE tb_auditoria DROP CHECK ck_auditoria_operacion;
ALTER TABLE tb_auditoria ADD CONSTRAINT ck_auditoria_operacion
  CHECK (operacion IN ('INSERTAR', 'MODIFICAR', 'ANULAR', 'REACTIVAR', 'EJECUTAR'));

-- ---------------------------------------------------------------------
-- Limpieza para poder volver a ejecutar el script
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS vw_estado_orden;

DROP TRIGGER IF EXISTS trg_requerimiento_bu;
DROP TRIGGER IF EXISTS trg_requerimiento_bd;
DROP TRIGGER IF EXISTS trg_requerimiento_ai;
DROP TRIGGER IF EXISTS trg_requerimiento_au;
DROP TRIGGER IF EXISTS trg_detreq_bi;
DROP TRIGGER IF EXISTS trg_cotizacion_bi;
DROP TRIGGER IF EXISTS trg_cotizacion_bu;
DROP TRIGGER IF EXISTS trg_cotizacion_bd;
DROP TRIGGER IF EXISTS trg_cotizacion_ai;
DROP TRIGGER IF EXISTS trg_cotizacion_au;
DROP TRIGGER IF EXISTS trg_detcot_bi;
DROP TRIGGER IF EXISTS trg_detcot_bu;
DROP TRIGGER IF EXISTS trg_orden_bi;
DROP TRIGGER IF EXISTS trg_orden_bu;
DROP TRIGGER IF EXISTS trg_orden_bd;
DROP TRIGGER IF EXISTS trg_orden_ai;
DROP TRIGGER IF EXISTS trg_orden_au;
DROP TRIGGER IF EXISTS trg_detoc_bi;
DROP TRIGGER IF EXISTS trg_detoc_bu;
DROP TRIGGER IF EXISTS trg_pago_bi;
DROP TRIGGER IF EXISTS trg_pago_bu;
DROP TRIGGER IF EXISTS trg_pago_bd;
DROP TRIGGER IF EXISTS trg_pago_ai;
DROP TRIGGER IF EXISTS trg_pago_au;
DROP TRIGGER IF EXISTS trg_guia_bi;
DROP TRIGGER IF EXISTS trg_guia_bu;
DROP TRIGGER IF EXISTS trg_guia_bd;
DROP TRIGGER IF EXISTS trg_guia_ai;
DROP TRIGGER IF EXISTS trg_guia_au;
DROP TRIGGER IF EXISTS trg_detguia_bi;
DROP TRIGGER IF EXISTS trg_detguia_bu;

DROP PROCEDURE IF EXISTS sp_combo_proveedores;
DROP PROCEDURE IF EXISTS sp_combo_requerimientos;
DROP PROCEDURE IF EXISTS sp_combo_cotizaciones_sin_orden;
DROP PROCEDURE IF EXISTS sp_combo_ordenes;
DROP PROCEDURE IF EXISTS sp_combo_productos;
DROP PROCEDURE IF EXISTS sp_combo_productos_requerimiento;
DROP PROCEDURE IF EXISTS sp_combo_productos_orden;
DROP PROCEDURE IF EXISTS sp_requerimiento_listar;
DROP PROCEDURE IF EXISTS sp_requerimiento_insertar;
DROP PROCEDURE IF EXISTS sp_requerimiento_modificar;
DROP PROCEDURE IF EXISTS sp_requerimiento_anular;
DROP PROCEDURE IF EXISTS sp_detreq_listar;
DROP PROCEDURE IF EXISTS sp_detreq_guardar;
DROP PROCEDURE IF EXISTS sp_detreq_quitar;
DROP PROCEDURE IF EXISTS sp_cotizacion_listar;
DROP PROCEDURE IF EXISTS sp_cotizacion_insertar;
DROP PROCEDURE IF EXISTS sp_cotizacion_modificar;
DROP PROCEDURE IF EXISTS sp_cotizacion_anular;
DROP PROCEDURE IF EXISTS sp_detcot_listar;
DROP PROCEDURE IF EXISTS sp_detcot_guardar;
DROP PROCEDURE IF EXISTS sp_detcot_quitar;
DROP PROCEDURE IF EXISTS sp_orden_listar;
DROP PROCEDURE IF EXISTS sp_orden_generar;
DROP PROCEDURE IF EXISTS sp_orden_modificar;
DROP PROCEDURE IF EXISTS sp_orden_anular;
DROP PROCEDURE IF EXISTS sp_detoc_listar;
DROP PROCEDURE IF EXISTS sp_detoc_guardar;
DROP PROCEDURE IF EXISTS sp_detoc_quitar;
DROP PROCEDURE IF EXISTS sp_pago_listar;
DROP PROCEDURE IF EXISTS sp_pago_solicitar;
DROP PROCEDURE IF EXISTS sp_pago_modificar;
DROP PROCEDURE IF EXISTS sp_pago_ejecutar;
DROP PROCEDURE IF EXISTS sp_pago_anular;
DROP PROCEDURE IF EXISTS sp_guia_listar;
DROP PROCEDURE IF EXISTS sp_guia_insertar;
DROP PROCEDURE IF EXISTS sp_guia_modificar;
DROP PROCEDURE IF EXISTS sp_guia_anular;
DROP PROCEDURE IF EXISTS sp_detguia_listar;
DROP PROCEDURE IF EXISTS sp_detguia_guardar;
DROP PROCEDURE IF EXISTS sp_detguia_quitar;

-- ---------------------------------------------------------------------
-- Vista: estado real de cada orden (pago y recepción)
--   * monto_pagado: solo pagos ACTIVOS y EJECUTADOS
--   * monto_por_ejecutar: pagos solicitados que aún no se ejecutan
--   * estado_pago: PENDIENTE / PARCIAL / PAGADO (según lo ejecutado)
--   * estado_recepcion: PENDIENTE / PARCIAL / COMPLETA, comparando cada
--     producto por separado (no se suman unidades con kilogramos)
-- ---------------------------------------------------------------------
CREATE VIEW vw_estado_orden AS
SELECT o.num_orden,
       o.fecha_emision,
       o.estado,
       c.num_cotizacion,
       c.num_requerimiento,
       c.moneda,
       p.ruc_proveedor,
       p.razon_social,
       o.monto_total,
       COALESCE(pg.pagado, 0)                    AS monto_pagado,
       COALESCE(pg.por_ejecutar, 0)              AS monto_por_ejecutar,
       o.monto_total - COALESCE(pg.pagado, 0)    AS saldo_pendiente,
       CASE
         WHEN COALESCE(pg.pagado, 0) = 0             THEN 'PENDIENTE'
         WHEN COALESCE(pg.pagado, 0) < o.monto_total THEN 'PARCIAL'
         ELSE 'PAGADO'
       END AS estado_pago,
       CASE
         WHEN COALESCE(rc.items_con_recepcion, 0) = 0 THEN 'PENDIENTE'
         WHEN rc.items_completos = rc.items           THEN 'COMPLETA'
         ELSE 'PARCIAL'
       END AS estado_recepcion
FROM tb_orden_compra o
JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
JOIN tb_proveedor  p ON p.ruc_proveedor  = c.ruc_proveedor
LEFT JOIN (
  SELECT num_orden,
         SUM(CASE WHEN fecha_ejecucion IS NOT NULL THEN monto_soles + monto_dolares ELSE 0 END) AS pagado,
         SUM(CASE WHEN fecha_ejecucion IS NULL     THEN monto_soles + monto_dolares ELSE 0 END) AS por_ejecutar
  FROM tb_pago
  WHERE estado = 'ACTIVO'
  GROUP BY num_orden
) pg ON pg.num_orden = o.num_orden
LEFT JOIN (
  SELECT x.num_orden,
         COUNT(*)                                     AS items,
         SUM(x.recibido > 0)                          AS items_con_recepcion,
         SUM(x.recibido >= x.cantidad_ordenada)       AS items_completos
  FROM (
    SELECT d.num_orden, d.codigo_producto, d.cantidad_ordenada,
           COALESCE(SUM(dg.cantidad_recibida), 0) AS recibido
    FROM tb_detalle_orden_compra d
    LEFT JOIN tb_guia_remision g
           ON g.num_orden = d.num_orden AND g.estado = 'ACTIVO'
    LEFT JOIN tb_detalle_guia dg
           ON dg.num_guia = g.num_guia AND dg.codigo_producto = d.codigo_producto
    GROUP BY d.num_orden, d.codigo_producto, d.cantidad_ordenada
  ) x
  GROUP BY x.num_orden
) rc ON rc.num_orden = o.num_orden;

DELIMITER $$

-- =====================================================================
-- TRIGGERS
-- =====================================================================

-- ---------------- Requerimiento ----------------
CREATE TRIGGER trg_requerimiento_bu
BEFORE UPDATE ON tb_requerimiento_compra
FOR EACH ROW
BEGIN
  IF NEW.num_requerimiento <> OLD.num_requerimiento THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número del requerimiento no se puede modificar.';
  END IF;
END$$

CREATE TRIGGER trg_requerimiento_bd
BEFORE DELETE ON tb_requerimiento_compra
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se permite eliminar requerimientos; use la opción Anular.';
END$$

CREATE TRIGGER trg_requerimiento_ai
AFTER INSERT ON tb_requerimiento_compra
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_requerimiento_compra', 'INSERTAR', NEW.num_requerimiento, NEW.area_responsable, USER());
END$$

CREATE TRIGGER trg_requerimiento_au
AFTER UPDATE ON tb_requerimiento_compra
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_requerimiento_compra',
          IF(OLD.estado = 'ACTIVO' AND NEW.estado = 'ANULADO', 'ANULAR', 'MODIFICAR'),
          NEW.num_requerimiento, NEW.area_responsable, USER());
END$$

-- Detalle del requerimiento: solo productos activos y requerimientos activos
CREATE TRIGGER trg_detreq_bi
BEFORE INSERT ON tb_detalle_requerimiento
FOR EACH ROW
BEGIN
  IF (SELECT estado FROM tb_producto WHERE codigo_producto = NEW.codigo_producto) <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto está anulado; no se puede requerir.';
  END IF;
  IF (SELECT estado FROM tb_requerimiento_compra WHERE num_requerimiento = NEW.num_requerimiento) <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento está anulado.';
  END IF;
END$$

-- ---------------- Cotización ----------------
CREATE TRIGGER trg_cotizacion_bi
BEFORE INSERT ON tb_cotizacion
FOR EACH ROW
BEGIN
  DECLARE v_fecha_req DATE;
  DECLARE v_estado_req VARCHAR(10);
  SELECT fecha_requerimiento, estado INTO v_fecha_req, v_estado_req
  FROM tb_requerimiento_compra WHERE num_requerimiento = NEW.num_requerimiento;
  IF v_estado_req <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento está anulado; no se puede cotizar.';
  END IF;
  IF NEW.fecha_cotizacion < v_fecha_req THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la cotización no puede ser anterior a la del requerimiento.';
  END IF;
  IF (SELECT estado FROM tb_proveedor WHERE ruc_proveedor = NEW.ruc_proveedor) <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor está anulado; no se puede registrar su cotización.';
  END IF;
END$$

CREATE TRIGGER trg_cotizacion_bu
BEFORE UPDATE ON tb_cotizacion
FOR EACH ROW
BEGIN
  IF NEW.num_cotizacion <> OLD.num_cotizacion THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de la cotización no se puede modificar.';
  END IF;
END$$

CREATE TRIGGER trg_cotizacion_bd
BEFORE DELETE ON tb_cotizacion
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se permite eliminar cotizaciones; use la opción Anular.';
END$$

CREATE TRIGGER trg_cotizacion_ai
AFTER INSERT ON tb_cotizacion
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_cotizacion', 'INSERTAR', NEW.num_cotizacion,
          CONCAT('Req. ', NEW.num_requerimiento, ' - RUC ', NEW.ruc_proveedor, ' - ', NEW.moneda), USER());
END$$

CREATE TRIGGER trg_cotizacion_au
AFTER UPDATE ON tb_cotizacion
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_cotizacion',
          IF(OLD.estado = 'ACTIVO' AND NEW.estado = 'ANULADO', 'ANULAR', 'MODIFICAR'),
          NEW.num_cotizacion,
          CONCAT('Req. ', NEW.num_requerimiento, ' - RUC ', NEW.ruc_proveedor, ' - ', NEW.moneda), USER());
END$$

-- R1: el producto cotizado debe estar en el requerimiento de la cotización
CREATE TRIGGER trg_detcot_bi
BEFORE INSERT ON tb_detalle_cotizacion
FOR EACH ROW
BEGIN
  DECLARE v_req VARCHAR(20);
  DECLARE v_estado VARCHAR(10);
  SELECT num_requerimiento, estado INTO v_req, v_estado
  FROM tb_cotizacion WHERE num_cotizacion = NEW.num_cotizacion;
  IF v_estado <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización está anulada.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_cotizacion = NEW.num_cotizacion) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización ya generó una orden; su detalle no se puede cambiar.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM tb_detalle_requerimiento
                 WHERE num_requerimiento = v_req AND codigo_producto = NEW.codigo_producto) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no figura en el requerimiento de esta cotización.';
  END IF;
END$$

CREATE TRIGGER trg_detcot_bu
BEFORE UPDATE ON tb_detalle_cotizacion
FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_cotizacion = NEW.num_cotizacion) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización ya generó una orden; su detalle no se puede cambiar.';
  END IF;
END$$

-- ---------------- Orden de compra ----------------
CREATE TRIGGER trg_orden_bi
BEFORE INSERT ON tb_orden_compra
FOR EACH ROW
BEGIN
  DECLARE v_fecha_cot DATE;
  DECLARE v_estado_cot VARCHAR(10);
  SELECT fecha_cotizacion, estado INTO v_fecha_cot, v_estado_cot
  FROM tb_cotizacion WHERE num_cotizacion = NEW.num_cotizacion;
  IF v_estado_cot <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización está anulada; no puede generar una orden.';
  END IF;
  IF NEW.fecha_emision < v_fecha_cot THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la orden no puede ser anterior a la de su cotización.';
  END IF;
END$$

CREATE TRIGGER trg_orden_bu
BEFORE UPDATE ON tb_orden_compra
FOR EACH ROW
BEGIN
  IF NEW.num_orden <> OLD.num_orden OR NEW.num_cotizacion <> OLD.num_cotizacion THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de la orden y su cotización no se pueden modificar.';
  END IF;
END$$

CREATE TRIGGER trg_orden_bd
BEFORE DELETE ON tb_orden_compra
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se permite eliminar órdenes de compra; use la opción Anular.';
END$$

CREATE TRIGGER trg_orden_ai
AFTER INSERT ON tb_orden_compra
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_orden_compra', 'INSERTAR', NEW.num_orden,
          CONCAT('Cot. ', NEW.num_cotizacion, ' - total ', NEW.monto_total), USER());
END$$

CREATE TRIGGER trg_orden_au
AFTER UPDATE ON tb_orden_compra
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_orden_compra',
          IF(OLD.estado = 'ACTIVO' AND NEW.estado = 'ANULADO', 'ANULAR', 'MODIFICAR'),
          NEW.num_orden, CONCAT('Cot. ', NEW.num_cotizacion, ' - total ', NEW.monto_total), USER());
END$$

-- R2: el producto ordenado debe estar en la cotización, sin superar lo cotizado
CREATE TRIGGER trg_detoc_bi
BEFORE INSERT ON tb_detalle_orden_compra
FOR EACH ROW
BEGIN
  DECLARE v_cot VARCHAR(20);
  DECLARE v_estado VARCHAR(10);
  DECLARE v_cotizada DECIMAL(10,2);
  SELECT num_cotizacion, estado INTO v_cot, v_estado
  FROM tb_orden_compra WHERE num_orden = NEW.num_orden;
  IF v_estado <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está anulada.';
  END IF;
  SELECT cantidad_cotizada INTO v_cotizada
  FROM tb_detalle_cotizacion
  WHERE num_cotizacion = v_cot AND codigo_producto = NEW.codigo_producto;
  IF v_cotizada IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no figura en la cotización de esta orden.';
  END IF;
  IF NEW.cantidad_ordenada > v_cotizada THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad ordenada no puede superar la cantidad cotizada.';
  END IF;
END$$

CREATE TRIGGER trg_detoc_bu
BEFORE UPDATE ON tb_detalle_orden_compra
FOR EACH ROW
BEGIN
  DECLARE v_cotizada DECIMAL(10,2);
  DECLARE v_recibido DECIMAL(12,2);
  SELECT dc.cantidad_cotizada INTO v_cotizada
  FROM tb_detalle_cotizacion dc
  JOIN tb_orden_compra o ON o.num_cotizacion = dc.num_cotizacion
  WHERE o.num_orden = NEW.num_orden AND dc.codigo_producto = NEW.codigo_producto;
  IF NEW.cantidad_ordenada > v_cotizada THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad ordenada no puede superar la cantidad cotizada.';
  END IF;
  SELECT COALESCE(SUM(dg.cantidad_recibida), 0) INTO v_recibido
  FROM tb_detalle_guia dg
  JOIN tb_guia_remision g ON g.num_guia = dg.num_guia
  WHERE g.num_orden = NEW.num_orden AND g.estado = 'ACTIVO'
    AND dg.codigo_producto = NEW.codigo_producto;
  IF NEW.cantidad_ordenada < v_recibido THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad ordenada no puede ser menor que lo ya recibido.';
  END IF;
END$$

-- ---------------- Pago ----------------
-- R4, R5 y R6 al insertar
CREATE TRIGGER trg_pago_bi
BEFORE INSERT ON tb_pago
FOR EACH ROW
BEGIN
  DECLARE v_moneda CHAR(3);
  DECLARE v_total DECIMAL(10,2);
  DECLARE v_estado VARCHAR(10);
  DECLARE v_otros DECIMAL(12,2);
  SELECT c.moneda, o.monto_total, o.estado INTO v_moneda, v_total, v_estado
  FROM tb_orden_compra o
  JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
  WHERE o.num_orden = NEW.num_orden;
  IF v_estado <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está anulada; no se le pueden registrar pagos.';
  END IF;
  IF v_moneda = 'PEN' AND (NEW.monto_dolares <> 0 OR NEW.monto_soles <= 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está en soles: el pago debe registrarse solo en soles.';
  END IF;
  IF v_moneda = 'USD' AND (NEW.monto_soles <> 0 OR NEW.monto_dolares <= 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está en dólares: el pago debe registrarse solo en dólares.';
  END IF;
  SELECT COALESCE(SUM(monto_soles + monto_dolares), 0) INTO v_otros
  FROM tb_pago WHERE num_orden = NEW.num_orden AND estado = 'ACTIVO';
  IF NEW.estado = 'ACTIVO' AND v_otros + NEW.monto_soles + NEW.monto_dolares > v_total THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La suma de los pagos superaría el monto total de la orden.';
  END IF;
END$$

-- R4, R5 y R6 al modificar; un pago ejecutado queda bloqueado
CREATE TRIGGER trg_pago_bu
BEFORE UPDATE ON tb_pago
FOR EACH ROW
BEGIN
  DECLARE v_moneda CHAR(3);
  DECLARE v_total DECIMAL(10,2);
  DECLARE v_otros DECIMAL(12,2);
  IF NEW.num_solicitud <> OLD.num_solicitud OR NEW.num_orden <> OLD.num_orden THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de solicitud y su orden no se pueden modificar.';
  END IF;
  IF OLD.fecha_ejecucion IS NOT NULL AND (
       NEW.monto_soles <> OLD.monto_soles OR NEW.monto_dolares <> OLD.monto_dolares
       OR NEW.estado <> OLD.estado OR NOT (NEW.fecha_ejecucion <=> OLD.fecha_ejecucion)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un pago ya ejecutado no se puede modificar ni anular.';
  END IF;
  SELECT c.moneda, o.monto_total INTO v_moneda, v_total
  FROM tb_orden_compra o
  JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
  WHERE o.num_orden = NEW.num_orden;
  IF v_moneda = 'PEN' AND (NEW.monto_dolares <> 0 OR NEW.monto_soles <= 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está en soles: el pago debe registrarse solo en soles.';
  END IF;
  IF v_moneda = 'USD' AND (NEW.monto_soles <> 0 OR NEW.monto_dolares <= 0) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está en dólares: el pago debe registrarse solo en dólares.';
  END IF;
  SELECT COALESCE(SUM(monto_soles + monto_dolares), 0) INTO v_otros
  FROM tb_pago
  WHERE num_orden = NEW.num_orden AND estado = 'ACTIVO' AND num_solicitud <> NEW.num_solicitud;
  IF NEW.estado = 'ACTIVO' AND v_otros + NEW.monto_soles + NEW.monto_dolares > v_total THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La suma de los pagos superaría el monto total de la orden.';
  END IF;
END$$

CREATE TRIGGER trg_pago_bd
BEFORE DELETE ON tb_pago
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se permite eliminar pagos; use la opción Anular.';
END$$

CREATE TRIGGER trg_pago_ai
AFTER INSERT ON tb_pago
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_pago', 'INSERTAR', NEW.num_solicitud,
          CONCAT('Orden ', NEW.num_orden, ' - S/ ', NEW.monto_soles, ' - US$ ', NEW.monto_dolares), USER());
END$$

CREATE TRIGGER trg_pago_au
AFTER UPDATE ON tb_pago
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_pago',
          CASE
            WHEN OLD.estado = 'ACTIVO' AND NEW.estado = 'ANULADO'               THEN 'ANULAR'
            WHEN OLD.fecha_ejecucion IS NULL AND NEW.fecha_ejecucion IS NOT NULL THEN 'EJECUTAR'
            ELSE 'MODIFICAR'
          END,
          NEW.num_solicitud,
          CONCAT('Orden ', NEW.num_orden, ' - S/ ', NEW.monto_soles, ' - US$ ', NEW.monto_dolares), USER());
END$$

-- ---------------- Guía de remisión ----------------
CREATE TRIGGER trg_guia_bi
BEFORE INSERT ON tb_guia_remision
FOR EACH ROW
BEGIN
  DECLARE v_fecha_oc DATE;
  DECLARE v_estado_oc VARCHAR(10);
  SELECT fecha_emision, estado INTO v_fecha_oc, v_estado_oc
  FROM tb_orden_compra WHERE num_orden = NEW.num_orden;
  IF v_estado_oc <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está anulada; no se le pueden registrar guías.';
  END IF;
  IF NEW.fecha_traslado < v_fecha_oc THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de traslado no puede ser anterior a la emisión de la orden.';
  END IF;
  SET NEW.modalidad_traslado = UPPER(TRIM(NEW.modalidad_traslado));
END$$

CREATE TRIGGER trg_guia_bu
BEFORE UPDATE ON tb_guia_remision
FOR EACH ROW
BEGIN
  IF NEW.num_guia <> OLD.num_guia OR NEW.num_orden <> OLD.num_orden THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El número de guía y su orden no se pueden modificar.';
  END IF;
  SET NEW.modalidad_traslado = UPPER(TRIM(NEW.modalidad_traslado));
END$$

CREATE TRIGGER trg_guia_bd
BEFORE DELETE ON tb_guia_remision
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se permite eliminar guías; use la opción Anular.';
END$$

CREATE TRIGGER trg_guia_ai
AFTER INSERT ON tb_guia_remision
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_guia_remision', 'INSERTAR', NEW.num_guia, CONCAT('Orden ', NEW.num_orden), USER());
END$$

CREATE TRIGGER trg_guia_au
AFTER UPDATE ON tb_guia_remision
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_guia_remision',
          IF(OLD.estado = 'ACTIVO' AND NEW.estado = 'ANULADO', 'ANULAR', 'MODIFICAR'),
          NEW.num_guia, CONCAT('Orden ', NEW.num_orden), USER());
END$$

-- R3: el producto recibido debe estar en la orden y no superar lo ordenado
CREATE TRIGGER trg_detguia_bi
BEFORE INSERT ON tb_detalle_guia
FOR EACH ROW
BEGIN
  DECLARE v_orden VARCHAR(20);
  DECLARE v_estado VARCHAR(10);
  DECLARE v_ordenada DECIMAL(10,2);
  DECLARE v_recibido DECIMAL(12,2);
  DECLARE v_msg VARCHAR(200);
  SELECT num_orden, estado INTO v_orden, v_estado
  FROM tb_guia_remision WHERE num_guia = NEW.num_guia;
  IF v_estado <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La guía está anulada.';
  END IF;
  SELECT cantidad_ordenada INTO v_ordenada
  FROM tb_detalle_orden_compra
  WHERE num_orden = v_orden AND codigo_producto = NEW.codigo_producto;
  IF v_ordenada IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no figura en la orden de compra que sustenta la guía.';
  END IF;
  SELECT COALESCE(SUM(dg.cantidad_recibida), 0) INTO v_recibido
  FROM tb_detalle_guia dg
  JOIN tb_guia_remision g ON g.num_guia = dg.num_guia
  WHERE g.num_orden = v_orden AND g.estado = 'ACTIVO'
    AND dg.codigo_producto = NEW.codigo_producto
    AND dg.num_guia <> NEW.num_guia;
  IF v_recibido + NEW.cantidad_recibida > v_ordenada THEN
    SET v_msg = CONCAT('Se recibiría más de lo ordenado (ordenado: ', v_ordenada,
                       '; ya recibido en otras guías: ', v_recibido, ').');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
END$$

CREATE TRIGGER trg_detguia_bu
BEFORE UPDATE ON tb_detalle_guia
FOR EACH ROW
BEGIN
  DECLARE v_orden VARCHAR(20);
  DECLARE v_ordenada DECIMAL(10,2);
  DECLARE v_recibido DECIMAL(12,2);
  DECLARE v_msg VARCHAR(200);
  SELECT num_orden INTO v_orden FROM tb_guia_remision WHERE num_guia = NEW.num_guia;
  SELECT cantidad_ordenada INTO v_ordenada
  FROM tb_detalle_orden_compra
  WHERE num_orden = v_orden AND codigo_producto = NEW.codigo_producto;
  SELECT COALESCE(SUM(dg.cantidad_recibida), 0) INTO v_recibido
  FROM tb_detalle_guia dg
  JOIN tb_guia_remision g ON g.num_guia = dg.num_guia
  WHERE g.num_orden = v_orden AND g.estado = 'ACTIVO'
    AND dg.codigo_producto = NEW.codigo_producto
    AND dg.num_guia <> NEW.num_guia;
  IF v_recibido + NEW.cantidad_recibida > v_ordenada THEN
    SET v_msg = CONCAT('Se recibiría más de lo ordenado (ordenado: ', v_ordenada,
                       '; ya recibido en otras guías: ', v_recibido, ').');
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_msg;
  END IF;
END$$

-- =====================================================================
-- PROCEDIMIENTOS PARA LLENAR LAS LISTAS DESPLEGABLES (combos)
-- =====================================================================
CREATE PROCEDURE sp_combo_proveedores()
BEGIN
  SELECT ruc_proveedor, razon_social FROM tb_proveedor
  WHERE estado = 'ACTIVO' ORDER BY razon_social;
END$$

CREATE PROCEDURE sp_combo_productos()
BEGIN
  SELECT codigo_producto, descripcion FROM tb_producto
  WHERE estado = 'ACTIVO' ORDER BY descripcion;
END$$

CREATE PROCEDURE sp_combo_requerimientos()
BEGIN
  SELECT num_requerimiento, DATE_FORMAT(fecha_requerimiento, '%d/%m/%Y') AS fecha
  FROM tb_requerimiento_compra
  WHERE estado = 'ACTIVO' ORDER BY fecha_requerimiento DESC;
END$$

-- Cotizaciones activas que todavía no generaron orden
CREATE PROCEDURE sp_combo_cotizaciones_sin_orden()
BEGIN
  SELECT c.num_cotizacion, CONCAT(p.razon_social, ' (', c.moneda, ')') AS proveedor
  FROM tb_cotizacion c
  JOIN tb_proveedor p ON p.ruc_proveedor = c.ruc_proveedor
  LEFT JOIN tb_orden_compra o ON o.num_cotizacion = c.num_cotizacion
  WHERE c.estado = 'ACTIVO' AND o.num_orden IS NULL
  ORDER BY c.fecha_cotizacion DESC;
END$$

CREATE PROCEDURE sp_combo_ordenes()
BEGIN
  SELECT num_orden, CONCAT(razon_social, ' (', moneda, ' ', monto_total, ')') AS proveedor
  FROM vw_estado_orden
  WHERE estado = 'ACTIVO' ORDER BY fecha_emision DESC;
END$$

-- Productos que pueden ir en el detalle de una cotización (los de su requerimiento)
CREATE PROCEDURE sp_combo_productos_requerimiento(IN p_num_cotizacion VARCHAR(20))
BEGIN
  SELECT pr.codigo_producto, pr.descripcion
  FROM tb_cotizacion c
  JOIN tb_detalle_requerimiento dr ON dr.num_requerimiento = c.num_requerimiento
  JOIN tb_producto pr ON pr.codigo_producto = dr.codigo_producto
  WHERE c.num_cotizacion = p_num_cotizacion
  ORDER BY pr.descripcion;
END$$

-- Productos que pueden ir en el detalle de una guía (los de su orden)
CREATE PROCEDURE sp_combo_productos_orden(IN p_num_guia VARCHAR(20))
BEGIN
  SELECT pr.codigo_producto, pr.descripcion
  FROM tb_guia_remision g
  JOIN tb_detalle_orden_compra d ON d.num_orden = g.num_orden
  JOIN tb_producto pr ON pr.codigo_producto = d.codigo_producto
  WHERE g.num_guia = p_num_guia
  ORDER BY pr.descripcion;
END$$

-- =====================================================================
-- REQUERIMIENTO DE COMPRA
-- =====================================================================
CREATE PROCEDURE sp_requerimiento_listar(IN p_texto VARCHAR(100), IN p_incluir_anulados TINYINT)
BEGIN
  SELECT r.num_requerimiento,
         DATE_FORMAT(r.fecha_requerimiento, '%Y-%m-%d') AS fecha_requerimiento,
         r.area_responsable,
         COUNT(d.codigo_producto) AS productos,
         r.estado
  FROM tb_requerimiento_compra r
  LEFT JOIN tb_detalle_requerimiento d ON d.num_requerimiento = r.num_requerimiento
  WHERE (p_texto IS NULL OR p_texto = '' OR r.num_requerimiento LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_anulados = 1 OR r.estado = 'ACTIVO')
  GROUP BY r.num_requerimiento, r.fecha_requerimiento, r.area_responsable, r.estado
  ORDER BY r.fecha_requerimiento DESC;
END$$

CREATE PROCEDURE sp_requerimiento_insertar(IN p_num VARCHAR(20), IN p_fecha DATE, IN p_area VARCHAR(50))
BEGIN
  IF p_num IS NULL OR TRIM(p_num) = '' OR p_fecha IS NULL OR p_area IS NULL OR TRIM(p_area) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Número, fecha y área responsable son obligatorios.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_requerimiento_compra WHERE num_requerimiento = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un requerimiento con ese número.';
  END IF;
  INSERT INTO tb_requerimiento_compra (num_requerimiento, fecha_requerimiento, area_responsable)
  VALUES (TRIM(p_num), p_fecha, TRIM(p_area));
END$$

CREATE PROCEDURE sp_requerimiento_modificar(IN p_num VARCHAR(20), IN p_fecha DATE, IN p_area VARCHAR(50))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_requerimiento_compra WHERE num_requerimiento = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento está anulado y no se puede modificar.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_cotizacion WHERE num_requerimiento = p_num
             AND estado = 'ACTIVO' AND fecha_cotizacion < p_fecha) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La nueva fecha quedaría después de una de sus cotizaciones.';
  END IF;
  UPDATE tb_requerimiento_compra
  SET fecha_requerimiento = p_fecha, area_responsable = TRIM(p_area)
  WHERE num_requerimiento = p_num;
END$$

CREATE PROCEDURE sp_requerimiento_anular(IN p_num VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_requerimiento_compra WHERE num_requerimiento = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento ya está anulado.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_cotizacion WHERE num_requerimiento = p_num AND estado = 'ACTIVO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede anular: tiene cotizaciones activas. Anúlelas primero.';
  END IF;
  UPDATE tb_requerimiento_compra SET estado = 'ANULADO' WHERE num_requerimiento = p_num;
END$$

CREATE PROCEDURE sp_detreq_listar(IN p_num VARCHAR(20))
BEGIN
  SELECT d.codigo_producto, p.descripcion, p.unidad_medida, d.cantidad_formulada
  FROM tb_detalle_requerimiento d
  JOIN tb_producto p ON p.codigo_producto = d.codigo_producto
  WHERE d.num_requerimiento = p_num
  ORDER BY p.descripcion;
END$$

-- Agrega el producto o actualiza su cantidad si ya estaba
CREATE PROCEDURE sp_detreq_guardar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20), IN p_cantidad DECIMAL(10,2))
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
  END IF;
  IF (SELECT estado FROM tb_requerimiento_compra WHERE num_requerimiento = p_num) <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El requerimiento está anulado.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_detalle_requerimiento WHERE num_requerimiento = p_num AND codigo_producto = p_codigo) THEN
    UPDATE tb_detalle_requerimiento SET cantidad_formulada = p_cantidad
    WHERE num_requerimiento = p_num AND codigo_producto = p_codigo;
  ELSE
    INSERT INTO tb_detalle_requerimiento (num_requerimiento, codigo_producto, cantidad_formulada)
    VALUES (p_num, p_codigo, p_cantidad);
  END IF;
END$$

CREATE PROCEDURE sp_detreq_quitar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20))
BEGIN
  IF EXISTS (SELECT 1 FROM tb_detalle_cotizacion dc
             JOIN tb_cotizacion c ON c.num_cotizacion = dc.num_cotizacion
             WHERE c.num_requerimiento = p_num AND c.estado = 'ACTIVO'
               AND dc.codigo_producto = p_codigo) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede quitar: el producto ya fue cotizado para este requerimiento.';
  END IF;
  DELETE FROM tb_detalle_requerimiento WHERE num_requerimiento = p_num AND codigo_producto = p_codigo;
END$$

-- =====================================================================
-- COTIZACIÓN
-- =====================================================================
CREATE PROCEDURE sp_cotizacion_listar(IN p_texto VARCHAR(100), IN p_incluir_anulados TINYINT)
BEGIN
  SELECT c.num_cotizacion,
         DATE_FORMAT(c.fecha_cotizacion, '%Y-%m-%d') AS fecha_cotizacion,
         c.moneda,
         c.num_requerimiento,
         c.ruc_proveedor,
         p.razon_social,
         ROUND(COALESCE(SUM(dc.cantidad_cotizada * dc.precio_unitario * 1.18), 0), 2) AS total_con_igv,
         COALESCE(o.num_orden, '') AS num_orden,
         c.estado
  FROM tb_cotizacion c
  JOIN tb_proveedor p ON p.ruc_proveedor = c.ruc_proveedor
  LEFT JOIN tb_detalle_cotizacion dc ON dc.num_cotizacion = c.num_cotizacion
  LEFT JOIN tb_orden_compra o ON o.num_cotizacion = c.num_cotizacion
  WHERE (p_texto IS NULL OR p_texto = ''
         OR c.num_cotizacion LIKE CONCAT('%', p_texto, '%')
         OR c.num_requerimiento LIKE CONCAT('%', p_texto, '%')
         OR p.razon_social LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_anulados = 1 OR c.estado = 'ACTIVO')
  GROUP BY c.num_cotizacion, c.fecha_cotizacion, c.moneda, c.num_requerimiento,
           c.ruc_proveedor, p.razon_social, o.num_orden, c.estado
  ORDER BY c.fecha_cotizacion DESC;
END$$

CREATE PROCEDURE sp_cotizacion_insertar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_moneda CHAR(3),
  IN p_num_req VARCHAR(20), IN p_ruc CHAR(11))
BEGIN
  IF p_num IS NULL OR TRIM(p_num) = '' OR p_fecha IS NULL OR p_num_req IS NULL OR p_ruc IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Número, fecha, requerimiento y proveedor son obligatorios.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_cotizacion WHERE num_cotizacion = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe una cotización con ese número.';
  END IF;
  INSERT INTO tb_cotizacion (num_cotizacion, fecha_cotizacion, moneda, num_requerimiento, ruc_proveedor)
  VALUES (TRIM(p_num), p_fecha, COALESCE(p_moneda, 'PEN'), p_num_req, p_ruc);
END$$

-- Solo se modifica mientras no haya generado una orden
CREATE PROCEDURE sp_cotizacion_modificar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_moneda CHAR(3),
  IN p_num_req VARCHAR(20), IN p_ruc CHAR(11))
BEGIN
  DECLARE v_estado VARCHAR(10);
  DECLARE v_req_actual VARCHAR(20);
  SELECT estado, num_requerimiento INTO v_estado, v_req_actual
  FROM tb_cotizacion WHERE num_cotizacion = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización está anulada y no se puede modificar.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_cotizacion = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización ya generó una orden; no se puede modificar.';
  END IF;
  IF p_num_req <> v_req_actual AND EXISTS (SELECT 1 FROM tb_detalle_cotizacion WHERE num_cotizacion = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Para cambiar el requerimiento, primero quite los productos de la cotización.';
  END IF;
  IF p_fecha < (SELECT fecha_requerimiento FROM tb_requerimiento_compra WHERE num_requerimiento = p_num_req) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la cotización no puede ser anterior a la del requerimiento.';
  END IF;
  UPDATE tb_cotizacion
  SET fecha_cotizacion = p_fecha, moneda = p_moneda, num_requerimiento = p_num_req, ruc_proveedor = p_ruc
  WHERE num_cotizacion = p_num;
END$$

CREATE PROCEDURE sp_cotizacion_anular(IN p_num VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_cotizacion WHERE num_cotizacion = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización ya está anulada.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_cotizacion = p_num AND estado = 'ACTIVO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede anular: generó una orden activa. Anule primero la orden.';
  END IF;
  UPDATE tb_cotizacion SET estado = 'ANULADO' WHERE num_cotizacion = p_num;
END$$

CREATE PROCEDURE sp_detcot_listar(IN p_num VARCHAR(20))
BEGIN
  SELECT d.codigo_producto, p.descripcion, p.unidad_medida,
         d.cantidad_cotizada, d.precio_unitario,
         ROUND(d.precio_unitario * 1.18, 2)                       AS precio_con_igv,
         ROUND(d.cantidad_cotizada * d.precio_unitario * 1.18, 2) AS subtotal_con_igv
  FROM tb_detalle_cotizacion d
  JOIN tb_producto p ON p.codigo_producto = d.codigo_producto
  WHERE d.num_cotizacion = p_num
  ORDER BY p.descripcion;
END$$

CREATE PROCEDURE sp_detcot_guardar(
  IN p_num VARCHAR(20), IN p_codigo VARCHAR(20),
  IN p_cantidad DECIMAL(10,2), IN p_precio DECIMAL(10,2))
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 OR p_precio IS NULL OR p_precio <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad y el precio deben ser mayores que cero.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_detalle_cotizacion WHERE num_cotizacion = p_num AND codigo_producto = p_codigo) THEN
    UPDATE tb_detalle_cotizacion SET cantidad_cotizada = p_cantidad, precio_unitario = p_precio
    WHERE num_cotizacion = p_num AND codigo_producto = p_codigo;
  ELSE
    INSERT INTO tb_detalle_cotizacion (num_cotizacion, codigo_producto, cantidad_cotizada, precio_unitario)
    VALUES (p_num, p_codigo, p_cantidad, p_precio);
  END IF;
END$$

CREATE PROCEDURE sp_detcot_quitar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20))
BEGIN
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_cotizacion = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización ya generó una orden; su detalle no se puede cambiar.';
  END IF;
  DELETE FROM tb_detalle_cotizacion WHERE num_cotizacion = p_num AND codigo_producto = p_codigo;
END$$

-- =====================================================================
-- ORDEN DE COMPRA
-- =====================================================================
CREATE PROCEDURE sp_orden_listar(IN p_texto VARCHAR(100), IN p_incluir_anulados TINYINT)
BEGIN
  SELECT num_orden,
         DATE_FORMAT(fecha_emision, '%Y-%m-%d') AS fecha_emision,
         num_cotizacion,
         razon_social,
         moneda,
         monto_total,
         monto_pagado,
         saldo_pendiente,
         estado_pago,
         estado_recepcion,
         estado
  FROM vw_estado_orden
  WHERE (p_texto IS NULL OR p_texto = ''
         OR num_orden LIKE CONCAT('%', p_texto, '%')
         OR razon_social LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_anulados = 1 OR estado = 'ACTIVO')
  ORDER BY fecha_emision DESC;
END$$

-- Genera la orden a partir de una cotización y copia sus productos.
-- Si no se indica el monto total, se calcula con el IGV (18 %).
CREATE PROCEDURE sp_orden_generar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_num_cot VARCHAR(20), IN p_monto_total DECIMAL(10,2))
BEGIN
  DECLARE v_items INT;
  DECLARE v_monto DECIMAL(10,2);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  IF p_num IS NULL OR TRIM(p_num) = '' OR p_fecha IS NULL OR p_num_cot IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Número, fecha y cotización son obligatorios.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_orden = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe una orden con ese número.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_orden_compra WHERE num_cotizacion = p_num_cot) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esa cotización ya generó una orden (relación 1:1).';
  END IF;
  SELECT COUNT(*), ROUND(SUM(cantidad_cotizada * precio_unitario * 1.18), 2)
  INTO v_items, v_monto
  FROM tb_detalle_cotizacion WHERE num_cotizacion = p_num_cot;
  IF v_items = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cotización no tiene productos.';
  END IF;
  START TRANSACTION;
  INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion)
  VALUES (TRIM(p_num), p_fecha, COALESCE(p_monto_total, v_monto), p_num_cot);
  INSERT INTO tb_detalle_orden_compra (num_orden, codigo_producto, cantidad_ordenada)
  SELECT TRIM(p_num), codigo_producto, cantidad_cotizada
  FROM tb_detalle_cotizacion WHERE num_cotizacion = p_num_cot;
  COMMIT;
END$$

CREATE PROCEDURE sp_orden_modificar(IN p_num VARCHAR(20), IN p_fecha DATE, IN p_monto_total DECIMAL(10,2))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_orden_compra WHERE num_orden = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está anulada y no se puede modificar.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_pago WHERE num_orden = p_num AND estado = 'ACTIVO')
     OR EXISTS (SELECT 1 FROM tb_guia_remision WHERE num_orden = p_num AND estado = 'ACTIVO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden ya tiene pagos o guías activas; no se puede modificar.';
  END IF;
  IF p_fecha < (SELECT c.fecha_cotizacion FROM tb_cotizacion c
                JOIN tb_orden_compra o ON o.num_cotizacion = c.num_cotizacion
                WHERE o.num_orden = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la orden no puede ser anterior a la de su cotización.';
  END IF;
  UPDATE tb_orden_compra SET fecha_emision = p_fecha, monto_total = p_monto_total WHERE num_orden = p_num;
END$$

CREATE PROCEDURE sp_orden_anular(IN p_num VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_orden_compra WHERE num_orden = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden ya está anulada.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_pago WHERE num_orden = p_num AND estado = 'ACTIVO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede anular: tiene pagos activos.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_guia_remision WHERE num_orden = p_num AND estado = 'ACTIVO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede anular: tiene guías de remisión activas.';
  END IF;
  UPDATE tb_orden_compra SET estado = 'ANULADO' WHERE num_orden = p_num;
END$$

-- Detalle con lo ordenado, lo recibido (guías activas) y lo pendiente
CREATE PROCEDURE sp_detoc_listar(IN p_num VARCHAR(20))
BEGIN
  SELECT d.codigo_producto, p.descripcion, p.unidad_medida, d.cantidad_ordenada,
         COALESCE(SUM(dg.cantidad_recibida), 0)                       AS cantidad_recibida,
         d.cantidad_ordenada - COALESCE(SUM(dg.cantidad_recibida), 0) AS pendiente
  FROM tb_detalle_orden_compra d
  JOIN tb_producto p ON p.codigo_producto = d.codigo_producto
  LEFT JOIN tb_guia_remision g ON g.num_orden = d.num_orden AND g.estado = 'ACTIVO'
  LEFT JOIN tb_detalle_guia dg ON dg.num_guia = g.num_guia AND dg.codigo_producto = d.codigo_producto
  WHERE d.num_orden = p_num
  GROUP BY d.codigo_producto, p.descripcion, p.unidad_medida, d.cantidad_ordenada
  ORDER BY p.descripcion;
END$$

-- Ajusta la cantidad de un producto de la orden (sin superar lo cotizado)
CREATE PROCEDURE sp_detoc_guardar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20), IN p_cantidad DECIMAL(10,2))
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
  END IF;
  IF (SELECT estado FROM tb_orden_compra WHERE num_orden = p_num) <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden está anulada.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_detalle_orden_compra WHERE num_orden = p_num AND codigo_producto = p_codigo) THEN
    UPDATE tb_detalle_orden_compra SET cantidad_ordenada = p_cantidad
    WHERE num_orden = p_num AND codigo_producto = p_codigo;
  ELSE
    INSERT INTO tb_detalle_orden_compra (num_orden, codigo_producto, cantidad_ordenada)
    VALUES (p_num, p_codigo, p_cantidad);
  END IF;
END$$

CREATE PROCEDURE sp_detoc_quitar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20))
BEGIN
  IF EXISTS (SELECT 1 FROM tb_detalle_guia dg
             JOIN tb_guia_remision g ON g.num_guia = dg.num_guia
             WHERE g.num_orden = p_num AND g.estado = 'ACTIVO' AND dg.codigo_producto = p_codigo) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede quitar: el producto ya tiene recepciones registradas.';
  END IF;
  DELETE FROM tb_detalle_orden_compra WHERE num_orden = p_num AND codigo_producto = p_codigo;
END$$

-- =====================================================================
-- PAGO (solicitar -> ejecutar)
-- =====================================================================
CREATE PROCEDURE sp_pago_listar(IN p_texto VARCHAR(100), IN p_incluir_anulados TINYINT)
BEGIN
  SELECT pg.num_solicitud,
         DATE_FORMAT(pg.fecha_solicitud, '%Y-%m-%d') AS fecha_solicitud,
         COALESCE(DATE_FORMAT(pg.fecha_ejecucion, '%Y-%m-%d'), '') AS fecha_ejecucion,
         pg.num_orden,
         v.razon_social,
         v.moneda,
         pg.monto_soles + pg.monto_dolares AS monto,
         pg.cuenta_origen,
         pg.cuenta_destino,
         pg.area_responsable,
         CASE
           WHEN pg.estado = 'ANULADO'         THEN 'ANULADO'
           WHEN pg.fecha_ejecucion IS NULL    THEN 'SOLICITADO'
           ELSE 'EJECUTADO'
         END AS situacion,
         pg.estado
  FROM tb_pago pg
  JOIN vw_estado_orden v ON v.num_orden = pg.num_orden
  WHERE (p_texto IS NULL OR p_texto = ''
         OR pg.num_solicitud LIKE CONCAT('%', p_texto, '%')
         OR pg.num_orden LIKE CONCAT('%', p_texto, '%')
         OR v.razon_social LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_anulados = 1 OR pg.estado = 'ACTIVO')
  ORDER BY pg.fecha_solicitud DESC;
END$$

-- Registra la solicitud. El monto se guarda en soles o en dólares
-- según la moneda de la cotización de la orden (regla R4).
CREATE PROCEDURE sp_pago_solicitar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_monto DECIMAL(10,2),
  IN p_cuenta_origen VARCHAR(50), IN p_cuenta_destino VARCHAR(30),
  IN p_area VARCHAR(50), IN p_num_orden VARCHAR(20))
BEGIN
  DECLARE v_moneda CHAR(3);
  IF p_num IS NULL OR TRIM(p_num) = '' OR p_fecha IS NULL OR p_num_orden IS NULL
     OR p_cuenta_origen IS NULL OR p_cuenta_destino IS NULL OR p_area IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Complete todos los datos de la solicitud de pago.';
  END IF;
  IF p_monto IS NULL OR p_monto <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto debe ser mayor que cero.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_pago WHERE num_solicitud = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe una solicitud con ese número.';
  END IF;
  SELECT c.moneda INTO v_moneda
  FROM tb_orden_compra o JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
  WHERE o.num_orden = p_num_orden;
  IF v_moneda IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La orden no existe.';
  END IF;
  INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                       cuenta_origen, cuenta_destino, area_responsable, num_orden)
  VALUES (TRIM(p_num), p_fecha, NULL,
          IF(v_moneda = 'PEN', p_monto, 0), IF(v_moneda = 'USD', p_monto, 0),
          TRIM(p_cuenta_origen), TRIM(p_cuenta_destino), TRIM(p_area), p_num_orden);
END$$

-- Solo se modifica mientras no se haya ejecutado
CREATE PROCEDURE sp_pago_modificar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_monto DECIMAL(10,2),
  IN p_cuenta_origen VARCHAR(50), IN p_cuenta_destino VARCHAR(30), IN p_area VARCHAR(50))
BEGIN
  DECLARE v_estado VARCHAR(10);
  DECLARE v_ejecucion DATE;
  DECLARE v_moneda CHAR(3);
  SELECT pg.estado, pg.fecha_ejecucion, c.moneda INTO v_estado, v_ejecucion, v_moneda
  FROM tb_pago pg
  JOIN tb_orden_compra o ON o.num_orden = pg.num_orden
  JOIN tb_cotizacion c ON c.num_cotizacion = o.num_cotizacion
  WHERE pg.num_solicitud = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud de pago no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud está anulada.';
  ELSEIF v_ejecucion IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un pago ya ejecutado no se puede modificar.';
  END IF;
  IF p_monto IS NULL OR p_monto <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto debe ser mayor que cero.';
  END IF;
  UPDATE tb_pago
  SET fecha_solicitud = p_fecha,
      monto_soles   = IF(v_moneda = 'PEN', p_monto, 0),
      monto_dolares = IF(v_moneda = 'USD', p_monto, 0),
      cuenta_origen = TRIM(p_cuenta_origen), cuenta_destino = TRIM(p_cuenta_destino),
      area_responsable = TRIM(p_area)
  WHERE num_solicitud = p_num;
END$$

-- Registra que la transferencia se realizó (regla R6)
CREATE PROCEDURE sp_pago_ejecutar(IN p_num VARCHAR(20), IN p_fecha_ejecucion DATE)
BEGIN
  DECLARE v_estado VARCHAR(10);
  DECLARE v_ejecucion DATE;
  DECLARE v_solicitud DATE;
  SELECT estado, fecha_ejecucion, fecha_solicitud INTO v_estado, v_ejecucion, v_solicitud
  FROM tb_pago WHERE num_solicitud = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud de pago no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud está anulada; no se puede ejecutar.';
  ELSEIF v_ejecucion IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El pago ya fue ejecutado.';
  END IF;
  IF p_fecha_ejecucion IS NULL OR p_fecha_ejecucion < v_solicitud THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de ejecución no puede ser anterior a la de solicitud.';
  END IF;
  UPDATE tb_pago SET fecha_ejecucion = p_fecha_ejecucion WHERE num_solicitud = p_num;
END$$

-- Solo se anulan solicitudes que no se ejecutaron (regla d)
CREATE PROCEDURE sp_pago_anular(IN p_num VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  DECLARE v_ejecucion DATE;
  SELECT estado, fecha_ejecucion INTO v_estado, v_ejecucion FROM tb_pago WHERE num_solicitud = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud de pago no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La solicitud ya está anulada.';
  ELSEIF v_ejecucion IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Un pago ya ejecutado no se puede anular.';
  END IF;
  UPDATE tb_pago SET estado = 'ANULADO' WHERE num_solicitud = p_num;
END$$

-- =====================================================================
-- GUÍA DE REMISIÓN
-- =====================================================================
CREATE PROCEDURE sp_guia_listar(IN p_texto VARCHAR(100), IN p_incluir_anulados TINYINT)
BEGIN
  SELECT g.num_guia,
         DATE_FORMAT(g.fecha_traslado, '%Y-%m-%d') AS fecha_traslado,
         g.modalidad_traslado,
         g.peso_total,
         g.punto_partida,
         g.punto_llegada,
         g.num_orden,
         v.razon_social,
         g.estado
  FROM tb_guia_remision g
  JOIN vw_estado_orden v ON v.num_orden = g.num_orden
  WHERE (p_texto IS NULL OR p_texto = ''
         OR g.num_guia LIKE CONCAT('%', p_texto, '%')
         OR g.num_orden LIKE CONCAT('%', p_texto, '%')
         OR v.razon_social LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_anulados = 1 OR g.estado = 'ACTIVO')
  ORDER BY g.fecha_traslado DESC;
END$$

CREATE PROCEDURE sp_guia_insertar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_modalidad VARCHAR(20), IN p_peso DECIMAL(10,2),
  IN p_partida VARCHAR(150), IN p_llegada VARCHAR(150), IN p_num_orden VARCHAR(20))
BEGIN
  IF p_num IS NULL OR TRIM(p_num) = '' OR p_fecha IS NULL OR p_modalidad IS NULL
     OR p_partida IS NULL OR p_llegada IS NULL OR p_num_orden IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Complete todos los datos de la guía.';
  END IF;
  IF p_peso IS NULL OR p_peso <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El peso debe ser mayor que cero.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_guia_remision WHERE num_guia = p_num) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe una guía con ese número.';
  END IF;
  INSERT INTO tb_guia_remision (num_guia, fecha_traslado, modalidad_traslado, peso_total,
                                punto_partida, punto_llegada, num_orden)
  VALUES (TRIM(p_num), p_fecha, p_modalidad, p_peso, TRIM(p_partida), TRIM(p_llegada), p_num_orden);
END$$

CREATE PROCEDURE sp_guia_modificar(
  IN p_num VARCHAR(20), IN p_fecha DATE, IN p_modalidad VARCHAR(20), IN p_peso DECIMAL(10,2),
  IN p_partida VARCHAR(150), IN p_llegada VARCHAR(150))
BEGIN
  DECLARE v_estado VARCHAR(10);
  DECLARE v_fecha_oc DATE;
  SELECT g.estado, o.fecha_emision INTO v_estado, v_fecha_oc
  FROM tb_guia_remision g JOIN tb_orden_compra o ON o.num_orden = g.num_orden
  WHERE g.num_guia = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La guía no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La guía está anulada y no se puede modificar.';
  END IF;
  IF p_fecha < v_fecha_oc THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de traslado no puede ser anterior a la emisión de la orden.';
  END IF;
  UPDATE tb_guia_remision
  SET fecha_traslado = p_fecha, modalidad_traslado = p_modalidad, peso_total = p_peso,
      punto_partida = TRIM(p_partida), punto_llegada = TRIM(p_llegada)
  WHERE num_guia = p_num;
END$$

CREATE PROCEDURE sp_guia_anular(IN p_num VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_guia_remision WHERE num_guia = p_num;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La guía no existe.';
  ELSEIF v_estado = 'ANULADO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La guía ya está anulada.';
  END IF;
  UPDATE tb_guia_remision SET estado = 'ANULADO' WHERE num_guia = p_num;
END$$

CREATE PROCEDURE sp_detguia_listar(IN p_num VARCHAR(20))
BEGIN
  SELECT dg.codigo_producto, p.descripcion, p.unidad_medida, d.cantidad_ordenada, dg.cantidad_recibida
  FROM tb_detalle_guia dg
  JOIN tb_guia_remision g ON g.num_guia = dg.num_guia
  JOIN tb_detalle_orden_compra d ON d.num_orden = g.num_orden AND d.codigo_producto = dg.codigo_producto
  JOIN tb_producto p ON p.codigo_producto = dg.codigo_producto
  WHERE dg.num_guia = p_num
  ORDER BY p.descripcion;
END$$

CREATE PROCEDURE sp_detguia_guardar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20), IN p_cantidad DECIMAL(10,2))
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cantidad debe ser mayor que cero.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_detalle_guia WHERE num_guia = p_num AND codigo_producto = p_codigo) THEN
    UPDATE tb_detalle_guia SET cantidad_recibida = p_cantidad
    WHERE num_guia = p_num AND codigo_producto = p_codigo;
  ELSE
    INSERT INTO tb_detalle_guia (num_guia, codigo_producto, cantidad_recibida)
    VALUES (p_num, p_codigo, p_cantidad);
  END IF;
END$$

CREATE PROCEDURE sp_detguia_quitar(IN p_num VARCHAR(20), IN p_codigo VARCHAR(20))
BEGIN
  IF (SELECT estado FROM tb_guia_remision WHERE num_guia = p_num) <> 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La guía está anulada.';
  END IF;
  DELETE FROM tb_detalle_guia WHERE num_guia = p_num AND codigo_producto = p_codigo;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Comprobación
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS total_procedimientos
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'odaxfarma_compras' AND ROUTINE_TYPE = 'PROCEDURE';

SELECT COUNT(*) AS total_triggers
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'odaxfarma_compras';

SELECT num_orden, razon_social, moneda, monto_total, monto_pagado, monto_por_ejecutar,
       saldo_pendiente, estado_pago, estado_recepcion
FROM vw_estado_orden;
