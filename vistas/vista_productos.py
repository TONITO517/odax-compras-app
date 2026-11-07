"""Módulo Productos: configura la ventana genérica para tb_producto."""
from datos import productos
from .vista_maestro import VentanaMaestro

CAMPOS = [
    {"nombre": "codigo_producto", "etiqueta": "Código", "ancho": 100, "clave": True},
    {"nombre": "descripcion", "etiqueta": "Descripción", "ancho": 380},
    {"nombre": "tipo_envase", "etiqueta": "Tipo de envase", "ancho": 130},
    {"nombre": "unidad_medida", "etiqueta": "Unidad", "ancho": 90, "opciones": ["UNIDAD", "KG"]},
]


def abrir(padre):
    VentanaMaestro(padre, "Productos", CAMPOS, productos)
