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

-- Para poder recargar sin errores de clave duplicada.
-- SOLO PARA EL ENTORNO DE PRUEBAS: en uso real no se borra el historial;
-- el aplicativo anula los registros (borrado lógico).
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE tb_detalle_guia;
TRUNCATE TABLE tb_detalle_orden_compra;
TRUNCATE TABLE tb_detalle_cotizacion;
TRUNCATE TABLE tb_detalle_requerimiento;
TRUNCATE TABLE tb_guia_remision;
TRUNCATE TABLE tb_pago;
TRUNCATE TABLE tb_orden_compra;
TRUNCATE TABLE tb_cotizacion;
TRUNCATE TABLE tb_requerimiento_compra;
TRUNCATE TABLE tb_producto;
TRUNCATE TABLE tb_proveedor;
TRUNCATE TABLE tb_auditoria;
SET FOREIGN_KEY_CHECKS = 1;

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
