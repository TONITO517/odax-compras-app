"""Módulo Proveedores: configura la ventana genérica para tb_proveedor."""
from datos import proveedores
from .vista_maestro import VentanaMaestro

CAMPOS = [
    {"nombre": "ruc_proveedor", "etiqueta": "RUC", "ancho": 110, "clave": True},
    {"nombre": "razon_social", "etiqueta": "Razón social", "ancho": 260},
    {"nombre": "direccion", "etiqueta": "Dirección", "ancho": 320},
    {"nombre": "telefono", "etiqueta": "Teléfono", "ancho": 100},
]


def abrir(padre):
    VentanaMaestro(padre, "Proveedores", CAMPOS, proveedores)
