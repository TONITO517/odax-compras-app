"""Acceso a datos del módulo Proveedores (tb_proveedor)."""
from .repositorio import ejecutar_sp


def listar(texto: str = "", incluir_inactivos: bool = False):
    return ejecutar_sp("sp_proveedor_listar", (texto, int(incluir_inactivos)))


def insertar(ruc, razon_social, direccion, telefono):
    ejecutar_sp("sp_proveedor_insertar", (ruc, razon_social, direccion, telefono))


def modificar(ruc, razon_social, direccion, telefono):
    ejecutar_sp("sp_proveedor_modificar", (ruc, razon_social, direccion, telefono))


def anular(ruc):
    ejecutar_sp("sp_proveedor_anular", (ruc,))


def reactivar(ruc):
    ejecutar_sp("sp_proveedor_reactivar", (ruc,))
