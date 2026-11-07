"""
Capa de interfaz – ventana principal del aplicativo.

Muestra el menú de módulos y, en la barra inferior, el estado de la
conexión con la base de datos.
"""
import tkinter as tk
from tkinter import messagebox, ttk

from datos.conexion import probar_conexion
from . import vista_productos, vista_proveedores

NOMBRE_APP = "Odax Farma – Gestión de Órdenes de Compra"


class VentanaPrincipal(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(NOMBRE_APP)
        self.geometry("900x520")
        self._crear_menu()
        self._crear_portada()
        self._crear_barra_estado()
        self.after(200, self.verificar_conexion)

    def _crear_menu(self):
        barra = tk.Menu(self)

        archivo = tk.Menu(barra, tearoff=0)
        archivo.add_command(label="Salir", command=self.destroy)
        barra.add_cascade(label="Archivo", menu=archivo)

        maestros = tk.Menu(barra, tearoff=0)
        maestros.add_command(label="Proveedores", command=lambda: vista_proveedores.abrir(self))
        maestros.add_command(label="Productos", command=lambda: vista_productos.abrir(self))
        barra.add_cascade(label="Maestros", menu=maestros)

        documentos = tk.Menu(barra, tearoff=0)
        for nombre in ("Requerimientos", "Cotizaciones", "Órdenes de compra",
                       "Pagos", "Guías de remisión"):
            documentos.add_command(label=nombre + " (en construcción)", state="disabled")
        barra.add_cascade(label="Documentos", menu=documentos)

        reportes = tk.Menu(barra, tearoff=0)
        reportes.add_command(label="Reportes (en construcción)", state="disabled")
        barra.add_cascade(label="Reportes", menu=reportes)

        ayuda = tk.Menu(barra, tearoff=0)
        ayuda.add_command(label="Probar conexión", command=lambda: self.verificar_conexion(mostrar=True))
        ayuda.add_command(label="Acerca de", command=self._acerca_de)
        barra.add_cascade(label="Ayuda", menu=ayuda)

        self.config(menu=barra)

    def _crear_portada(self):
        marco = ttk.Frame(self, padding=40)
        marco.pack(fill="both", expand=True)
        ttk.Label(marco, text="Odax Farma S.R.L.", font=("Segoe UI", 22, "bold")).pack(pady=(40, 6))
        ttk.Label(marco, text="Gestión de Órdenes de Compra", font=("Segoe UI", 14)).pack()
        ttk.Label(marco, text="Use el menú superior para abrir los módulos.",
                  foreground="gray").pack(pady=20)

    def _crear_barra_estado(self):
        self.barra_estado = ttk.Label(self, text="Verificando conexión…", relief="sunken",
                                      anchor="w", padding=(8, 3))
        self.barra_estado.pack(side="bottom", fill="x")

    def verificar_conexion(self, mostrar=False):
        ok, mensaje = probar_conexion()
        self.barra_estado.configure(text=("● " if ok else "✖ ") + mensaje,
                                    foreground="green" if ok else "red")
        if mostrar or not ok:
            (messagebox.showinfo if ok else messagebox.showerror)("Conexión", mensaje, parent=self)

    def _acerca_de(self):
        messagebox.showinfo("Acerca de", NOMBRE_APP + "\nGestión de Datos e Información – UCSM\nPython + Tkinter + MySQL 8.0",
                            parent=self)
