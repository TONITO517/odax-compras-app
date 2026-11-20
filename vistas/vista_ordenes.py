"""Módulo Órdenes de compra: se generan desde una cotización y muestran su estado real."""
from datos import combos, ordenes
from .vista_documento import VentanaDocumento

COLUMNAS = [
    ("num_orden", "N.° orden", 110),
    ("fecha_emision", "Emisión", 90),
    ("num_cotizacion", "Cotización", 100),
    ("razon_social", "Proveedor", 200),
    ("moneda", "Moneda", 60),
    ("monto_total", "Total", 85),
    ("monto_pagado", "Pagado", 85),
    ("saldo_pendiente", "Saldo", 85),
    ("estado_pago", "Estado pago", 95),
    ("estado_recepcion", "Recepción", 95),
    ("estado", "Estado", 75),
]
CAMPOS = [
    {"nombre": "num_orden", "etiqueta": "N.° orden", "tipo": "texto", "clave": True},
    {"nombre": "fecha_emision", "etiqueta": "Fecha (AAAA-MM-DD)", "tipo": "fecha"},
    {"nombre": "num_cotizacion", "etiqueta": "Cotización aprobada", "tipo": "combo",
     "combo": combos.cotizaciones_sin_orden, "solo_nuevo": True, "ancho": 42},
    {"nombre": "monto_total", "etiqueta": "Monto total (vacío = calcular)", "tipo": "numero", "opcional": True},
]
DETALLE = {
    "titulo": "Productos de la orden (copiados de la cotización)",
    "columnas": [("codigo_producto", "Código", 90), ("descripcion", "Descripción", 380),
                 ("unidad_medida", "Unidad", 70), ("cantidad_ordenada", "Ordenado", 100),
                 ("cantidad_recibida", "Recibido", 100), ("pendiente", "Pendiente", 100)],
    "listar": ordenes.listar_detalle,
    "productos": ordenes.productos_detalle,
    "campos": [("cantidad", "Cantidad ordenada", "cantidad_ordenada")],
    "guardar": ordenes.guardar_detalle,
    "quitar": ordenes.quitar_detalle,
}


def abrir(padre):
    VentanaDocumento(padre, "Órdenes de compra", COLUMNAS, CAMPOS, ordenes, DETALLE)
