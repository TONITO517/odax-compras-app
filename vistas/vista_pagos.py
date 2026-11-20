"""Módulo Pagos: se SOLICITAN y luego se EJECUTAN (fecha de la transferencia)."""
from datetime import date
from tkinter import messagebox, simpledialog

from datos import combos, pagos
from datos.repositorio import ErrorBD
from .vista_documento import VentanaDocumento

COLUMNAS = [
    ("num_solicitud", "N.° solicitud", 115),
    ("fecha_solicitud", "Solicitado", 90),
    ("fecha_ejecucion", "Ejecutado", 90),
    ("num_orden", "Orden", 100),
    ("razon_social", "Proveedor", 190),
    ("moneda", "Moneda", 60),
    ("monto", "Monto", 85),
    ("cuenta_origen", "Cta. origen", 95),
    ("cuenta_destino", "Cta. destino", 120),
    ("area_responsable", "Área", 90),
    ("situacion", "Situación", 95),
    ("estado", "Estado", 75),
]
CAMPOS = [
    {"nombre": "num_solicitud", "etiqueta": "N.° solicitud", "tipo": "texto", "clave": True},
    {"nombre": "fecha_solicitud", "etiqueta": "Fecha solicitud", "tipo": "fecha"},
    {"nombre": "num_orden", "etiqueta": "Orden de compra", "tipo": "combo", "combo": combos.ordenes,
     "solo_nuevo": True, "ancho": 42},
    {"nombre": "monto", "etiqueta": "Monto (moneda de la orden)", "tipo": "numero"},
    {"nombre": "cuenta_origen", "etiqueta": "Cuenta origen", "tipo": "texto", "defecto": "ODAXFARMA"},
    {"nombre": "cuenta_destino", "etiqueta": "Cuenta destino", "tipo": "texto"},
    {"nombre": "area_responsable", "etiqueta": "Área responsable", "tipo": "texto", "defecto": "Gerencia"},
]


def ejecutar_pago(ventana):
    """Botón extra: registra la fecha en que se realizó la transferencia."""
    clave = ventana.clave_actual
    if clave is None:
        messagebox.showwarning("Seleccione", "Seleccione una solicitud de pago de la lista.", parent=ventana)
        return
    fecha = simpledialog.askstring("Ejecutar pago", f"Fecha de ejecución de {clave} (AAAA-MM-DD):",
                                   initialvalue=date.today().isoformat(), parent=ventana)
    if not fecha:
        return
    try:
        pagos.ejecutar(clave, fecha.strip())
    except ErrorBD as e:
        ventana.mostrar_error(e)
        return
    messagebox.showinfo("Listo", f"Pago {clave} ejecutado el {fecha.strip()}.", parent=ventana)
    ventana.cargar()
    ventana.seleccionar(clave)


def abrir(padre):
    VentanaDocumento(padre, "Pagos (solicitud y ejecución)", COLUMNAS, CAMPOS, pagos,
                     acciones=[("Ejecutar pago", ejecutar_pago)])
