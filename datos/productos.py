"""Acceso a datos del módulo Productos (tb_producto)."""
from .repositorio import ejecutar_sp


def listar(texto: str = "", incluir_inactivos: bool = False):
    return ejecutar_sp("sp_producto_listar", (texto, int(incluir_inactivos)))


def insertar(codigo, descripcion, tipo_envase, unidad_medida):
    ejecutar_sp("sp_producto_insertar", (codigo, descripcion, tipo_envase, unidad_medida))


def modificar(codigo, descripcion, tipo_envase, unidad_medida):
    ejecutar_sp("sp_producto_modificar", (codigo, descripcion, tipo_envase, unidad_medida))


def anular(codigo):
    ejecutar_sp("sp_producto_anular", (codigo,))


def reactivar(codigo):
    ejecutar_sp("sp_producto_reactivar", (codigo,))
