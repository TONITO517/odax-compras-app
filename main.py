"""
Punto de entrada del aplicativo Odax Farma – Gestión de Órdenes de Compra.

Arquitectura en tres capas:
    vistas/  -> interfaz gráfica (Tkinter)
    datos/   -> acceso a datos (conector nativo de MySQL, solo CALL a procedimientos)
    MySQL    -> procedimientos almacenados y triggers con las reglas del negocio
"""
from vistas.ventana_principal import VentanaPrincipal

if __name__ == "__main__":
    VentanaPrincipal().mainloop()
