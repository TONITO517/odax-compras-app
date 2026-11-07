-- =====================================================================
-- 05_maestros_sp_triggers.sql
-- Entrega 5 - Lógica del aplicativo para las tablas maestras
-- (tb_proveedor y tb_producto): triggers y procedimientos almacenados.
--
-- Reglas que se implementan:
--   * El aplicativo NO hace INSERT/UPDATE/DELETE directos: llama a estos
--     procedimientos (el usuario odax_app solo tiene SELECT y EXECUTE).
--   * Borrado lógico: "anular" cambia estado a INACTIVO; el borrado físico
--     está bloqueado por trigger para no perder el historial de compras.
--   * Los triggers normalizan los datos y registran cada operación en
--     tb_auditoria (quién, qué y cuándo).
--
-- Ejecutar después de 01_crear_bd.sql y 02_insertar_datos.sql.
-- Se puede ejecutar varias veces.
-- =====================================================================

USE odaxfarma_compras;

DROP TRIGGER IF EXISTS trg_proveedor_bi;
DROP TRIGGER IF EXISTS trg_proveedor_bu;
DROP TRIGGER IF EXISTS trg_proveedor_bd;
DROP TRIGGER IF EXISTS trg_proveedor_ai;
DROP TRIGGER IF EXISTS trg_proveedor_au;
DROP TRIGGER IF EXISTS trg_producto_bi;
DROP TRIGGER IF EXISTS trg_producto_bu;
DROP TRIGGER IF EXISTS trg_producto_bd;
DROP TRIGGER IF EXISTS trg_producto_ai;
DROP TRIGGER IF EXISTS trg_producto_au;

DROP PROCEDURE IF EXISTS sp_proveedor_listar;
DROP PROCEDURE IF EXISTS sp_proveedor_insertar;
DROP PROCEDURE IF EXISTS sp_proveedor_modificar;
DROP PROCEDURE IF EXISTS sp_proveedor_anular;
DROP PROCEDURE IF EXISTS sp_proveedor_reactivar;
DROP PROCEDURE IF EXISTS sp_producto_listar;
DROP PROCEDURE IF EXISTS sp_producto_insertar;
DROP PROCEDURE IF EXISTS sp_producto_modificar;
DROP PROCEDURE IF EXISTS sp_producto_anular;
DROP PROCEDURE IF EXISTS sp_producto_reactivar;

DELIMITER $$

-- =====================================================================
-- TRIGGERS DE tb_proveedor
-- =====================================================================

-- Antes de insertar: normaliza textos y valida el formato del RUC peruano
CREATE TRIGGER trg_proveedor_bi
BEFORE INSERT ON tb_proveedor
FOR EACH ROW
BEGIN
  SET NEW.razon_social = UPPER(TRIM(NEW.razon_social));
  SET NEW.direccion    = NULLIF(TRIM(NEW.direccion), '');
  SET NEW.telefono     = NULLIF(TRIM(NEW.telefono), '');
  IF NEW.ruc_proveedor NOT REGEXP '^(10|15|17|20)[0-9]{9}$' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El RUC debe tener 11 dígitos y empezar con 10, 15, 17 o 20.';
  END IF;
END$$

-- Antes de modificar: el RUC es la clave y no se cambia
CREATE TRIGGER trg_proveedor_bu
BEFORE UPDATE ON tb_proveedor
FOR EACH ROW
BEGIN
  IF NEW.ruc_proveedor <> OLD.ruc_proveedor THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El RUC de un proveedor no se puede modificar.';
  END IF;
  SET NEW.razon_social = UPPER(TRIM(NEW.razon_social));
  SET NEW.direccion    = NULLIF(TRIM(NEW.direccion), '');
  SET NEW.telefono     = NULLIF(TRIM(NEW.telefono), '');
END$$

-- Antes de borrar: se prohíbe el borrado físico (se usa la anulación)
CREATE TRIGGER trg_proveedor_bd
BEFORE DELETE ON tb_proveedor
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'No se permite eliminar proveedores; use la opción Anular.';
END$$

-- Después de insertar: auditoría
CREATE TRIGGER trg_proveedor_ai
AFTER INSERT ON tb_proveedor
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_proveedor', 'INSERTAR', NEW.ruc_proveedor, NEW.razon_social, USER());
END$$

