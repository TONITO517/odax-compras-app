"""
Capa de interfaz – ventana genérica para tablas maestras.

Una sola clase sirve para Proveedores y Productos: recibe la descripción de
los campos y las funciones de la capa de datos, y arma la búsqueda, la
lista, el formulario y los botones Nuevo, Guardar, Anular y Reactivar.
"""
import tkinter as tk
from tkinter import messagebox, ttk

from datos.repositorio import ErrorBD


class VentanaMaestro(tk.Toplevel):
    def __init__(self, padre, titulo, campos, modulo_datos):
        """
        campos: lista de diccionarios con
            nombre    -> nombre de la columna que devuelve el procedimiento
            etiqueta  -> texto que ve el usuario
            ancho     -> ancho de la columna en la lista
            clave     -> True si es la clave primaria (no se edita)
            opciones  -> lista de valores si es un combo (opcional)
        modulo_datos: módulo de la capa de datos con listar, insertar,
            modificar, anular y reactivar.
        """
        super().__init__(padre)
        self.title(titulo)
        self.geometry("980x560")
        self.campos = campos
        self.datos = modulo_datos
        self.modo_nuevo = True
        self.variables = {c["nombre"]: tk.StringVar() for c in campos}
        self.entradas = {}

        self._crear_busqueda()
        self._crear_lista()
        self._crear_formulario()
        self.cargar()

    # ---------------------------------------------------------------- UI
    def _crear_busqueda(self):
        marco = ttk.Frame(self, padding=8)
        marco.pack(fill="x")
        ttk.Label(marco, text="Buscar:").pack(side="left")
        self.texto_busqueda = tk.StringVar()
        entrada = ttk.Entry(marco, textvariable=self.texto_busqueda, width=40)
        entrada.pack(side="left", padx=6)
        entrada.bind("<Return>", lambda _e: self.cargar())
        self.ver_inactivos = tk.BooleanVar(value=False)
        ttk.Checkbutton(marco, text="Mostrar anulados", variable=self.ver_inactivos,
                        command=self.cargar).pack(side="left", padx=6)
        ttk.Button(marco, text="Buscar", command=self.cargar).pack(side="left")

    def _crear_lista(self):
        marco = ttk.Frame(self, padding=(8, 0))
        marco.pack(fill="both", expand=True)
        columnas = [c["nombre"] for c in self.campos] + ["estado"]
        self.lista = ttk.Treeview(marco, columns=columnas, show="headings", height=12)
        for c in self.campos:
            self.lista.heading(c["nombre"], text=c["etiqueta"])
            self.lista.column(c["nombre"], width=c.get("ancho", 120))
        self.lista.heading("estado", text="Estado")
        self.lista.column("estado", width=80, anchor="center")
        self.lista.tag_configure("inactivo", foreground="gray")
        barra = ttk.Scrollbar(marco, orient="vertical", command=self.lista.yview)
        self.lista.configure(yscrollcommand=barra.set)
        self.lista.pack(side="left", fill="both", expand=True)
        barra.pack(side="right", fill="y")
        self.lista.bind("<<TreeviewSelect>>", self._al_seleccionar)

    def _crear_formulario(self):
        marco = ttk.LabelFrame(self, text="Datos del registro", padding=8)
        marco.pack(fill="x", padx=8, pady=8)
        for i, c in enumerate(self.campos):
            fila, col = divmod(i, 2)
            ttk.Label(marco, text=c["etiqueta"] + ":").grid(row=fila, column=col * 2, sticky="e", padx=4, pady=3)
            if c.get("opciones"):
                w = ttk.Combobox(marco, textvariable=self.variables[c["nombre"]],
                                 values=c["opciones"], state="readonly", width=38)
            else:
                w = ttk.Entry(marco, textvariable=self.variables[c["nombre"]], width=40)
            w.grid(row=fila, column=col * 2 + 1, sticky="w", padx=4, pady=3)
            self.entradas[c["nombre"]] = w

        botones = ttk.Frame(marco)
        botones.grid(row=10, column=0, columnspan=4, pady=(8, 0))
        ttk.Button(botones, text="Nuevo", command=self.nuevo).pack(side="left", padx=4)
        ttk.Button(botones, text="Guardar", command=self.guardar).pack(side="left", padx=4)
        ttk.Button(botones, text="Anular", command=self.anular).pack(side="left", padx=4)
        ttk.Button(botones, text="Reactivar", command=self.reactivar).pack(side="left", padx=4)
        ttk.Button(botones, text="Cerrar", command=self.destroy).pack(side="left", padx=4)
        self.estado = ttk.Label(marco, text="Modo: nuevo registro", foreground="#1F3864")
        self.estado.grid(row=11, column=0, columnspan=4, pady=(6, 0))

    # ----------------------------------------------------------- acciones
    def _clave(self):
        return next(c["nombre"] for c in self.campos if c.get("clave"))

    def _valores_formulario(self):
        return [self.variables[c["nombre"]].get().strip() or None for c in self.campos]

    def _mostrar_error(self, e):
        messagebox.showerror("No se pudo completar", str(e), parent=self)

    def cargar(self):
        """Pide la lista al procedimiento sp_..._listar y la muestra."""
        try:
            _cols, filas = self.datos.listar(self.texto_busqueda.get().strip(), self.ver_inactivos.get())
        except ErrorBD as e:
            self._mostrar_error(e)
            return
        self.lista.delete(*self.lista.get_children())
        for f in filas:
            valores = ["" if v is None else v for v in f]
            tag = ("inactivo",) if valores[-1] != "ACTIVO" else ()
            self.lista.insert("", "end", values=valores, tags=tag)

    def _al_seleccionar(self, _evento):
        seleccion = self.lista.selection()
        if not seleccion:
            return
        valores = self.lista.item(seleccion[0], "values")
        for c, v in zip(self.campos, valores):
            self.variables[c["nombre"]].set(v)
        self.entradas[self._clave()].configure(state="disabled")
        self.modo_nuevo = False
        self.estado.configure(text=f"Modo: modificar ({valores[-1]})")

    def nuevo(self):
        for v in self.variables.values():
            v.set("")
        self.entradas[self._clave()].configure(state="normal")
        self.lista.selection_remove(self.lista.selection())
        self.modo_nuevo = True
        self.estado.configure(text="Modo: nuevo registro")
        self.entradas[self._clave()].focus_set()

    def guardar(self):
        valores = self._valores_formulario()
        if valores[0] is None:
            messagebox.showwarning("Falta un dato", "Complete el campo clave.", parent=self)
            return
        try:
            if self.modo_nuevo:
                self.datos.insertar(*valores)
                messagebox.showinfo("Listo", "Registro insertado.", parent=self)
            else:
                self.datos.modificar(*valores)
                messagebox.showinfo("Listo", "Registro modificado.", parent=self)
        except ErrorBD as e:
            self._mostrar_error(e)
            return
        self.cargar()
        self.nuevo()

    def _accion_estado(self, funcion, verbo):
        clave = self.variables[self._clave()].get().strip()
        if not clave or self.modo_nuevo:
            messagebox.showwarning("Seleccione", "Seleccione un registro de la lista.", parent=self)
            return
        if not messagebox.askyesno("Confirmar", f"¿Desea {verbo} el registro {clave}?", parent=self):
            return
        try:
            funcion(clave)
        except ErrorBD as e:
            self._mostrar_error(e)
            return
        self.cargar()
        self.nuevo()

    def anular(self):
        self._accion_estado(self.datos.anular, "anular")

    def reactivar(self):
        self._accion_estado(self.datos.reactivar, "reactivar")
