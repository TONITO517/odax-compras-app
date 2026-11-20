"""Acceso a datos del módulo Cotizaciones (tb_cotizacion y su detalle)."""
from .repositorio import ejecutar_sp


def listar(texto="", incluir_anulados=False):
    return ejecutar_sp("sp_cotizacion_listar", (texto, int(incluir_anulados)))


def _params(d):
    return (d["num_cotizacion"], d["fecha_cotizacion"], d["moneda"],
            d["num_requerimiento"], d["ruc_proveedor"])


def insertar(d):
    ejecutar_sp("sp_cotizacion_insertar", _params(d))


def modificar(d):
    ejecutar_sp("sp_cotizacion_modificar", _params(d))


def anular(num):
    ejecutar_sp("sp_cotizacion_anular", (num,))


def listar_detalle(num):
    return ejecutar_sp("sp_detcot_listar", (num,))


def guardar_detalle(num, codigo, d):
    ejecutar_sp("sp_detcot_guardar", (num, codigo, d["cantidad"], d["precio"]))


def quitar_detalle(num, codigo):
    ejecutar_sp("sp_detcot_quitar", (num, codigo))
