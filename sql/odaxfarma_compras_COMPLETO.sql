-- =====================================================================
-- odaxfarma_compras_COMPLETO.sql
-- Script ÚNICO de la base de datos del aplicativo "Odax Farma - Gestión de
-- Órdenes de Compra" (Entrega 5, Gestión de Datos e Información - UCSM).
--
-- Crea TODO desde cero, en este orden:
--   1. Base de datos, tablas, índices y vistas        (01_crear_bd.sql)
--   2. Procedimientos y triggers de maestros          (05_maestros_sp_triggers.sql)
--   3. Procedimientos y triggers de documentos        (06_documentos_sp_triggers.sql)
--   4. Reportes (12 procedimientos, 9 con JOIN)        (07_reportes.sql)
--   5. Datos de prueba reales/orientativos             (02_insertar_datos.sql)
--   6. Datos de prueba adicionales ficticios           (08_datos_adicionales.sql)
--   7. Usuario del aplicativo con mínimo privilegio    (00_usuario_app.sql)
--
-- Requisitos: MySQL 8.0.16 o superior. Ejecutar como root en MySQL Workbench
-- (File > Open SQL Script > botón Execute) o desde CMD:
--   mysql -u root -p --default-character-set=utf8mb4 < odaxfarma_compras_COMPLETO.sql
-- ATENCIÓN: elimina y vuelve a crear la base de datos odaxfarma_compras.
-- =====================================================================


-- #####################################################################
-- 1. BASE DE DATOS, TABLAS, ÍNDICES Y VISTAS
-- #####################################################################

-- =====================================================================
-- 01_crear_bd.sql
-- Base de datos de la funcionalidad "Orden de Compra" - Odax Farma S.R.L.
-- MySQL 8.0 (8.0.16 o superior, por los CHECK) | Motor InnoDB | utf8mb4
-- Esquema: sección 6.12 del informe, con las decisiones por defecto:
--   * sin cantidad_total en el requerimiento (sumaba unidades y kilos)
--   * sin precio_con_igv (se calcula: precio_unitario * 1.18, ver vista)
--   * sin ruc_proveedor en orden y guía (se obtiene por la cotización)
--   * pago con fecha_solicitud y fecha_ejecucion
-- Versión 2 (Entrega 5): columna estado en maestros y documentos para el
--   borrado lógico, y tabla tb_auditoria que llenan los triggers.
-- Se puede ejecutar varias veces: empieza borrando la BD.
-- =====================================================================

DROP DATABASE IF EXISTS odaxfarma_compras;
CREATE DATABASE odaxfarma_compras
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE odaxfarma_compras;

-- ---------------------------------------------------------------------
-- 1. Tablas maestras
-- ---------------------------------------------------------------------
CREATE TABLE tb_proveedor (
  ruc_proveedor  CHAR(11)     NOT NULL,
  razon_social   VARCHAR(100) NOT NULL,
  direccion      VARCHAR(150) NULL,
  telefono       VARCHAR(15)  NULL,
  estado         VARCHAR(10)  NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_proveedor PRIMARY KEY (ruc_proveedor),
  CONSTRAINT ck_proveedor_ruc CHECK (ruc_proveedor REGEXP '^[0-9]{11}$'),
  CONSTRAINT ck_proveedor_estado CHECK (estado IN ('ACTIVO', 'INACTIVO'))
) ENGINE = InnoDB;

