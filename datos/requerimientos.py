"""Acceso a datos del módulo Requerimientos (tb_requerimiento_compra y su detalle)."""
from .repositorio import ejecutar_sp


def listar(texto="", incluir_anulados=False):
    return ejecutar_sp("sp_requerimiento_listar", (texto, int(incluir_anulados)))


def insertar(d):
    ejecutar_sp("sp_requerimiento_insertar",
                (d["num_requerimiento"], d["fecha_requerimiento"], d["area_responsable"]))


def modificar(d):
    ejecutar_sp("sp_requerimiento_modificar",
                (d["num_requerimiento"], d["fecha_requerimiento"], d["area_responsable"]))


def anular(num):
    ejecutar_sp("sp_requerimiento_anular", (num,))


def listar_detalle(num):
    return ejecutar_sp("sp_detreq_listar", (num,))


def guardar_detalle(num, codigo, d):
    ejecutar_sp("sp_detreq_guardar", (num, codigo, d["cantidad"]))


def quitar_detalle(num, codigo):
    ejecutar_sp("sp_detreq_quitar", (num, codigo))
