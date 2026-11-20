"""Módulo Cotizaciones (cabecera + productos con cantidad y precio)."""
from datos import combos, cotizaciones
from .vista_documento import VentanaDocumento

COLUMNAS = [
    ("num_cotizacion", "N.° cotización", 120),
    ("fecha_cotizacion", "Fecha", 95),
    ("moneda", "Moneda", 70),
    ("num_requerimiento", "Requerimiento", 110),
    ("ruc_proveedor", "RUC", 105),
    ("razon_social", "Proveedor", 230),
    ("total_con_igv", "Total con IGV", 110),
    ("num_orden", "Orden generada", 110),
    ("estado", "Estado", 80),
]
CAMPOS = [
    {"nombre": "num_cotizacion", "etiqueta": "N.° cotización", "tipo": "texto", "clave": True},
    {"nombre": "fecha_cotizacion", "etiqueta": "Fecha (AAAA-MM-DD)", "tipo": "fecha"},
    {"nombre": "moneda", "etiqueta": "Moneda", "tipo": "opciones", "opciones": ["PEN", "USD"], "defecto": "PEN"},
    {"nombre": "num_requerimiento", "etiqueta": "Requerimiento", "tipo": "combo", "combo": combos.requerimientos},
    {"nombre": "ruc_proveedor", "etiqueta": "Proveedor", "tipo": "combo", "combo": combos.proveedores,
     "ancho": 40},
]
DETALLE = {
    "titulo": "Productos cotizados (precio sin IGV; el precio con IGV se calcula)",
    "columnas": [("codigo_producto", "Código", 90), ("descripcion", "Descripción", 330),
                 ("unidad_medida", "Unidad", 70), ("cantidad_cotizada", "Cantidad", 90),
                 ("precio_unitario", "P. unitario", 90), ("precio_con_igv", "P. con IGV", 90),
                 ("subtotal_con_igv", "Subtotal con IGV", 120)],
    "listar": cotizaciones.listar_detalle,
    "productos": combos.productos_de_requerimiento,
    "campos": [("cantidad", "Cantidad", "cantidad_cotizada"), ("precio", "Precio sin IGV", "precio_unitario")],
    "guardar": cotizaciones.guardar_detalle,
    "quitar": cotizaciones.quitar_detalle,
}


def abrir(padre):
    VentanaDocumento(padre, "Cotizaciones", COLUMNAS, CAMPOS, cotizaciones, DETALLE)
