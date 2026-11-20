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
