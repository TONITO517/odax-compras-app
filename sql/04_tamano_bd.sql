-- =====================================================================
-- 04_tamano_bd.sql
-- Tamaño actual de odaxfarma_compras (Modelo físico 2: almacenamiento)
-- =====================================================================

USE odaxfarma_compras;
SET SESSION information_schema_stats_expiry = 0;   -- para que no muestre datos en caché

ANALYZE TABLE tb_proveedor, tb_producto, tb_requerimiento_compra, tb_cotizacion,
  tb_orden_compra, tb_pago, tb_guia_remision, tb_detalle_requerimiento,
  tb_detalle_cotizacion, tb_detalle_orden_compra, tb_detalle_guia;

-- Tamaño por tabla
SELECT table_name AS tabla,
       table_rows AS filas,
       ROUND(data_length / 1024, 1)  AS datos_kb,
       ROUND(index_length / 1024, 1) AS indices_kb,
       ROUND((data_length + index_length) / 1024, 1) AS total_kb
FROM information_schema.TABLES
WHERE table_schema = 'odaxfarma_compras' AND table_type = 'BASE TABLE'
ORDER BY total_kb DESC;

-- Tamaño total de la BD
SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.TABLES
WHERE table_schema = 'odaxfarma_compras';

-- Ficheros físicos (.ibd) y dónde están
SELECT @@datadir AS carpeta_de_datos;

SELECT name AS fichero,
       ROUND(file_size / 1024) AS tamano_kb
FROM information_schema.INNODB_TABLESPACES
WHERE name LIKE 'odaxfarma_compras/%'
ORDER BY tamano_kb DESC;
