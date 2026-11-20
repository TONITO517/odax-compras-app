"""Acceso a datos del módulo Órdenes de compra (tb_orden_compra y su detalle)."""
from .repositorio import ejecutar_sp


def listar(texto="", incluir_anulados=False):
    return ejecutar_sp("sp_orden_listar", (texto, int(incluir_anulados)))


def insertar(d):
    """Genera la orden desde la cotización; si no hay monto, se calcula con IGV."""
    ejecutar_sp("sp_orden_generar",
                (d["num_orden"], d["fecha_emision"], d["num_cotizacion"], d.get("monto_total")))


def modificar(d):
    ejecutar_sp("sp_orden_modificar", (d["num_orden"], d["fecha_emision"], d.get("monto_total")))


def anular(num):
    ejecutar_sp("sp_orden_anular", (num,))


def listar_detalle(num):
    return ejecutar_sp("sp_detoc_listar", (num,))


def productos_detalle(num):
    """Productos que ya están en la orden (solo se ajusta su cantidad)."""
    _cols, filas = listar_detalle(num)
    return [(str(f[0]), str(f[1])) for f in filas]


def guardar_detalle(num, codigo, d):
    ejecutar_sp("sp_detoc_guardar", (num, codigo, d["cantidad"]))


def quitar_detalle(num, codigo):
    ejecutar_sp("sp_detoc_quitar", (num, codigo))
