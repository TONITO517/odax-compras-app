"""Módulo Requerimientos de compra (cabecera + productos requeridos)."""
from datos import combos, requerimientos
from .vista_documento import VentanaDocumento

COLUMNAS = [
    ("num_requerimiento", "N.° requerimiento", 140),
    ("fecha_requerimiento", "Fecha", 100),
    ("area_responsable", "Área responsable", 200),
    ("productos", "Productos", 90),
    ("estado", "Estado", 90),
]
CAMPOS = [
    {"nombre": "num_requerimiento", "etiqueta": "N.° requerimiento", "tipo": "texto", "clave": True},
    {"nombre": "fecha_requerimiento", "etiqueta": "Fecha (AAAA-MM-DD)", "tipo": "fecha"},
    {"nombre": "area_responsable", "etiqueta": "Área responsable", "tipo": "texto",
     "defecto": "Área de Producción"},
]
DETALLE = {
    "titulo": "Productos requeridos",
    "columnas": [("codigo_producto", "Código", 100), ("descripcion", "Descripción", 420),
                 ("unidad_medida", "Unidad", 90), ("cantidad_formulada", "Cantidad", 110)],
    "listar": requerimientos.listar_detalle,
    "productos": lambda _num: combos.productos(),
    "campos": [("cantidad", "Cantidad", "cantidad_formulada")],
    "guardar": requerimientos.guardar_detalle,
    "quitar": requerimientos.quitar_detalle,
}


def abrir(padre):
    VentanaDocumento(padre, "Requerimientos de compra", COLUMNAS, CAMPOS, requerimientos, DETALLE)
