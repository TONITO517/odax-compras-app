"""
Acceso a datos del módulo Reportes.

Cada reporte es un procedimiento almacenado (sp_rep_...). Este módulo
describe los reportes disponibles (nombre, descripción y parámetros) y los
ejecuta. 9 de los 12 reportes usan JOIN entre varias tablas.
"""
from .repositorio import ejecutar_sp

# Tipos de parámetro: "fecha" (opcional), "entero", "requerimiento", "orden", "producto", "tabla"
REPORTES = [
    {"sp": "sp_rep_01_trazabilidad", "nombre": "01. Trazabilidad del proceso de compra",
     "descripcion": "Recorre cada requerimiento hasta sus cotizaciones, órdenes, pagos y guías, "
                    "con el estado real de pago y de recepción.",
     "parametros": [("requerimiento", "Requerimiento (vacío = todos)")]},
    {"sp": "sp_rep_02_compras_por_proveedor", "nombre": "02. Compras por proveedor",
     "descripcion": "Total ordenado, pagado (solo pagos ejecutados) y saldo por proveedor y moneda.",
     "parametros": [("fecha", "Desde"), ("fecha", "Hasta")]},
    {"sp": "sp_rep_03_ordenes_pendientes", "nombre": "03. Órdenes pendientes de pago o recepción",
     "descripcion": "Órdenes que todavía no están pagadas o no se recibieron completas.",
     "parametros": []},
    {"sp": "sp_rep_04_ordenado_vs_recibido", "nombre": "04. Ordenado vs. recibido por producto",
     "descripcion": "Compara lo pedido con lo recibido en todas las guías; muestra lo pendiente.",
     "parametros": [("orden", "Orden (vacío = todas)")]},
    {"sp": "sp_rep_05_estado_financiero", "nombre": "05. Estado financiero de las órdenes",
     "descripcion": "Separa lo solicitado sin ejecutar de lo efectivamente pagado y calcula el saldo.",
     "parametros": []},
    {"sp": "sp_rep_06_pagos_por_ejecutar", "nombre": "06. Pagos solicitados sin ejecutar",
     "descripcion": "Solicitudes de pago que esperan la transferencia, con los días de espera.",
     "parametros": []},
    {"sp": "sp_rep_07_comparar_cotizaciones", "nombre": "07. Comparación de cotizaciones",
     "descripcion": "Subtotal, IGV y total de las cotizaciones de un requerimiento y cuál se aprobó.",
     "parametros": [("requerimiento", "Requerimiento (vacío = todos)")]},
    {"sp": "sp_rep_08_historial_producto", "nombre": "08. Historial de compras de un producto",
     "descripcion": "En qué órdenes se compró el producto, a qué proveedor, cuánto y a qué precio.",
     "parametros": [("producto", "Producto (vacío = todos)")]},
    {"sp": "sp_rep_09_ordenes_por_fecha", "nombre": "09. Órdenes por rango de fechas",
     "descripcion": "Órdenes emitidas en un periodo, incluidas las anuladas.",
     "parametros": [("fecha", "Desde"), ("fecha", "Hasta")]},
    {"sp": "sp_rep_10_productos_mas_comprados", "nombre": "10. Productos más comprados",
     "descripcion": "Ranking de productos por número de órdenes y cantidad ordenada.",
     "parametros": [("entero", "Cantidad de productos (top)")]},
    {"sp": "sp_rep_11_auditoria", "nombre": "11. Auditoría de operaciones",
     "descripcion": "Operaciones registradas por los triggers: qué, quién y cuándo.",
     "parametros": [("fecha", "Desde"), ("fecha", "Hasta"), ("tabla", "Tabla (vacío = todas)")]},
    {"sp": "sp_rep_12_productos_sin_cotizar", "nombre": "12. Productos requeridos sin cotizar",
     "descripcion": "Productos de un requerimiento que todavía no tienen ninguna cotización.",
     "parametros": [("requerimiento", "Requerimiento (vacío = todos)")]},
]

TABLAS_AUDITADAS = ["tb_proveedor", "tb_producto", "tb_requerimiento_compra", "tb_cotizacion",
                    "tb_orden_compra", "tb_pago", "tb_guia_remision"]


def ejecutar(sp: str, parametros: tuple):
    """Ejecuta el reporte y devuelve (columnas, filas)."""
    return ejecutar_sp(sp, parametros)