CREATE TABLE tb_producto (
  codigo_producto VARCHAR(20)  NOT NULL,
  descripcion     VARCHAR(100) NOT NULL,
  tipo_envase     VARCHAR(30)  NOT NULL,
  unidad_medida   VARCHAR(15)  NOT NULL,
  estado          VARCHAR(10)  NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_producto PRIMARY KEY (codigo_producto),
  CONSTRAINT ck_producto_unidad CHECK (unidad_medida IN ('UNIDAD', 'KG')),
  CONSTRAINT ck_producto_estado CHECK (estado IN ('ACTIVO', 'INACTIVO'))
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 2. Tablas de documentos
-- ---------------------------------------------------------------------
CREATE TABLE tb_requerimiento_compra (
  num_requerimiento   VARCHAR(20) NOT NULL,
  fecha_requerimiento DATE        NOT NULL,
  area_responsable    VARCHAR(50) NOT NULL,
  estado VARCHAR(10) NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_requerimiento PRIMARY KEY (num_requerimiento),
  CONSTRAINT ck_requerimiento_estado CHECK (estado IN ('ACTIVO', 'ANULADO'))
) ENGINE = InnoDB;

CREATE TABLE tb_cotizacion (
  num_cotizacion    VARCHAR(20) NOT NULL,
  fecha_cotizacion  DATE        NOT NULL,
  moneda            CHAR(3)     NOT NULL DEFAULT 'PEN',
  num_requerimiento VARCHAR(20) NOT NULL,
  ruc_proveedor     CHAR(11)    NOT NULL,
  estado VARCHAR(10) NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_cotizacion PRIMARY KEY (num_cotizacion),
  CONSTRAINT ck_cotizacion_estado CHECK (estado IN ('ACTIVO', 'ANULADO')),
  CONSTRAINT ck_cotizacion_moneda CHECK (moneda IN ('PEN', 'USD')),
  CONSTRAINT fk_cotizacion_requerimiento FOREIGN KEY (num_requerimiento)
    REFERENCES tb_requerimiento_compra (num_requerimiento)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_cotizacion_proveedor FOREIGN KEY (ruc_proveedor)
    REFERENCES tb_proveedor (ruc_proveedor)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- Genera (1:1): cada orden sale de una sola cotización y una cotización
-- origina una sola orden -> num_cotizacion NOT NULL + UNIQUE.
-- La moneda de monto_total es la de su cotización.
CREATE TABLE tb_orden_compra (
  num_orden      VARCHAR(20)   NOT NULL,
  fecha_emision  DATE          NOT NULL,
  monto_total    DECIMAL(10,2) NOT NULL,
  num_cotizacion VARCHAR(20)   NOT NULL,
  estado VARCHAR(10) NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_orden_compra PRIMARY KEY (num_orden),
  CONSTRAINT ck_orden_estado CHECK (estado IN ('ACTIVO', 'ANULADO')),
  CONSTRAINT uq_orden_cotizacion UNIQUE (num_cotizacion),
  CONSTRAINT ck_orden_monto CHECK (monto_total > 0),
  CONSTRAINT fk_orden_cotizacion FOREIGN KEY (num_cotizacion)
    REFERENCES tb_cotizacion (num_cotizacion)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- Cancela (N:1): una orden puede pagarse en una o varias solicitudes.
CREATE TABLE tb_pago (
  num_solicitud    VARCHAR(20)   NOT NULL,
  fecha_solicitud  DATE          NOT NULL,
  fecha_ejecucion  DATE          NULL,      -- se llena cuando se transfiere
  monto_soles      DECIMAL(10,2) NOT NULL DEFAULT 0,
  monto_dolares    DECIMAL(10,2) NOT NULL DEFAULT 0,
  cuenta_origen    VARCHAR(50)   NOT NULL,
  cuenta_destino   VARCHAR(30)   NOT NULL,
  area_responsable VARCHAR(50)   NOT NULL,
  num_orden        VARCHAR(20)   NOT NULL,
  estado VARCHAR(10) NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_pago PRIMARY KEY (num_solicitud),
  CONSTRAINT ck_pago_estado CHECK (estado IN ('ACTIVO', 'ANULADO')),
  CONSTRAINT ck_pago_soles   CHECK (monto_soles   >= 0),
  CONSTRAINT ck_pago_dolares CHECK (monto_dolares >= 0),
  CONSTRAINT ck_pago_monto   CHECK (monto_soles > 0 OR monto_dolares > 0),
  CONSTRAINT ck_pago_fechas  CHECK (fecha_ejecucion IS NULL
                                    OR fecha_ejecucion >= fecha_solicitud),
  CONSTRAINT fk_pago_orden FOREIGN KEY (num_orden)
    REFERENCES tb_orden_compra (num_orden)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- Sustenta (N:1): una orden puede llegar en una o varias guías.
CREATE TABLE tb_guia_remision (
  num_guia           VARCHAR(20)   NOT NULL,
  fecha_traslado     DATE          NOT NULL,
  modalidad_traslado VARCHAR(20)   NOT NULL,
  peso_total         DECIMAL(10,2) NOT NULL,
  punto_partida      VARCHAR(150)  NOT NULL,
  punto_llegada      VARCHAR(150)  NOT NULL,
  num_orden          VARCHAR(20)   NOT NULL,
  estado VARCHAR(10) NOT NULL DEFAULT 'ACTIVO',
  CONSTRAINT pk_guia PRIMARY KEY (num_guia),
  CONSTRAINT ck_guia_estado CHECK (estado IN ('ACTIVO', 'ANULADO')),
  CONSTRAINT ck_guia_modalidad CHECK (modalidad_traslado IN ('PRIVADO', 'PUBLICO')),
  CONSTRAINT ck_guia_peso CHECK (peso_total > 0),
  CONSTRAINT fk_guia_orden FOREIGN KEY (num_orden)
    REFERENCES tb_orden_compra (num_orden)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3. Tablas de detalle (relaciones N:M con Producto)
--    detalle -> documento: CASCADE / CASCADE
--    detalle -> producto : RESTRICT / CASCADE
-- ---------------------------------------------------------------------
CREATE TABLE tb_detalle_requerimiento (
  num_requerimiento  VARCHAR(20)   NOT NULL,
  codigo_producto    VARCHAR(20)   NOT NULL,
  cantidad_formulada DECIMAL(10,2) NOT NULL,
  CONSTRAINT pk_detalle_requerimiento PRIMARY KEY (num_requerimiento, codigo_producto),
  CONSTRAINT ck_detreq_cantidad CHECK (cantidad_formulada > 0),
  CONSTRAINT fk_detreq_requerimiento FOREIGN KEY (num_requerimiento)
    REFERENCES tb_requerimiento_compra (num_requerimiento)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_detreq_producto FOREIGN KEY (codigo_producto)
    REFERENCES tb_producto (codigo_producto)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

CREATE TABLE tb_detalle_cotizacion (
  num_cotizacion    VARCHAR(20)   NOT NULL,
  codigo_producto   VARCHAR(20)   NOT NULL,
  cantidad_cotizada DECIMAL(10,2) NOT NULL,
  precio_unitario   DECIMAL(10,2) NOT NULL,   -- sin IGV, en la moneda de la cotización
  CONSTRAINT pk_detalle_cotizacion PRIMARY KEY (num_cotizacion, codigo_producto),
  CONSTRAINT ck_detcot_cantidad CHECK (cantidad_cotizada > 0),
  CONSTRAINT ck_detcot_precio   CHECK (precio_unitario > 0),
  CONSTRAINT fk_detcot_cotizacion FOREIGN KEY (num_cotizacion)
    REFERENCES tb_cotizacion (num_cotizacion)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_detcot_producto FOREIGN KEY (codigo_producto)
    REFERENCES tb_producto (codigo_producto)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

CREATE TABLE tb_detalle_orden_compra (
  num_orden         VARCHAR(20)   NOT NULL,
  codigo_producto   VARCHAR(20)   NOT NULL,
  cantidad_ordenada DECIMAL(10,2) NOT NULL,
  CONSTRAINT pk_detalle_orden PRIMARY KEY (num_orden, codigo_producto),
  CONSTRAINT ck_detoc_cantidad CHECK (cantidad_ordenada > 0),
  CONSTRAINT fk_detoc_orden FOREIGN KEY (num_orden)
    REFERENCES tb_orden_compra (num_orden)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_detoc_producto FOREIGN KEY (codigo_producto)
    REFERENCES tb_producto (codigo_producto)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

CREATE TABLE tb_detalle_guia (
  num_guia          VARCHAR(20)   NOT NULL,
  codigo_producto   VARCHAR(20)   NOT NULL,
  cantidad_recibida DECIMAL(10,2) NOT NULL,
  CONSTRAINT pk_detalle_guia PRIMARY KEY (num_guia, codigo_producto),
  CONSTRAINT ck_detguia_cantidad CHECK (cantidad_recibida > 0),
  CONSTRAINT fk_detguia_guia FOREIGN KEY (num_guia)
    REFERENCES tb_guia_remision (num_guia)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_detguia_producto FOREIGN KEY (codigo_producto)
    REFERENCES tb_producto (codigo_producto)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 3b. Auditoría: la llenan los triggers (inserción, modificación, anulación)
-- ---------------------------------------------------------------------
CREATE TABLE tb_auditoria (
  id_auditoria INT UNSIGNED NOT NULL AUTO_INCREMENT,
  tabla        VARCHAR(40)  NOT NULL,
  operacion    VARCHAR(12)  NOT NULL,
  clave        VARCHAR(40)  NOT NULL,
  detalle      VARCHAR(255) NULL,
  usuario      VARCHAR(100) NOT NULL,
  fecha_hora   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_auditoria PRIMARY KEY (id_auditoria),
  CONSTRAINT ck_auditoria_operacion CHECK (operacion IN ('INSERTAR', 'MODIFICAR', 'ANULAR', 'REACTIVAR', 'EJECUTAR'))
) ENGINE = InnoDB;

-- ---------------------------------------------------------------------
-- 4. Índices secundarios
--    (las PK ya son índice clustered; las FK de una sola columna también
--     necesitan índice y aquí se crean con nombre propio)
-- ---------------------------------------------------------------------
-- Búsquedas por nombre
CREATE INDEX idx_proveedor_razon_social ON tb_proveedor (razon_social);
CREATE INDEX idx_producto_descripcion   ON tb_producto (descripcion);

-- Búsquedas y reportes por fecha
CREATE INDEX idx_requerimiento_fecha ON tb_requerimiento_compra (fecha_requerimiento);
CREATE INDEX idx_cotizacion_fecha    ON tb_cotizacion (fecha_cotizacion);
CREATE INDEX idx_orden_fecha         ON tb_orden_compra (fecha_emision);
CREATE INDEX idx_pago_fecha_solicitud ON tb_pago (fecha_solicitud);
CREATE INDEX idx_guia_fecha          ON tb_guia_remision (fecha_traslado);

-- Claves foráneas
CREATE INDEX idx_cotizacion_requerimiento ON tb_cotizacion (num_requerimiento);
CREATE INDEX idx_cotizacion_proveedor     ON tb_cotizacion (ruc_proveedor);
CREATE INDEX idx_pago_orden               ON tb_pago (num_orden);
CREATE INDEX idx_guia_orden               ON tb_guia_remision (num_orden);
-- (tb_orden_compra.num_cotizacion ya tiene índice por el UNIQUE)

-- Otros
CREATE INDEX idx_pago_cuenta_origen ON tb_pago (cuenta_origen);

-- codigo_producto en los detalles (la PK compuesta empieza por el documento,
-- así que no sirve para buscar por producto)
CREATE INDEX idx_detreq_producto  ON tb_detalle_requerimiento (codigo_producto);
CREATE INDEX idx_detcot_producto  ON tb_detalle_cotizacion (codigo_producto);
CREATE INDEX idx_detoc_producto   ON tb_detalle_orden_compra (codigo_producto);
CREATE INDEX idx_detguia_producto ON tb_detalle_guia (codigo_producto);

-- ---------------------------------------------------------------------
-- 5. Vista: precio con IGV calculado (no se guarda, ver normalización 6.9)
-- ---------------------------------------------------------------------
CREATE VIEW vw_cotizacion_con_igv AS
SELECT dc.num_cotizacion,
       c.moneda,
       dc.codigo_producto,
       dc.cantidad_cotizada,
       dc.precio_unitario                                         AS precio_sin_igv,
       ROUND(dc.precio_unitario * 1.18, 2)                        AS precio_con_igv,
       ROUND(dc.cantidad_cotizada * dc.precio_unitario * 1.18, 2) AS total_linea_con_igv
FROM tb_detalle_cotizacion dc
JOIN tb_cotizacion c ON c.num_cotizacion = dc.num_cotizacion;

-- Comprobación rápida
SHOW TABLES;


-- #####################################################################
-- 2. MAESTROS: PROCEDIMIENTOS Y TRIGGERS
-- #####################################################################

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


-- #####################################################################
-- 3. DOCUMENTOS: PROCEDIMIENTOS, TRIGGERS Y VISTA DE ESTADO
-- #####################################################################

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


-- #####################################################################
-- 4. REPORTES
-- #####################################################################

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


-- #####################################################################
-- 5. DATOS DE PRUEBA (documentos reales y orientativos)
-- #####################################################################

-- =====================================================================
-- 02_insertar_datos.sql
-- Datos de prueba de odaxfarma_compras. Ejecutar después de 01_crear_bd.sql.
--
-- Origen de los datos:
--   [REAL]  tomado de los 5 documentos levantados (OP P04-2026, cotización
--           GK, OC RQP04/26, solicitud de pago P03-2026, guía T001-9342)
--   [ORIENT] orientativo: el documento no se tiene o el dato no figura
--   [FICT]  ficticio, solo para probar casos (2.ª operación de prueba)
--
-- Operaciones cargadas:
--   A) Envases a ALPAPLAS: OC RQP04/26 con su pago, SIN guía todavía
--   B) Insumos a Soluciones Químicas GK: cotización y guía reales, SIN pago
--   C) Envases P05-2026 [FICT]: 2 cotizaciones (una no aprobada),
--      pago en 2 partes y recepción incompleta
-- =====================================================================

USE odaxfarma_compras;

-- (En el script completo la BD se crea vacía, así que no se borra nada.)

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Proveedores
-- ---------------------------------------------------------------------
INSERT INTO tb_proveedor (ruc_proveedor, razon_social, direccion, telefono) VALUES
('20610730109', 'ALPAPLAS', NULL, NULL),                                          -- [REAL] OC RQP04/26
('20602435041', 'SOLUCIONES QUIMICAS GK E.I.R.L.',
                'Calle C Mz. B Lote 44, Urb. Industrial Independencia, Lima', NULL), -- [REAL] guía T001-9342
('20000000001', 'ENVASES DEL SUR S.A.C.', 'Arequipa', '959000001');               -- [FICT]

-- ---------------------------------------------------------------------
-- Productos
-- ---------------------------------------------------------------------
INSERT INTO tb_producto (codigo_producto, descripcion, tipo_envase, unidad_medida) VALUES
-- Los 6 ítems de la OC RQP04/26 [REAL descripción, ORIENT código]
('PFM150', 'POTE FAMILIA MEDIANO / CILINDRO 150GR BLANCO',        'POTE',      'UNIDAD'),
('PTH950', 'POTE TIPO TEHOMA 950GR BLANCO',                       'POTE',      'UNIDAD'),
('TAP130', 'TAPA N° 130 / TAPAS DE KILO',                         'TAPA',      'UNIDAD'),
('PFC150', 'POTE FAMILIA CHICO / POTE FAMILIA CILINDRO 150 GR',   'POTE',      'UNIDAD'),
('TAP060', 'TAPA N° 60 BLANCO / TAPA MAGNESIO',                   'TAPA',      'UNIDAD'),
('CUC010', 'CUCHARITA DOSIFICADORA 10GR NATURAL / TRANSPARENTE',  'CUCHARITA', 'UNIDAD'),
-- Insumos de la cotización y guía de GK [REAL descripción]
('GK00816', 'CARBONATO DE MAGNESIO LIVIANO', 'BOLSA', 'KG'),  -- código [REAL] de la guía
('GK00187', 'SUCRALOSA',                     'BOLSA', 'KG'),  -- código [REAL] de la guía
('GK00866', 'INULINA',                       'BOLSA', 'KG');  -- código [REAL] de la guía

-- ---------------------------------------------------------------------
-- Requerimientos
-- ---------------------------------------------------------------------
INSERT INTO tb_requerimiento_compra (num_requerimiento, fecha_requerimiento, area_responsable) VALUES
('P04-2026', '2026-07-20', 'Área de Producción'),   -- código [REAL], fecha [ORIENT]
('P05-2026', '2026-09-15', 'Área de Producción');   -- [FICT]

-- Cantidades: envases = total de su columna en la Orden de Producción
-- (coincide con la OC); insumos = cantidades de la cotización GK
INSERT INTO tb_detalle_requerimiento (num_requerimiento, codigo_producto, cantidad_formulada) VALUES
('P04-2026', 'PFM150',   680.00),  -- [REAL]
('P04-2026', 'PTH950',   500.00),  -- [REAL]
('P04-2026', 'TAP130',   200.00),  -- [REAL]
('P04-2026', 'PFC150',  1040.00),  -- [REAL] 260 + 780
('P04-2026', 'TAP060',  1040.00),  -- [REAL]
('P04-2026', 'CUC010',  1050.00),  -- [REAL]
('P04-2026', 'GK00816',   16.70),  -- [REAL]
('P04-2026', 'GK00187',    0.35),  -- [REAL]
('P04-2026', 'GK00866',   37.00),  -- [REAL]
('P05-2026', 'PFM150',   400.00),  -- [FICT]
('P05-2026', 'PFC150',   600.00),  -- [FICT]
('P05-2026', 'TAP060',   600.00);  -- [FICT]

-- ---------------------------------------------------------------------
-- Cotizaciones (moneda de la cotización: GK cotiza en dólares)
-- ---------------------------------------------------------------------
INSERT INTO tb_cotizacion (num_cotizacion, fecha_cotizacion, moneda, num_requerimiento, ruc_proveedor) VALUES
('COT-ALP-001', '2026-07-22', 'PEN', 'P04-2026', '20610730109'),  -- [ORIENT] no se tiene el documento
('COT-GK-014',  '2026-07-21', 'USD', 'P04-2026', '20602435041'),  -- detalle [REAL], n.° y fecha [ORIENT]
('COT-ALP-002', '2026-09-17', 'PEN', 'P05-2026', '20610730109'),  -- [FICT]
('COT-EDS-001', '2026-09-17', 'PEN', 'P05-2026', '20000000001');  -- [FICT] no aprobada

INSERT INTO tb_detalle_cotizacion (num_cotizacion, codigo_producto, cantidad_cotizada, precio_unitario) VALUES
-- [ORIENT] precios de envases (la OC real solo trae el total)
('COT-ALP-001', 'PFM150',  680.00, 0.85),
('COT-ALP-001', 'PTH950',  500.00, 1.20),
('COT-ALP-001', 'TAP130',  200.00, 0.40),
('COT-ALP-001', 'PFC150', 1040.00, 0.45),
('COT-ALP-001', 'TAP060', 1040.00, 0.25),
('COT-ALP-001', 'CUC010', 1050.00, 0.27),
-- [REAL] cotización de GK (Figura 2), precios sin IGV en USD
('COT-GK-014', 'GK00816', 16.70,  2.60),
('COT-GK-014', 'GK00187',  0.35, 30.00),
('COT-GK-014', 'GK00866', 37.00,  5.90),
-- [FICT]
('COT-ALP-002', 'PFM150', 400.00, 0.85),
('COT-ALP-002', 'PFC150', 600.00, 0.45),
('COT-ALP-002', 'TAP060', 600.00, 0.25),
('COT-EDS-001', 'PFM150', 400.00, 0.95),
('COT-EDS-001', 'PFC150', 600.00, 0.50),
('COT-EDS-001', 'TAP060', 600.00, 0.28);

-- ---------------------------------------------------------------------
-- Órdenes de compra (una por cotización aprobada)
-- ---------------------------------------------------------------------
INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion) VALUES
('RQP04/26',    '2026-07-27', 2678.85, 'COT-ALP-001'),  -- [REAL] Figura 3 (S/)
('RQP04/26-GK', '2026-07-28',  321.22, 'COT-GK-014'),   -- [ORIENT] n.° pendiente de validar con la empresa (US$)
('RQP05/26',    '2026-09-20',  896.80, 'COT-ALP-002');  -- [FICT] (S/) = 760.00 * 1.18

INSERT INTO tb_detalle_orden_compra (num_orden, codigo_producto, cantidad_ordenada) VALUES
-- [REAL] los 6 ítems y cantidades de la OC RQP04/26
('RQP04/26', 'PFM150',  680.00),
('RQP04/26', 'PTH950',  500.00),
('RQP04/26', 'TAP130',  200.00),
('RQP04/26', 'PFC150', 1040.00),
('RQP04/26', 'TAP060', 1040.00),
('RQP04/26', 'CUC010', 1050.00),
-- insumos GK (mismas cantidades de la cotización y la guía)
('RQP04/26-GK', 'GK00816', 16.70),
('RQP04/26-GK', 'GK00187',  0.35),
('RQP04/26-GK', 'GK00866', 37.00),
-- [FICT]
('RQP05/26', 'PFM150', 400.00),
('RQP05/26', 'PFC150', 600.00),
('RQP05/26', 'TAP060', 600.00);

-- ---------------------------------------------------------------------
-- Pagos
-- ---------------------------------------------------------------------
INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                     cuenta_origen, cuenta_destino, area_responsable, num_orden) VALUES
-- [REAL] Formato P03-2026 (fecha de ejecución no figura en el formato)
('SOL-000209-26', '2026-07-24', NULL, 2678.85, 0.00, 'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP04/26'),
-- [FICT] la orden RQP05/26 se paga en dos partes (adelanto y saldo)
('SOL-000231-26', '2026-09-21', '2026-09-22', 448.40, 0.00, 'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP05/26'),
('SOL-000240-26', '2026-10-05', '2026-10-06', 448.40, 0.00, 'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP05/26');
-- La orden RQP04/26-GK queda sin pago a propósito (para la consulta 3).

-- ---------------------------------------------------------------------
-- Guías de remisión
-- ---------------------------------------------------------------------
INSERT INTO tb_guia_remision (num_guia, fecha_traslado, modalidad_traslado, peso_total,
                              punto_partida, punto_llegada, num_orden) VALUES
-- [REAL] Figura 5
('T001-9342', '2026-08-07', 'PRIVADO', 54.05,
 'Calle C Mz. B Lote 44, Urb. Industrial Independencia, Lima',
 'Av. Néstor Gambeta Mz. H Lote 54, Callao', 'RQP04/26-GK'),
-- [FICT] primera entrega parcial de RQP05/26
('EG01-0001234', '2026-10-08', 'PRIVADO', 38.50,
 'Av. Industrial 120, Lima', 'Mza. F Lote 16, Urb. Residencial La Fonda, Cerro Colorado, Arequipa',
 'RQP05/26');
-- La orden RQP04/26 queda sin guía a propósito (para la consulta 3).

INSERT INTO tb_detalle_guia (num_guia, codigo_producto, cantidad_recibida) VALUES
('T001-9342', 'GK00816', 16.70),   -- [REAL]
('T001-9342', 'GK00187',  0.35),   -- [REAL]
('T001-9342', 'GK00866', 37.00),   -- [REAL]
('EG01-0001234', 'PFM150', 400.00), -- [FICT] completo
('EG01-0001234', 'PFC150', 450.00); -- [FICT] faltan 150; TAP060 no llegó

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobación: filas por tabla
-- ---------------------------------------------------------------------
SELECT 'tb_proveedor' AS tabla, COUNT(*) AS filas FROM tb_proveedor
UNION ALL SELECT 'tb_producto',              COUNT(*) FROM tb_producto
UNION ALL SELECT 'tb_requerimiento_compra',  COUNT(*) FROM tb_requerimiento_compra
UNION ALL SELECT 'tb_detalle_requerimiento', COUNT(*) FROM tb_detalle_requerimiento
UNION ALL SELECT 'tb_cotizacion',            COUNT(*) FROM tb_cotizacion
UNION ALL SELECT 'tb_detalle_cotizacion',    COUNT(*) FROM tb_detalle_cotizacion
UNION ALL SELECT 'tb_orden_compra',          COUNT(*) FROM tb_orden_compra
UNION ALL SELECT 'tb_detalle_orden_compra',  COUNT(*) FROM tb_detalle_orden_compra
UNION ALL SELECT 'tb_pago',                  COUNT(*) FROM tb_pago
UNION ALL SELECT 'tb_guia_remision',         COUNT(*) FROM tb_guia_remision
UNION ALL SELECT 'tb_detalle_guia',          COUNT(*) FROM tb_detalle_guia;


-- #####################################################################
-- 6. DATOS DE PRUEBA ADICIONALES (ficticios)
-- #####################################################################

-- =====================================================================
-- 08_datos_adicionales.sql
-- Entrega 5 - Más datos de prueba para demostrar el aplicativo y los reportes.
--
-- TODOS LOS DATOS DE ESTE ARCHIVO SON FICTICIOS [FICT]: proveedores, RUC,
-- productos, precios y documentos se inventaron para cubrir todos los
-- casos del proceso. No corresponden a documentos de Odax Farma.
--
-- Casos que se cubren:
--   * Orden pagada y recibida completa (RQP06/26-A, en dólares)
--   * Orden con pago parcial: adelanto ejecutado + saldo solicitado sin
--     ejecutar, recibida en DOS guías (RQP06/26-B)
--   * Orden con pago solicitado sin ejecutar y sin recepción (RQP07/26)
--   * Orden sin pagos y con recepción parcial (RQP07/26-C)
--   * Orden pagada pero todavía no recibida (RQP08/26)
--   * Orden ANULADA y recotizada (RQP07/26-B), solicitud de pago ANULADA
--   * Cotizaciones no aprobadas para comparar precios
--   * Requerimiento ANULADO y requerimiento con productos sin cotizar
--   * Proveedor y producto INACTIVOS (borrado lógico)
--
-- Se insertan con los triggers activos, así que todos los datos cumplen
-- las reglas del negocio. Ejecutar después de 02_insertar_datos.sql.
-- =====================================================================

USE odaxfarma_compras;

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Proveedores [FICT]
-- ---------------------------------------------------------------------
INSERT INTO tb_proveedor (ruc_proveedor, razon_social, direccion, telefono) VALUES
('20601234561', 'IMPORTADORA NUTRIFARMA S.A.C.',          'Av. Argentina 1450, Cercado, Lima',              '014567890'),
('20455123987', 'INSUMOS NATURALES DEL SUR S.R.L.',       'Calle Mercaderes 312, Cercado, Arequipa',       '054213344'),
('20539876541', 'DISTRIBUIDORA QUIMICA ANDINA S.A.C.',    'Jr. Huanta 880, Breña, Lima',                    '013322110'),
('20498765432', 'ETIQUETAS Y ENVASES AREQUIPA E.I.R.L.',  'Parque Industrial Mz. C Lote 7, Arequipa',      '054445566'),
('20456789013', 'CAJAS Y CARTONES MISTI S.A.C.',          'Av. Jesús 1203, Paucarpata, Arequipa',          '054778899'),
('20100000017', 'PLASTICOS DEL PACIFICO S.A.',            'Av. Industrial 500, Callao',                     '014001122');

-- ---------------------------------------------------------------------
-- Productos [FICT]
-- ---------------------------------------------------------------------
INSERT INTO tb_producto (codigo_producto, descripcion, tipo_envase, unidad_medida) VALUES
('COL001', 'COLAGENO HIDROLIZADO',               'BOLSA',    'KG'),
('VTC001', 'VITAMINA C (ACIDO ASCORBICO)',       'BOLSA',    'KG'),
('STV001', 'STEVIA EN POLVO',                    'BOLSA',    'KG'),
('MDX001', 'MALTODEXTRINA',                      'SACO',     'KG'),
('ETQ150', 'ETIQUETA ADHESIVA PREVILIFE 150 G',  'ETIQUETA', 'UNIDAD'),
('SLL060', 'SELLO DE INDUCCION N° 60',           'SELLO',    'UNIDAD'),
('CAJ012', 'CAJA DE CARTON X 12 UNIDADES',       'CAJA',     'UNIDAD'),
('PTH750', 'POTE TEHOMA 750 G (DESCONTINUADO)',  'POTE',     'UNIDAD');

-- Borrado lógico de maestros: proveedor y producto que ya no se usan
UPDATE tb_proveedor SET estado = 'INACTIVO' WHERE ruc_proveedor = '20100000017';
UPDATE tb_producto  SET estado = 'INACTIVO' WHERE codigo_producto = 'PTH750';

-- ---------------------------------------------------------------------
-- Requerimientos [FICT]
-- ---------------------------------------------------------------------
INSERT INTO tb_requerimiento_compra (num_requerimiento, fecha_requerimiento, area_responsable) VALUES
('P06-2026', '2026-10-05', 'Área de Producción'),
('P07-2026', '2026-10-20', 'Área de Producción'),
('P08-2026', '2026-11-03', 'Área de Producción'),
('P09-2026', '2026-11-10', 'Área de Producción'),
('P10-2026', '2026-11-15', 'Área de Producción');

INSERT INTO tb_detalle_requerimiento (num_requerimiento, codigo_producto, cantidad_formulada) VALUES
('P06-2026', 'COL001',   50.00),
('P06-2026', 'VTC001',   20.00),
('P06-2026', 'STV001',   25.00),
('P06-2026', 'MDX001',  100.00),
('P07-2026', 'ETQ150', 3000.00),
('P07-2026', 'SLL060', 3000.00),
('P07-2026', 'CAJ012',  400.00),
('P08-2026', 'PFC150', 1500.00),
('P08-2026', 'TAP060', 1500.00),
('P08-2026', 'PFM150',  800.00),
('P09-2026', 'CAJ012',  200.00),
('P10-2026', 'CUC010', 1200.00),
('P10-2026', 'ETQ150', 1200.00),
('P10-2026', 'COL001',   30.00);

-- P09 se registró por error y se anuló (no tiene cotizaciones)
UPDATE tb_requerimiento_compra SET estado = 'ANULADO' WHERE num_requerimiento = 'P09-2026';
-- P10 queda sin cotizar (aparece en el reporte 12)

-- ---------------------------------------------------------------------
-- Cotizaciones [FICT]
-- ---------------------------------------------------------------------
INSERT INTO tb_cotizacion (num_cotizacion, fecha_cotizacion, moneda, num_requerimiento, ruc_proveedor) VALUES
('COT-NUT-031', '2026-10-07', 'USD', 'P06-2026', '20601234561'),
('COT-INS-118', '2026-10-07', 'PEN', 'P06-2026', '20455123987'),
('COT-DQA-207', '2026-10-08', 'PEN', 'P06-2026', '20539876541'),   -- no aprobada
('COT-CCM-089', '2026-10-21', 'PEN', 'P07-2026', '20456789013'),   -- su orden se anula
('COT-EAQ-044', '2026-10-22', 'PEN', 'P07-2026', '20498765432'),
('COT-CCM-090', '2026-10-23', 'PEN', 'P07-2026', '20456789013'),   -- nueva cotización de cajas
('COT-ALP-003', '2026-11-04', 'PEN', 'P08-2026', '20610730109'),
('COT-EDS-002', '2026-11-04', 'PEN', 'P08-2026', '20000000001');   -- no aprobada

INSERT INTO tb_detalle_cotizacion (num_cotizacion, codigo_producto, cantidad_cotizada, precio_unitario) VALUES
('COT-NUT-031', 'COL001',   50.00, 12.50),
('COT-NUT-031', 'VTC001',   20.00,  8.40),
('COT-INS-118', 'STV001',   25.00, 48.00),
('COT-INS-118', 'MDX001',  100.00,  6.20),
('COT-DQA-207', 'STV001',   25.00, 52.00),
('COT-DQA-207', 'MDX001',  100.00,  6.50),
('COT-CCM-089', 'CAJ012',  400.00,  1.45),
('COT-EAQ-044', 'ETQ150', 3000.00,  0.18),
('COT-EAQ-044', 'SLL060', 3000.00,  0.09),
('COT-CCM-090', 'CAJ012',  400.00,  1.35),
('COT-ALP-003', 'PFC150', 1500.00,  0.45),
('COT-ALP-003', 'TAP060', 1500.00,  0.25),
('COT-ALP-003', 'PFM150',  800.00,  0.85),
('COT-EDS-002', 'PFC150', 1500.00,  0.50),
('COT-EDS-002', 'TAP060', 1500.00,  0.28),
('COT-EDS-002', 'PFM150',  800.00,  0.95);

-- ---------------------------------------------------------------------
-- Órdenes de compra [FICT] (montos = suma de cantidad x precio x 1.18)
-- ---------------------------------------------------------------------
INSERT INTO tb_orden_compra (num_orden, fecha_emision, monto_total, num_cotizacion) VALUES
('RQP06/26-A', '2026-10-09',  935.74, 'COT-NUT-031'),   -- USD
('RQP06/26-B', '2026-10-10', 2147.60, 'COT-INS-118'),
('RQP07/26-B', '2026-10-22',  684.40, 'COT-CCM-089'),   -- se anula
('RQP07/26',   '2026-10-24',  955.80, 'COT-EAQ-044'),
('RQP07/26-C', '2026-10-24',  637.20, 'COT-CCM-090'),
('RQP08/26',   '2026-11-06', 2041.40, 'COT-ALP-003');

INSERT INTO tb_detalle_orden_compra (num_orden, codigo_producto, cantidad_ordenada) VALUES
('RQP06/26-A', 'COL001',   50.00),
('RQP06/26-A', 'VTC001',   20.00),
('RQP06/26-B', 'STV001',   25.00),
('RQP06/26-B', 'MDX001',  100.00),
('RQP07/26-B', 'CAJ012',  400.00),
('RQP07/26',   'ETQ150', 3000.00),
('RQP07/26',   'SLL060', 3000.00),
('RQP07/26-C', 'CAJ012',  400.00),
('RQP08/26',   'PFC150', 1500.00),
('RQP08/26',   'TAP060', 1500.00),
('RQP08/26',   'PFM150',  800.00);

-- La orden de cajas se anuló porque el proveedor mejoró su precio (COT-CCM-090)
UPDATE tb_orden_compra SET estado = 'ANULADO' WHERE num_orden = 'RQP07/26-B';

-- ---------------------------------------------------------------------
-- Pagos [FICT]: solicitados, ejecutados, parciales y anulados
-- ---------------------------------------------------------------------
INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                     cuenta_origen, cuenta_destino, area_responsable, num_orden) VALUES
-- RQP06/26-A (USD): pago completo ejecutado
('SOL-000251-26', '2026-10-08', '2026-10-10',    0.00, 935.74, 'ODAXFARMA', '00211223344556677889', 'Gerencia', 'RQP06/26-A'),
-- RQP06/26-B (PEN): adelanto ejecutado
('SOL-000252-26', '2026-10-10', '2026-10-12', 1000.00,   0.00, 'ODAXFARMA', '2153344556677', 'Gerencia', 'RQP06/26-B'),
-- RQP06/26-B: solicitud con monto equivocado, luego anulada
('SOL-000259-26', '2026-10-19', NULL,          500.00,   0.00, 'ODAXFARMA', '2153344556677', 'Gerencia', 'RQP06/26-B');

UPDATE tb_pago SET estado = 'ANULADO' WHERE num_solicitud = 'SOL-000259-26';

INSERT INTO tb_pago (num_solicitud, fecha_solicitud, fecha_ejecucion, monto_soles, monto_dolares,
                     cuenta_origen, cuenta_destino, area_responsable, num_orden) VALUES
-- RQP06/26-B: saldo solicitado, todavía sin ejecutar
('SOL-000258-26', '2026-10-20', NULL,         1147.60,   0.00, 'ODAXFARMA', '2153344556677', 'Gerencia', 'RQP06/26-B'),
-- RQP07/26: solicitado sin ejecutar
('SOL-000263-26', '2026-10-25', NULL,          955.80,   0.00, 'ODAXFARMA', '1914455667788', 'Gerencia', 'RQP07/26'),
-- RQP08/26: pagado por adelantado, mercadería aún no llega
('SOL-000270-26', '2026-11-05', '2026-11-07', 2041.40,   0.00, 'ODAXFARMA', '1942623880037', 'Gerencia', 'RQP08/26');

-- ---------------------------------------------------------------------
-- Guías de remisión [FICT]: completas, en dos entregas y parciales
-- ---------------------------------------------------------------------
INSERT INTO tb_guia_remision (num_guia, fecha_traslado, modalidad_traslado, peso_total,
                              punto_partida, punto_llegada, num_orden) VALUES
('G001-1201', '2026-10-14', 'PUBLICO', 72.50,  'Av. Argentina 1450, Cercado, Lima',
 'Mza. F Lote 16, Urb. Residencial La Fonda, Cerro Colorado, Arequipa', 'RQP06/26-A'),
('G002-0455', '2026-10-16', 'PRIVADO', 87.00,  'Calle Mercaderes 312, Cercado, Arequipa',
 'Mza. F Lote 16, Urb. Residencial La Fonda, Cerro Colorado, Arequipa', 'RQP06/26-B'),
('G002-0471', '2026-10-23', 'PRIVADO', 41.00,  'Calle Mercaderes 312, Cercado, Arequipa',
 'Mza. F Lote 16, Urb. Residencial La Fonda, Cerro Colorado, Arequipa', 'RQP06/26-B'),
('G003-0090', '2026-10-28', 'PRIVADO', 95.00,  'Av. Jesús 1203, Paucarpata, Arequipa',
 'Mza. F Lote 16, Urb. Residencial La Fonda, Cerro Colorado, Arequipa', 'RQP07/26-C');

INSERT INTO tb_detalle_guia (num_guia, codigo_producto, cantidad_recibida) VALUES
('G001-1201', 'COL001',  50.00),   -- completo
('G001-1201', 'VTC001',  20.00),   -- completo
('G002-0455', 'STV001',  25.00),   -- 1.a entrega: stevia completa
('G002-0455', 'MDX001',  60.00),   -- 1.a entrega: 60 de 100 kg
('G002-0471', 'MDX001',  40.00),   -- 2.a entrega: los 40 kg restantes
('G003-0090', 'CAJ012', 250.00);   -- parcial: 250 de 400 cajas

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobación
-- ---------------------------------------------------------------------
SELECT num_orden, razon_social, moneda, monto_total, monto_pagado, monto_por_ejecutar,
       saldo_pendiente, estado_pago, estado_recepcion, estado
FROM vw_estado_orden
ORDER BY fecha_emision;


-- #####################################################################
-- 7. USUARIO DEL APLICATIVO
-- #####################################################################

-- =====================================================================
-- 00_usuario_app.sql
-- Usuario con el que se conecta el aplicativo (principio de mínimo privilegio):
-- solo puede consultar (SELECT) y ejecutar procedimientos (EXECUTE).
-- No tiene INSERT, UPDATE ni DELETE directos: todo pasa por los procedimientos.
-- Ejecutar como root, una sola vez.
-- =====================================================================
CREATE USER IF NOT EXISTS 'odax_app'@'localhost' IDENTIFIED BY 'OdaxApp2026!';
GRANT SELECT, EXECUTE ON odaxfarma_compras.* TO 'odax_app'@'localhost';
FLUSH PRIVILEGES;


-- #####################################################################
-- 8. RESUMEN FINAL
-- #####################################################################

USE odaxfarma_compras;
SELECT
  (SELECT COUNT(*) FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = 'odaxfarma_compras' AND TABLE_TYPE = 'BASE TABLE')   AS tablas,
  (SELECT COUNT(*) FROM information_schema.VIEWS
    WHERE TABLE_SCHEMA = 'odaxfarma_compras')                                 AS vistas,
  (SELECT COUNT(*) FROM information_schema.ROUTINES
    WHERE ROUTINE_SCHEMA = 'odaxfarma_compras' AND ROUTINE_TYPE = 'PROCEDURE') AS procedimientos,
  (SELECT COUNT(*) FROM information_schema.TRIGGERS
    WHERE TRIGGER_SCHEMA = 'odaxfarma_compras')                               AS triggers,
  (SELECT COUNT(*) FROM tb_proveedor)            AS proveedores,
  (SELECT COUNT(*) FROM tb_producto)             AS productos,
  (SELECT COUNT(*) FROM tb_requerimiento_compra) AS requerimientos,
  (SELECT COUNT(*) FROM tb_cotizacion)           AS cotizaciones,
  (SELECT COUNT(*) FROM tb_orden_compra)         AS ordenes,
  (SELECT COUNT(*) FROM tb_pago)                 AS pagos,
  (SELECT COUNT(*) FROM tb_guia_remision)        AS guias;
