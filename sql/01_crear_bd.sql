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
