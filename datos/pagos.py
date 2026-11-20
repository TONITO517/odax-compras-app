"""Acceso a datos del módulo Pagos (tb_pago): solicitar, ejecutar y anular."""
from .repositorio import ejecutar_sp


def listar(texto="", incluir_anulados=False):
    return ejecutar_sp("sp_pago_listar", (texto, int(incluir_anulados)))


def insertar(d):
    """Registra la SOLICITUD de pago (todavía sin ejecutar)."""
    ejecutar_sp("sp_pago_solicitar",
                (d["num_solicitud"], d["fecha_solicitud"], d["monto"], d["cuenta_origen"],
                 d["cuenta_destino"], d["area_responsable"], d["num_orden"]))


def modificar(d):
    ejecutar_sp("sp_pago_modificar",
                (d["num_solicitud"], d["fecha_solicitud"], d["monto"], d["cuenta_origen"],
                 d["cuenta_destino"], d["area_responsable"]))


def ejecutar(num, fecha_ejecucion):
    """Registra la fecha en que se realizó la transferencia."""
    ejecutar_sp("sp_pago_ejecutar", (num, fecha_ejecucion))


def anular(num):
    ejecutar_sp("sp_pago_anular", (num,))
