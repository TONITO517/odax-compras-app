"""Acceso a datos del módulo Guías de remisión (tb_guia_remision y su detalle)."""
from .repositorio import ejecutar_sp


def listar(texto="", incluir_anulados=False):
    return ejecutar_sp("sp_guia_listar", (texto, int(incluir_anulados)))


def insertar(d):
    ejecutar_sp("sp_guia_insertar",
                (d["num_guia"], d["fecha_traslado"], d["modalidad_traslado"], d["peso_total"],
                 d["punto_partida"], d["punto_llegada"], d["num_orden"]))


def modificar(d):
    ejecutar_sp("sp_guia_modificar",
                (d["num_guia"], d["fecha_traslado"], d["modalidad_traslado"], d["peso_total"],
                 d["punto_partida"], d["punto_llegada"]))


def anular(num):
    ejecutar_sp("sp_guia_anular", (num,))


def listar_detalle(num):
    return ejecutar_sp("sp_detguia_listar", (num,))


def guardar_detalle(num, codigo, d):
    ejecutar_sp("sp_detguia_guardar", (num, codigo, d["cantidad"]))


def quitar_detalle(num, codigo):
    ejecutar_sp("sp_detguia_quitar", (num, codigo))