-- Después de modificar: auditoría (distingue modificación, anulación y reactivación)
CREATE TRIGGER trg_proveedor_au
AFTER UPDATE ON tb_proveedor
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_proveedor',
          CASE
            WHEN OLD.estado = 'ACTIVO'   AND NEW.estado = 'INACTIVO' THEN 'ANULAR'
            WHEN OLD.estado = 'INACTIVO' AND NEW.estado = 'ACTIVO'   THEN 'REACTIVAR'
            ELSE 'MODIFICAR'
          END,
          NEW.ruc_proveedor, NEW.razon_social, USER());
END$$

-- =====================================================================
-- TRIGGERS DE tb_producto
-- =====================================================================

CREATE TRIGGER trg_producto_bi
BEFORE INSERT ON tb_producto
FOR EACH ROW
BEGIN
  SET NEW.codigo_producto = UPPER(TRIM(NEW.codigo_producto));
  SET NEW.descripcion     = UPPER(TRIM(NEW.descripcion));
  SET NEW.tipo_envase     = UPPER(TRIM(NEW.tipo_envase));
  SET NEW.unidad_medida   = UPPER(TRIM(NEW.unidad_medida));
END$$

CREATE TRIGGER trg_producto_bu
BEFORE UPDATE ON tb_producto
FOR EACH ROW
BEGIN
  IF NEW.codigo_producto <> OLD.codigo_producto THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El código de un producto no se puede modificar.';
  END IF;
  SET NEW.descripcion   = UPPER(TRIM(NEW.descripcion));
  SET NEW.tipo_envase   = UPPER(TRIM(NEW.tipo_envase));
  SET NEW.unidad_medida = UPPER(TRIM(NEW.unidad_medida));
END$$

CREATE TRIGGER trg_producto_bd
BEFORE DELETE ON tb_producto
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'No se permite eliminar productos; use la opción Anular.';
END$$

CREATE TRIGGER trg_producto_ai
AFTER INSERT ON tb_producto
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_producto', 'INSERTAR', NEW.codigo_producto, NEW.descripcion, USER());
END$$

CREATE TRIGGER trg_producto_au
AFTER UPDATE ON tb_producto
FOR EACH ROW
BEGIN
  INSERT INTO tb_auditoria (tabla, operacion, clave, detalle, usuario)
  VALUES ('tb_producto',
          CASE
            WHEN OLD.estado = 'ACTIVO'   AND NEW.estado = 'INACTIVO' THEN 'ANULAR'
            WHEN OLD.estado = 'INACTIVO' AND NEW.estado = 'ACTIVO'   THEN 'REACTIVAR'
            ELSE 'MODIFICAR'
          END,
          NEW.codigo_producto, NEW.descripcion, USER());
END$$

-- =====================================================================
-- PROCEDIMIENTOS DE tb_proveedor
-- =====================================================================

-- Lista proveedores; busca por RUC o razón social. p_incluir_inactivos = 1 muestra también los anulados
CREATE PROCEDURE sp_proveedor_listar(
  IN p_texto             VARCHAR(100),
  IN p_incluir_inactivos TINYINT
)
BEGIN
  SELECT ruc_proveedor, razon_social, direccion, telefono, estado
  FROM tb_proveedor
  WHERE (p_texto IS NULL OR p_texto = ''
         OR ruc_proveedor LIKE CONCAT('%', p_texto, '%')
         OR razon_social  LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_inactivos = 1 OR estado = 'ACTIVO')
  ORDER BY razon_social;
END$$

CREATE PROCEDURE sp_proveedor_insertar(
  IN p_ruc       CHAR(11),
  IN p_razon     VARCHAR(100),
  IN p_direccion VARCHAR(150),
  IN p_telefono  VARCHAR(15)
)
BEGIN
  IF p_razon IS NULL OR TRIM(p_razon) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La razón social es obligatoria.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_proveedor WHERE ruc_proveedor = p_ruc) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un proveedor registrado con ese RUC.';
  END IF;
  INSERT INTO tb_proveedor (ruc_proveedor, razon_social, direccion, telefono)
  VALUES (TRIM(p_ruc), p_razon, p_direccion, p_telefono);
END$$

CREATE PROCEDURE sp_proveedor_modificar(
  IN p_ruc       CHAR(11),
  IN p_razon     VARCHAR(100),
  IN p_direccion VARCHAR(150),
  IN p_telefono  VARCHAR(15)
)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM tb_proveedor WHERE ruc_proveedor = p_ruc) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor no existe.';
  END IF;
  IF p_razon IS NULL OR TRIM(p_razon) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La razón social es obligatoria.';
  END IF;
  UPDATE tb_proveedor
  SET razon_social = p_razon, direccion = p_direccion, telefono = p_telefono
  WHERE ruc_proveedor = p_ruc;
