"""Módulo Guías de remisión: recepción de la mercadería (admite entregas parciales)."""
from datos import combos, guias
from .vista_documento import VentanaDocumento

COLUMNAS = [
    ("num_guia", "N.° guía", 115),
    ("fecha_traslado", "Traslado", 90),
    ("modalidad_traslado", "Modalidad", 85),
    ("peso_total", "Peso (kg)", 75),
    ("punto_partida", "Partida", 210),
    ("punto_llegada", "Llegada", 210),
    ("num_orden", "Orden", 100),
    ("razon_social", "Proveedor", 180),
    ("estado", "Estado", 75),
]
CAMPOS = [
    {"nombre": "num_guia", "etiqueta": "N.° guía", "tipo": "texto", "clave": True},
    {"nombre": "fecha_traslado", "etiqueta": "Fecha traslado", "tipo": "fecha"},
    {"nombre": "num_orden", "etiqueta": "Orden de compra", "tipo": "combo", "combo": combos.ordenes,
     "solo_nuevo": True, "ancho": 42},
    {"nombre": "modalidad_traslado", "etiqueta": "Modalidad", "tipo": "opciones",
     "opciones": ["PRIVADO", "PUBLICO"], "defecto": "PRIVADO"},
    {"nombre": "peso_total", "etiqueta": "Peso total (kg)", "tipo": "numero"},
    {"nombre": "punto_partida", "etiqueta": "Punto de partida", "tipo": "texto"},
    {"nombre": "punto_llegada", "etiqueta": "Punto de llegada", "tipo": "texto",
     "defecto": "Mza. F Lote 16, Urb. Residencial La Fonda, Cerro Colorado, Arequipa"},
]
DETALLE = {
    "titulo": "Productos recibidos en esta guía (no pueden superar lo ordenado)",
    "columnas": [("codigo_producto", "Código", 90), ("descripcion", "Descripción", 420),
                 ("unidad_medida", "Unidad", 70), ("cantidad_ordenada", "Ordenado", 100),
                 ("cantidad_recibida", "Recibido aquí", 110)],
    "listar": guias.listar_detalle,
    "productos": combos.productos_de_orden,
    "campos": [("cantidad", "Cantidad recibida", "cantidad_recibida")],
    "guardar": guias.guardar_detalle,
    "quitar": guias.quitar_detalle,
}


def abrir(padre):
    VentanaDocumento(padre, "Guías de remisión", COLUMNAS, CAMPOS, guias, DETALLE)
