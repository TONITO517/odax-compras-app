"""Acceso a datos para llenar las listas desplegables (combos) de las ventanas."""
from .repositorio import ejecutar_sp


def _pares(nombre, parametros=()):
    """Devuelve una lista de (código, texto) a partir de un procedimiento."""
    _cols, filas = ejecutar_sp(nombre, parametros)
    return [(str(f[0]), str(f[1])) for f in filas]


def proveedores():
    return _pares("sp_combo_proveedores")


def productos():
    return _pares("sp_combo_productos")


def requerimientos():
    return _pares("sp_combo_requerimientos")


def cotizaciones_sin_orden():
    return _pares("sp_combo_cotizaciones_sin_orden")


def ordenes():
    return _pares("sp_combo_ordenes")


def productos_de_requerimiento(num_cotizacion):
    return _pares("sp_combo_productos_requerimiento", (num_cotizacion,))


def productos_de_orden(num_guia):
    return _pares("sp_combo_productos_orden", (num_guia,))