END$$

-- Borrado lógico
CREATE PROCEDURE sp_proveedor_anular(IN p_ruc CHAR(11))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_proveedor WHERE ruc_proveedor = p_ruc;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor no existe.';
  ELSEIF v_estado = 'INACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor ya está anulado.';
  END IF;
  UPDATE tb_proveedor SET estado = 'INACTIVO' WHERE ruc_proveedor = p_ruc;
END$$

CREATE PROCEDURE sp_proveedor_reactivar(IN p_ruc CHAR(11))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_proveedor WHERE ruc_proveedor = p_ruc;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor no existe.';
  ELSEIF v_estado = 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El proveedor ya está activo.';
  END IF;
  UPDATE tb_proveedor SET estado = 'ACTIVO' WHERE ruc_proveedor = p_ruc;
END$$

-- =====================================================================
-- PROCEDIMIENTOS DE tb_producto
-- =====================================================================

CREATE PROCEDURE sp_producto_listar(
  IN p_texto             VARCHAR(100),
  IN p_incluir_inactivos TINYINT
)
BEGIN
  SELECT codigo_producto, descripcion, tipo_envase, unidad_medida, estado
  FROM tb_producto
  WHERE (p_texto IS NULL OR p_texto = ''
         OR codigo_producto LIKE CONCAT('%', p_texto, '%')
         OR descripcion     LIKE CONCAT('%', p_texto, '%'))
    AND (p_incluir_inactivos = 1 OR estado = 'ACTIVO')
  ORDER BY descripcion;
END$$

CREATE PROCEDURE sp_producto_insertar(
  IN p_codigo      VARCHAR(20),
  IN p_descripcion VARCHAR(100),
  IN p_tipo_envase VARCHAR(30),
  IN p_unidad      VARCHAR(15)
)
BEGIN
  IF p_codigo IS NULL OR TRIM(p_codigo) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El código del producto es obligatorio.';
  END IF;
  IF p_descripcion IS NULL OR TRIM(p_descripcion) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La descripción es obligatoria.';
  END IF;
  IF p_tipo_envase IS NULL OR TRIM(p_tipo_envase) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de envase es obligatorio.';
  END IF;
  IF EXISTS (SELECT 1 FROM tb_producto WHERE codigo_producto = UPPER(TRIM(p_codigo))) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ya existe un producto con ese código.';
  END IF;
  INSERT INTO tb_producto (codigo_producto, descripcion, tipo_envase, unidad_medida)
  VALUES (p_codigo, p_descripcion, p_tipo_envase, p_unidad);
END$$

CREATE PROCEDURE sp_producto_modificar(
  IN p_codigo      VARCHAR(20),
  IN p_descripcion VARCHAR(100),
  IN p_tipo_envase VARCHAR(30),
  IN p_unidad      VARCHAR(15)
)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM tb_producto WHERE codigo_producto = p_codigo) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe.';
  END IF;
  IF p_descripcion IS NULL OR TRIM(p_descripcion) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La descripción es obligatoria.';
  END IF;
  UPDATE tb_producto
  SET descripcion = p_descripcion, tipo_envase = p_tipo_envase, unidad_medida = p_unidad
  WHERE codigo_producto = p_codigo;
END$$

CREATE PROCEDURE sp_producto_anular(IN p_codigo VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_producto WHERE codigo_producto = p_codigo;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe.';
  ELSEIF v_estado = 'INACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto ya está anulado.';
  END IF;
  UPDATE tb_producto SET estado = 'INACTIVO' WHERE codigo_producto = p_codigo;
END$$

CREATE PROCEDURE sp_producto_reactivar(IN p_codigo VARCHAR(20))
BEGIN
  DECLARE v_estado VARCHAR(10);
  SELECT estado INTO v_estado FROM tb_producto WHERE codigo_producto = p_codigo;
  IF v_estado IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto no existe.';
  ELSEIF v_estado = 'ACTIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El producto ya está activo.';
  END IF;
  UPDATE tb_producto SET estado = 'ACTIVO' WHERE codigo_producto = p_codigo;
END$$

DELIMITER ;

-- Comprobación
SELECT ROUTINE_NAME AS procedimiento
FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = 'odaxfarma_compras' AND ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME;

SELECT TRIGGER_NAME AS trigger_creado, EVENT_OBJECT_TABLE AS tabla,
       ACTION_TIMING AS momento, EVENT_MANIPULATION AS evento
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = 'odaxfarma_compras'
ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME;
