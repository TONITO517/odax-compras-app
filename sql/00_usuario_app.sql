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
